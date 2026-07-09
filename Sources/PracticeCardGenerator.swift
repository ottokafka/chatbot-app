import Foundation

/// Generates ephemeral practice cards from due flashcards via the chat-completions LLM.
enum PracticeCardGenerator {
    enum GeneratorError: LocalizedError {
        case noSeeds
        case emptyResponse
        case invalidJSON(String)
        case noValidItems

        var errorDescription: String? {
            switch self {
            case .noSeeds:
                return "No due cards to generate practice from"
            case .emptyResponse:
                return "The model returned an empty response"
            case .invalidJSON(let detail):
                return "Could not parse practice JSON: \(detail)"
            case .noValidItems:
                return "No valid practice examples were produced"
            }
        }
    }

    private struct SeedPayload: Encodable {
        let id: String
        let front: String
        let back: String
        let phonics: String?
    }

    private struct LLMItem: Decodable {
        let parent_id: String?
        let parent_front: String?
        let sentence: String?
        let translation: String?
        let phonics: String?
    }

    private struct LLMEnvelope: Decodable {
        let items: [LLMItem]
    }

    /// Builds an in-memory practice pack by calling the OpenAI-compatible text-gen endpoint.
    @MainActor
    static func generatePack(
        from dueCards: [Flashcard],
        endpoint: String,
        model: String,
        appLanguage: AppLanguage,
        apiManager: APIManager,
        maxSeeds: Int = PracticeGenerationConfig.maxDueSeeds,
        examplesPerCard: Int = PracticeGenerationConfig.examplesPerCard,
        maxTokens: Int = PracticeGenerationConfig.maxTokens
    ) async throws -> PracticePack {
        let seeds = Array(dueCards.prefix(maxSeeds))
        guard !seeds.isEmpty else { throw GeneratorError.noSeeds }

        let messages = buildMessages(
            seeds: seeds,
            examplesPerCard: examplesPerCard,
            appLanguage: appLanguage
        )

        let raw = try await apiManager.generateText(
            endpoint: endpoint,
            model: model,
            messages: messages,
            temperature: 0.7,
            max_tokens: maxTokens
        )

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeneratorError.emptyResponse }

        let cards = try parsePracticeCards(from: trimmed, seeds: seeds)
        guard !cards.isEmpty else { throw GeneratorError.noValidItems }

        return PracticePack(sourceDueCount: seeds.count, cards: cards)
    }

    /// Regenerates a single example sentence for one seed card.
    @MainActor
    static func regenerateExample(
        seed: Flashcard,
        existingSentences: [String],
        endpoint: String,
        model: String,
        appLanguage: AppLanguage,
        apiManager: APIManager,
        maxTokens: Int = PracticeGenerationConfig.singleExampleMaxTokens
    ) async throws -> PracticeCard {
        let messages = buildSingleRegenerateMessages(
            seed: seed,
            existingSentences: existingSentences,
            appLanguage: appLanguage
        )

        let raw = try await apiManager.generateText(
            endpoint: endpoint,
            model: model,
            messages: messages,
            temperature: 0.85,
            max_tokens: maxTokens
        )

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeneratorError.emptyResponse }

        let cards = try parsePracticeCards(from: trimmed, seeds: [seed])
        guard let card = cards.first else { throw GeneratorError.noValidItems }
        return card
    }

    // MARK: - Prompt

    static func buildMessages(
        seeds: [Flashcard],
        examplesPerCard: Int,
        appLanguage: AppLanguage
    ) -> [ChatMessage] {
        let seedPayloads = seeds.map {
            SeedPayload(
                id: $0.id,
                front: $0.front,
                back: $0.back,
                phonics: $0.phonics
            )
        }

        let seedsJSON: String
        if let data = try? JSONEncoder().encode(seedPayloads),
           let string = String(data: data, encoding: .utf8) {
            seedsJSON = string
        } else {
            seedsJSON = "[]"
        }

        let system: String
        if appLanguage == .zh {
            system = """
            你是语言学习助教。根据学生到期的闪卡，生成自然的例句练习。
            只输出合法 JSON，不要 markdown 代码块，不要解释。
            JSON 结构：
            {"items":[{"parent_id":"...","parent_front":"...","sentence":"...","translation":"...","phonics":"..."}]}
            规则：
            - 每张种子卡恰好 \(examplesPerCard) 条 items
            - parent_id 必须是输入中的 id
            - sentence 必须自然使用该卡的 front 词汇/短语
            - 多条例句语境要不同（日常、提问、否定、工作/学习等）
            - translation 为 sentence 的翻译（与卡的 back 语言一致）
            - phonics：若 sentence 含中文，填拼音；否则可省略或空字符串
            - 不要发明与 front 无关的新词作为练习目标
            """
        } else {
            system = """
            You are a language-learning tutor. Given the student's due flashcards, create natural example-sentence practice cards.
            Output valid JSON only — no markdown fences, no commentary.
            Schema:
            {"items":[{"parent_id":"...","parent_front":"...","sentence":"...","translation":"...","phonics":"..."}]}
            Rules:
            - Exactly \(examplesPerCard) items per seed card
            - parent_id MUST be the seed card id from the input
            - sentence MUST naturally use that card's front word/phrase
            - Vary context across examples (daily life, questions, negation, work/study, etc.)
            - translation is the meaning of sentence (same language as the card's back when possible)
            - phonics: include pinyin when sentence is Chinese; otherwise omit or empty string
            - Do not invent unrelated new headwords as the learning target
            """
        }

        let user: String
        if appLanguage == .zh {
            user = """
            请为以下到期闪卡生成练习例句（每卡 \(examplesPerCard) 条）：
            \(seedsJSON)
            """
        } else {
            user = """
            Generate practice example sentences for these due flashcards (\(examplesPerCard) per card):
            \(seedsJSON)
            """
        }

        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: user)
        ]
    }

    static func buildSingleRegenerateMessages(
        seed: Flashcard,
        existingSentences: [String],
        appLanguage: AppLanguage
    ) -> [ChatMessage] {
        let seedPayload = SeedPayload(
            id: seed.id,
            front: seed.front,
            back: seed.back,
            phonics: seed.phonics
        )
        let seedJSON: String
        if let data = try? JSONEncoder().encode(seedPayload),
           let string = String(data: data, encoding: .utf8) {
            seedJSON = string
        } else {
            seedJSON = "{}"
        }

        let avoided = existingSentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let avoidedBlock = avoided.isEmpty
            ? (appLanguage == .zh ? "（无）" : "(none)")
            : avoided.map { "- \($0)" }.joined(separator: "\n")

        let system: String
        if appLanguage == .zh {
            system = """
            你是语言学习助教。为给定闪卡生成 1 条全新的自然例句。
            只输出合法 JSON，不要 markdown 代码块，不要解释。
            JSON 结构：
            {"items":[{"parent_id":"...","parent_front":"...","sentence":"...","translation":"...","phonics":"..."}]}
            规则：
            - 恰好 1 条 item
            - parent_id 必须等于输入卡的 id
            - sentence 必须自然使用 front 词汇/短语
            - 不要与“避免使用的句子”重复或仅做微小改写
            - translation 为 sentence 的翻译
            - 含中文时提供 phonics（拼音）
            """
        } else {
            system = """
            You are a language-learning tutor. Create exactly 1 new natural example sentence for the given flashcard.
            Output valid JSON only — no markdown fences, no commentary.
            Schema:
            {"items":[{"parent_id":"...","parent_front":"...","sentence":"...","translation":"...","phonics":"..."}]}
            Rules:
            - Exactly 1 item
            - parent_id MUST equal the seed card id
            - sentence MUST naturally use the card's front word/phrase
            - Do not repeat or lightly rephrase any sentence listed under avoid
            - translation is the meaning of sentence
            - Include phonics (pinyin) when the sentence is Chinese
            """
        }

        let user: String
        if appLanguage == .zh {
            user = """
            闪卡：
            \(seedJSON)

            避免使用的句子：
            \(avoidedBlock)

            请生成 1 条新例句。
            """
        } else {
            user = """
            Flashcard:
            \(seedJSON)

            Avoid these sentences:
            \(avoidedBlock)

            Generate 1 new example sentence.
            """
        }

        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: user)
        ]
    }

    // MARK: - Parsing

    /// Parses model output into practice cards, dropping malformed items.
    static func parsePracticeCards(from raw: String, seeds: [Flashcard]) throws -> [PracticeCard] {
        let jsonText = extractJSONObject(from: raw)
        guard let data = jsonText.data(using: .utf8) else {
            throw GeneratorError.invalidJSON("response is not UTF-8")
        }

        let envelope: LLMEnvelope
        do {
            envelope = try JSONDecoder().decode(LLMEnvelope.self, from: data)
        } catch {
            throw GeneratorError.invalidJSON(error.localizedDescription)
        }

        let seedsById = Dictionary(uniqueKeysWithValues: seeds.map { ($0.id, $0) })
        let seedsByFront = Dictionary(grouping: seeds, by: { normalizeKey($0.front) })

        var cards: [PracticeCard] = []
        cards.reserveCapacity(envelope.items.count)

        for item in envelope.items {
            let sentence = item.sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let translation = item.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !sentence.isEmpty, !translation.isEmpty else { continue }

            let parent = resolveParent(
                parentId: item.parent_id,
                parentFront: item.parent_front,
                seedsById: seedsById,
                seedsByFront: seedsByFront
            )

            let phonicsRaw = item.phonics?.trimmingCharacters(in: .whitespacesAndNewlines)
            let phonics: String?
            if let phonicsRaw, !phonicsRaw.isEmpty {
                phonics = phonicsRaw
            } else if let parentPhonics = parent?.phonics, !parentPhonics.isEmpty {
                // Prefer auto pinyin for the full sentence when Chinese.
                let auto = FlashcardTranslator.autoFillPhonics(for: sentence)
                phonics = auto.isEmpty ? nil : auto
            } else {
                let auto = FlashcardTranslator.autoFillPhonics(for: sentence)
                phonics = auto.isEmpty ? nil : auto
            }

            cards.append(
                PracticeCard(
                    front: sentence,
                    back: translation,
                    phonics: phonics,
                    parentFlashcardId: parent?.id,
                    parentFront: parent?.front ?? item.parent_front
                )
            )
        }

        return cards
    }

    // MARK: - Helpers

    static func extractJSONObject(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ```json ... ``` or ``` ... ```
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If there is leading prose, take the outermost { ... }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            return String(text[start...end])
        }

        return text
    }

    private static func normalizeKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func resolveParent(
        parentId: String?,
        parentFront: String?,
        seedsById: [String: Flashcard],
        seedsByFront: [String: [Flashcard]]
    ) -> Flashcard? {
        if let parentId,
           let match = seedsById[parentId] {
            return match
        }
        if let parentFront {
            let key = normalizeKey(parentFront)
            if let matches = seedsByFront[key], let first = matches.first {
                return first
            }
            // Soft match: parent_front contained in seed front or vice versa
            for (seedFront, cards) in seedsByFront {
                if seedFront.contains(key) || key.contains(seedFront), let first = cards.first {
                    return first
                }
            }
        }
        return nil
    }
}
