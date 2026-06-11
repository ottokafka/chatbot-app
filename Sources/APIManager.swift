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
}
