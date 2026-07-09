import Foundation

/// How voice input is processed before the main chat turn.
enum SpeechPipelineMode: String, CaseIterable, Identifiable {
    /// Raw NVIDIA STT text goes straight into the conversation.
    case directSTT = "directSTT"
    /// STT then LLM correction + pronunciation feedback (practice mode).
    case sttPlusLLM = "sttPlusLLM"

    var id: String { rawValue }

    var usesLLMCorrection: Bool {
        self == .sttPlusLLM
    }
}

/// Target language forced on the NVIDIA STT WebSocket (`?language=`).
enum STTLanguage: String, CaseIterable, Identifiable {
    case chinese = "Chinese"
    case english = "English"
    case auto = "auto"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        case .auto: return "Auto"
        }
    }

    /// Human label for LLM prompts.
    var promptLabel: String {
        switch self {
        case .chinese: return "Chinese (Mandarin)"
        case .english: return "English"
        case .auto: return "auto-detect"
        }
    }
}

/// Result of the STT → LLM intent-recovery step.
struct SpeechCorrectionResult: Equatable {
    let correctedText: String
    let feedback: String
    /// True when the LLM call failed or timed out and raw ASR was kept.
    let usedFallback: Bool

    static func fallback(_ raw: String) -> SpeechCorrectionResult {
        SpeechCorrectionResult(correctedText: raw, feedback: "", usedFallback: true)
    }
}

/// LLM post-correction + short pronunciation tutoring for learner speech.
/// Orchestrated on the client so both NVIDIA remote STT and future backends stay thin ASR services.
enum SpeechCorrection {
    private struct Payload: Decodable {
        let corrected_text: String?
        let feedback: String?
    }

    /// Default timeout for the correction hop (short utterances only).
    static let defaultTimeoutNanoseconds: UInt64 = 2_500_000_000

    // MARK: - STT URL (NVIDIA)

    /// Ensures `language=` is present for the NVIDIA STT server without dropping other query params.
    static func sttURL(base: String, language: STTLanguage) -> String {
        guard var components = URLComponents(string: base) else {
            let separator = base.contains("?") ? "&" : "?"
            return "\(base)\(separator)language=\(language.rawValue)"
        }

        var items = components.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "language" }
        items.append(URLQueryItem(name: "language", value: language.rawValue))
        components.queryItems = items
        return components.string ?? base
    }

    // MARK: - Prompt

    static func buildMessages(
        rawText: String,
        history: [ChatMessage],
        targetLanguage: STTLanguage,
        appLanguage: AppLanguage
    ) -> [ChatMessage] {
        let historyLines: String
        if history.isEmpty {
            historyLines = "(none)"
        } else {
            historyLines = history.map { msg in
                let role = msg.role == "assistant" ? "Assistant" : "Learner"
                return "\(role): \(msg.content)"
            }.joined(separator: "\n")
        }

        let system = """
        You are a patient English/Chinese language tutor helping with conversation practice.

        Given a raw speech-to-text transcript that may contain pronunciation errors, wrong tones, or ASR mistakes:
        1. Infer the learner's intended meaning using conversation history.
        2. Produce a natural corrected utterance in the target language (do not over-correct style or invent long extra content).
        3. Optionally give one short, specific, encouraging pronunciation or phrasing note.
        4. If the transcript is already fine, return it unchanged and empty feedback.

        Respond ONLY with JSON (no markdown fences, no prose outside JSON):
        {
          "corrected_text": "...",
          "feedback": ""
        }

        Target language: \(targetLanguage.promptLabel).
        App UI language for feedback wording: \(appLanguage == .zh ? "Chinese" : "English").
        Keep feedback to at most one short sentence; empty string if none needed.
        """

        let user = """
        Recent conversation (oldest → newest):
        \(historyLines)

        Raw ASR (may be wrong): "\(rawText)"

        Correct and give brief feedback if useful.
        """

        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: user)
        ]
    }

    // MARK: - Call

    static func correct(
        rawText: String,
        history: [ChatMessage],
        targetLanguage: STTLanguage,
        appLanguage: AppLanguage,
        endpoint: String,
        model: String,
        apiManager: APIManager,
        timeoutNanoseconds: UInt64 = defaultTimeoutNanoseconds
    ) async -> SpeechCorrectionResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .fallback(rawText)
        }

        let messages = buildMessages(
            rawText: trimmed,
            history: history,
            targetLanguage: targetLanguage,
            appLanguage: appLanguage
        )

        do {
            let rawResponse = try await withTimeout(nanoseconds: timeoutNanoseconds) {
                try await apiManager.generateText(
                    endpoint: endpoint,
                    model: model,
                    messages: messages,
                    temperature: 0.25,
                    max_tokens: 120
                )
            }
            return parse(response: rawResponse, fallbackRaw: trimmed)
        } catch {
            return .fallback(trimmed)
        }
    }

    // MARK: - Parse

    static func parse(response: String, fallbackRaw: String) -> SpeechCorrectionResult {
        let jsonText = extractJSONObject(from: response)
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .fallback(fallbackRaw)
        }

        let corrected = (payload.corrected_text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let feedback = (payload.feedback ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !corrected.isEmpty else {
            return .fallback(fallbackRaw)
        }

        return SpeechCorrectionResult(
            correctedText: corrected,
            feedback: feedback,
            usedFallback: false
        )
    }

    static func extractJSONObject(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            return String(text[start...end])
        }

        return text
    }

    // MARK: - Timeout helper

    private static func withTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw CorrectionTimeoutError()
            }
            guard let first = try await group.next() else {
                throw CorrectionTimeoutError()
            }
            group.cancelAll()
            return first
        }
    }

    private struct CorrectionTimeoutError: Error {}
}
