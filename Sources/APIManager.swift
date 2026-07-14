import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let stream: Bool
    let max_tokens: Int
}

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }
        let message: Message
        let finish_reason: String?
    }
    let choices: [Choice]
}

struct TTSRequest: Codable {
    let model: String
    let input: String
    let voice: String
    let speed: Double
}

struct VoicesResponse: Codable {
    let voices: [String]
}

struct PronunciationPhoneme: Decodable, Equatable, Hashable {
    let grapheme: String
    let phoneme: String
    let score: Double
    let is_correct: Bool
}

struct PronunciationAssessmentResponse: Decodable, Equatable {
    let overall_score: Double
    let is_correct: Bool
    /// Per-phoneme breakdown (removed in server v2.2+ — word-level assessment only).
    /// Optional for backward compatibility with older servers.
    let phonemes: [PronunciationPhoneme]?
    let predicted_phonemes: [String]
    let target_phonemes: [String]
    /// Human-readable tip from the server (word-level feedback in v2.2+).
    let feedback: String?
    /// Present when the server was called with `"debug": true`.
    let debug: PronunciationDebugInfo?

    init(
        overall_score: Double,
        is_correct: Bool,
        phonemes: [PronunciationPhoneme]? = nil,
        predicted_phonemes: [String],
        target_phonemes: [String],
        feedback: String? = nil,
        debug: PronunciationDebugInfo? = nil
    ) {
        self.overall_score = overall_score
        self.is_correct = is_correct
        self.phonemes = phonemes
        self.predicted_phonemes = predicted_phonemes
        self.target_phonemes = target_phonemes
        self.feedback = feedback
        self.debug = debug
    }

    /// Returns server `feedback` if present, otherwise synthesizes word-level feedback.
    var displayFeedback: String {
        if let feedback, !feedback.isEmpty { return feedback }
        if is_correct { return "Great pronunciation!" }
        if overall_score >= 0.50 { return "Close — try once more, a bit clearer." }
        if overall_score >= 0.25 { return "Not quite — give it another try." }
        return "Let's try that word again."
    }

    /// Compact line for logs / debug UI: what the model heard vs expected.
    var diagnosticSummary: String {
        let pct = Int((overall_score * 100).rounded())
        let heard = predicted_phonemes.isEmpty ? "(none)" : predicted_phonemes.joined(separator: " ")
        let target = target_phonemes.isEmpty ? "(none)" : target_phonemes.joined(separator: " ")
        var line = "score=\(pct)% correct=\(is_correct) target=[\(target)] heard=[\(heard)]"
        if let dbg = debug {
            if let audio = dbg.audio ?? dbg.post_trim {
                line += " rms=\(audio.rms) dur=\(audio.duration_ms ?? 0)ms silent=\(audio.is_silent)"
            }
            if let reason = dbg.reason {
                line += " reason=\(reason)"
            }
        }
        return line
    }
}

struct PronunciationAudioStats: Decodable, Equatable {
    let duration_ms: Int?
    let samples: Int?
    let rms: Double
    let peak: Double?
    let is_silent: Bool
}

struct PronunciationDebugInfo: Decodable, Equatable {
    let audio: PronunciationAudioStats?
    let pre_trim: PronunciationAudioStats?
    let post_trim: PronunciationAudioStats?
    let reason: String?
    let target_normalized: [String]?
    let predicted_normalized: [String]?
    let predicted_raw_string: String?
    let payload_bytes: Int?
    let decoded_sr: Int?
}

// MARK: - Pronunciation WebSocket URL helpers

enum PronunciationEndpoint {
    /// Production default used when UserDefaults / endpoint row has no URL yet.
    static let defaultAssessURL = "https://pronunciation_assessment.npro.ai/assess"

    /// Returns a non-empty assess URL, falling back to `defaultAssessURL`.
    static func resolvedAssessURL(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultAssessURL : trimmed
    }

    /// Converts a configured HTTP(S) assess URL into the streaming WebSocket path.
    /// `https://host/assess` → `wss://host/ws/assess`
    /// `http://host:8086/assess` → `ws://host:8086/ws/assess`
    /// Already-`ws(s):` URLs are returned (path normalized to `/ws/assess` when needed).
    static func webSocketURL(from endpoint: String) -> String? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return nil }

        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        case "wss", "ws":
            break
        default:
            return nil
        }

        var path = components.path
        if path.hasSuffix("/assess") && !path.hasSuffix("/ws/assess") {
            path = String(path.dropLast("/assess".count)) + "/ws/assess"
        } else if path.isEmpty || path == "/" {
            path = "/ws/assess"
        } else if !path.contains("ws") {
            // e.g. bare host root → /ws/assess
            if path.hasSuffix("/") {
                path += "ws/assess"
            } else {
                path += "/ws/assess"
            }
        }
        components.path = path
        return components.string
    }

    /// Maps ws(s) assess URLs back to HTTP POST `/assess` for the one-shot fallback.
    static func httpAssessURL(from endpoint: String) -> String? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else { return nil }
        switch components.scheme?.lowercased() {
        case "wss":
            components.scheme = "https"
        case "ws":
            components.scheme = "http"
        case "https", "http":
            break
        default:
            return nil
        }
        var path = components.path
        if path.hasSuffix("/ws/assess") {
            path = String(path.dropLast("/ws/assess".count)) + "/assess"
        } else if path.isEmpty || path == "/" {
            path = "/assess"
        } else if !path.hasSuffix("/assess") {
            path = path.hasSuffix("/") ? path + "assess" : path + "/assess"
        }
        components.path = path
        return components.string
    }
}


@MainActor
class APIManager {
    var onLog: ((String) -> Void)?
    
    /// Requests chat completion from OpenAI-compatible endpoint
    func generateText(
        endpoint: String,
        model: String,
        messages: [ChatMessage],
        temperature: Double = 0.7,
        max_tokens: Int = 199
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "APIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Text Gen Endpoint URL"])
        }
        
        let payload = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            stream: false,
            max_tokens: max_tokens
        )
        
        let jsonData = try JSONEncoder().encode(payload)
        
        // Pretty print JSON payload for logging
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            onLog?("APIManager [LLM]: Sending POST to \(endpoint)\nPayload:\n\(jsonString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP Response"])
        }
        
        onLog?("APIManager [LLM]: Received Response (Status Code: \(httpResponse.statusCode))")
        
        guard httpResponse.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "No body"
            onLog?("APIManager [LLM]: Error Response: \(errBody)")
            throw NSError(domain: "APIManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode): \(errBody)"])
        }
        
        let textResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = textResponse.choices.first?.message.content else {
            throw NSError(domain: "APIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Empty chat response from LLM server"])
        }
        
        onLog?("APIManager [LLM]: Extracted completion response: \"\(content)\"")
        return content
    }
    
    /// Requests WAV audio bytes from TTS endpoint
    func generateSpeech(
        endpoint: String,
        model: String,
        text: String,
        voice: String,
        speed: Double = 1.0
    ) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "APIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid TTS Endpoint URL"])
        }
        
        let payload = TTSRequest(
            model: model,
            input: text,
            voice: voice,
            speed: speed
        )
        
        let jsonData = try JSONEncoder().encode(payload)
        
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            onLog?("APIManager [TTS]: Sending POST to \(endpoint)\nPayload:\n\(jsonString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP Response"])
        }
        
        onLog?("APIManager [TTS]: Received Response (Status Code: \(httpResponse.statusCode), Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "none"), Length: \(data.count) bytes)")
        
        guard httpResponse.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "No body"
            onLog?("APIManager [TTS]: Error Response: \(errBody)")
            throw NSError(domain: "APIManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode): \(errBody)"])
        }
        
        return data
    }
    
    /// Dynamically fetches the list of voice names supported by the TTS server
    func fetchVoices(endpoint: String) async throws -> [String] {
        var voicesURLString = endpoint
        if endpoint.hasSuffix("/speech") {
            voicesURLString = String(endpoint.dropLast(6)) + "voices"
        } else {
            if let urlObj = URL(string: endpoint) {
                voicesURLString = urlObj.deletingLastPathComponent().appendingPathComponent("voices").absoluteString
            }
        }
        
        guard let url = URL(string: voicesURLString) else {
            throw NSError(domain: "APIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Voices URL"])
        }
        
        onLog?("APIManager [TTS]: Fetching voices list from \(voicesURLString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP Response"])
        }
        
        onLog?("APIManager [TTS]: Fetch voices response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "No body"
            throw NSError(domain: "APIManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode): \(errBody)"])
        }
        
        let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return decoded.voices
    }
    
    /// Submits audio for pronunciation assessment (HTTP one-shot fallback).
    /// `audioData` may be raw float32 PCM @ 16 kHz or a WAV container.
    func submitPronunciationAssessment(
        endpoint: String,
        audioData: Data,
        targetWord: String
    ) async throws -> PronunciationAssessmentResponse {
        // Prefer the HTTP /assess path even if the user pasted a WS URL.
        let httpEndpoint = PronunciationEndpoint.httpAssessURL(from: endpoint) ?? endpoint
        guard let url = URL(string: httpEndpoint) else {
            throw NSError(domain: "APIManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Pronunciation Endpoint URL"])
        }

        let base64Audio = audioData.base64EncodedString()
        // Always request debug metadata so logs show RMS/duration/heard phonemes when scores look wrong.
        let payload: [String: Any] = [
            "audio_base64": base64Audio,
            "target_text": targetWord,
            "debug": true
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)

        onLog?("APIManager [Pronunciation]: Sending POST to \(httpEndpoint) for word '\(targetWord)' (\(audioData.count) bytes)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "APIManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP Response"])
        }

        onLog?("APIManager [Pronunciation]: Received Response (Status Code: \(httpResponse.statusCode))")

        guard httpResponse.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "No body"
            onLog?("APIManager [Pronunciation]: Error Response: \(errBody)")
            throw NSError(domain: "APIManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode): \(errBody)"])
        }

        let decoded = try JSONDecoder().decode(PronunciationAssessmentResponse.self, from: data)
        onLog?("APIManager [Pronunciation]: \(decoded.diagnosticSummary)")
        return decoded
    }

    
    /// Connection verifier for Text Generation endpoint
    func testTextGenConnection(url: String) async -> Bool {
        guard let urlObj = URL(string: url) else { return false }
        onLog?("APIManager [LLM]: Testing connection to \(url)")
        
        var request = URLRequest(url: urlObj)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let testPayload: [String: Any] = [
            "model": "ping-test",
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: testPayload) else { return false }
        request.httpBody = jsonData
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                onLog?("APIManager [LLM]: Connection test returned status code: \(httpResponse.statusCode)")
                return (200...299).contains(httpResponse.statusCode)
            }
        } catch {
            onLog?("APIManager [LLM]: Connection test failed with error: \(error.localizedDescription)")
            return false
        }
        return false
    }
    
    /// Connection verifier for STT WebSocket endpoint
    func testSTTConnection(url: String) async -> Bool {
        guard let urlObj = URL(string: url) else { return false }
        onLog?("APIManager [STT]: Testing connection to \(url)")
        
        return await withCheckedContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: urlObj)
            
            var completed = false
            func finish(result: Bool) {
                if !completed {
                    completed = true
                    task.cancel(with: .normalClosure, reason: nil)
                    continuation.resume(returning: result)
                }
            }
            
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                finish(result: false)
            }
            
            task.resume()
            
            task.sendPing { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.onLog?("APIManager [STT]: Ping test failed: \(error.localizedDescription)")
                    }
                    finish(result: false)
                } else {
                    Task { @MainActor in
                        self?.onLog?("APIManager [STT]: Ping test succeeded")
                    }
                    finish(result: true)
                }
            }
        }
    }
}
