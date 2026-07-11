import Foundation

/// Generates ephemeral practice cards from vocabulary seed flashcards via the chat-completions LLM.
enum PracticeCardGenerator {
    enum GeneratorError: LocalizedError {
        case noSeeds
        case emptyResponse
        case invalidJSON(String)
        case noValidItems

        var errorDescription: String? {
            switch self {
            case .noSeeds:
                return "No seed cards to generate practice from"
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
    /// PR2: always emits comprehensible (A0–A1 + known scaffold) prompts; `style` is accepted for API stability but ignored until PR4.
    @MainActor
    static func generatePack(
        from seedCards: [Flashcard],
        knownFronts: [String],
        style: PracticeSentenceStyle = .comprehensible,
        endpoint: String,
        model: String,
        appLanguage: AppLanguage,
        apiManager: APIManager,
        maxSeeds: Int = PracticeGenerationConfig.maxDueSeeds,
        examplesPerCard: Int = PracticeGenerationConfig.examplesPerCard,
        maxTokens: Int = PracticeGenerationConfig.maxTokens
    ) async throws -> PracticePack {
        _ = style // PR4: branch on .natural
        let seeds = Array(seedCards.prefix(maxSeeds))
        guard !seeds.isEmpty else { throw GeneratorError.noSeeds }

        let messages = buildMessages(
            seeds: seeds,
            examplesPerCard: examplesPerCard,
            knownFronts: knownFronts,
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
    /// PR2: always comprehensible prompts; `style` ignored until PR4.
    @MainActor
    static func regenerateExample(
        seed: Flashcard,
        existingSentences: [String],
        knownFronts: [String],
        style: PracticeSentenceStyle = .comprehensible,
        endpoint: String,
        model: String,
        appLanguage: AppLanguage,
        apiManager: APIManager,
        maxTokens: Int = PracticeGenerationConfig.singleExampleMaxTokens
    ) async throws -> PracticeCard {
        _ = style // PR4: branch on .natural
        let messages = buildSingleRegenerateMessages(
            seed: seed,
            existingSentences: existingSentences,
            knownFronts: knownFronts,
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

    /// Pack system + user messages. Always comprehensible (baby language + KNOWN_VOCAB scaffold).
    static func buildMessages(
        seeds: [Flashcard],
        examplesPerCard: Int,
        knownFronts: [String],
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

        let seedsJSON = encodeJSONArray(seedPayloads)
        let knownJSON = encodeStringArray(knownFronts)
        let maxWords = PracticeGenerationConfig.babyLanguageMaxWordsEnglish
        let maxChars = PracticeGenerationConfig.babyLanguageMaxCharsChinese
        let sparse = knownFronts.count < PracticeGenerationConfig.minKnownForRichScaffold
        let seedFronts = seeds.map(\.front)
        let beginnerList = PracticeUltraCommonBeginnerContent.promptList(
            forSeedFronts: seedFronts,
            appLanguage: appLanguage
        )

        let system: String
        if appLanguage == .zh {
            var s = """
            你是面向绝对初学者（CEFR A0–A1）的语言学习助教。
            根据种子闪卡，生成非常简单的练习例句。

            只输出合法 JSON，不要 markdown 代码块，不要解释。
            JSON 结构：{"items":[{"parent_id","parent_front","sentence","translation","phonics"}]}

            结构规则（输出管线）：
            - 每张种子卡恰好 \(examplesPerCard) 条 items。
            - parent_id 必须是输入中的种子卡 id。
            - parent_front 应与该种子卡的 front 一致。
            - sentence 必须把该种子卡的 front 作为学习目标来使用。
            - translation 为 sentence 的翻译（尽量与卡片 back 语言一致）。
            - phonics：若 sentence 为中文则填拼音；否则可省略或空字符串。

            硬性规则（幼儿式语言）：
            - 句子要短：英文优先 ≤ \(maxWords) 个词，中文优先 ≤ \(maxChars) 个汉字。
            - 只用简单主谓宾/日常句式。不要生僻习语、俚语或书面语。
            - 优先一般现在时/基本体貌，避免复杂从句。
            - 用最简单的词变化句式（肯定 / 疑问 / 否定）。若需要难词，不要强行使用职场、学术或新闻话题。

            脚手架优先级（高 → 低）：
            1. 必须使用种子 front 作为目标词。
            2. 非目标实词优先来自 KNOWN_VOCAB。
            3. 可以始终使用列表外的超常见虚词/功能词（助词、代词、系词、否定、疑问、基本介词/助动词等）。
            4. SEED_CARDS 中出现的任一 front，都可以作为任意条目的内容词。
            5. 避免生僻或专业领域实词；不要引入新的学习目标词。
            6. 脚手架用词尽量与种子 front 同一语言/文字系统。

            已知词很少时：
            - 若 KNOWN_VOCAB 为空或很少，依靠幼儿式语言 + 功能词，并仅允许构成语法通顺简单句所必需的超高频初学实词（例如：\(beginnerList)）。仍禁止习语/俚语/行话。

            不要发明与 front 无关的新词作为练习目标。
            """
            if sparse {
                s += """


                - KNOWN_VOCAB 有限——只用最简单的词；短句优于丰富词汇。可为基本主谓宾句使用超高频初学实词。
                """
            }
            system = s
        } else {
            var s = """
            You are a language-learning tutor for absolute beginners (CEFR A0–A1).
            Given seed flashcards, create VERY SIMPLE practice sentences.

            Output valid JSON only — no markdown fences, no commentary.
            Schema: {"items":[{"parent_id","parent_front","sentence","translation","phonics"}]}

            Structural rules (output plumbing):
            - Exactly \(examplesPerCard) items per seed card.
            - parent_id MUST be the seed card id from the input.
            - parent_front should match that seed's front.
            - sentence MUST use the seed's front word/phrase as the learning target.
            - translation matches the meaning of sentence (same language as card back when possible).
            - phonics: pinyin when sentence is Chinese; else empty/omit.

            Hard rules (baby language):
            - Short sentences: prefer ≤ \(maxWords) English words or ≤ \(maxChars) Chinese characters.
            - Simple SVO / everyday patterns only. No rare idioms, slang, or literary style.
            - Prefer present tense / basic aspect. Avoid complex subordination.
            - Vary frame (affirmative / question / negation) using the simplest possible words. Do not force workplace, academic, or news topics if that requires hard vocabulary.

            Scaffold priority (highest → lowest):
            1. Use the seed front as the target.
            2. Prefer non-target content words from KNOWN_VOCAB.
            3. You MAY always use ultra-common function words not on the list.
            4. Any front appearing in SEED_CARDS may appear as content in any item.
            5. Avoid rare or domain-specific content words; do not introduce new learning targets.
            6. Scaffold with KNOWN_VOCAB items written in the same language/script as the seed front.

            Sparse known set:
            - If KNOWN_VOCAB is empty or very small, use baby language + function words, and only the most basic beginner content words needed for a grammatical sentence (e.g. \(beginnerList)). Still ban idioms/slang/jargon.

            Do not invent unrelated new headwords as the learning target.
            """
            if sparse {
                s += """


                - KNOWN_VOCAB is limited — use only the simplest possible words; short pattern sentences are better than rich vocabulary. You may use ultra-common beginner content words for a basic SVO frame.
                """
            }
            system = s
        }

        let user: String
        if appLanguage == .zh {
            user = """
            KNOWN_VOCAB（脚手架优先用词，可为空）：
            \(knownJSON)

            SEED_CARDS（每张种子恰好生成 \(examplesPerCard) 条例句）：
            \(seedsJSON)
            """
        } else {
            user = """
            KNOWN_VOCAB (prefer these words for scaffolding; may be empty):
            \(knownJSON)

            SEED_CARDS (generate exactly \(examplesPerCard) examples each):
            \(seedsJSON)
            """
        }

        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: user)
        ]
    }

    /// Single-item regenerate messages with the same comprehensible scaffold as pack generation.
    static func buildSingleRegenerateMessages(
        seed: Flashcard,
        existingSentences: [String],
        knownFronts: [String],
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
        let knownJSON = encodeStringArray(knownFronts)

        let avoided = existingSentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let avoidedBlock = avoided.isEmpty
            ? (appLanguage == .zh ? "（无）" : "(none)")
            : avoided.map { "- \($0)" }.joined(separator: "\n")

        let maxWords = PracticeGenerationConfig.babyLanguageMaxWordsEnglish
        let maxChars = PracticeGenerationConfig.babyLanguageMaxCharsChinese
        let sparse = knownFronts.count < PracticeGenerationConfig.minKnownForRichScaffold
        let beginnerList = PracticeUltraCommonBeginnerContent.promptList(
            forSeedFronts: [seed.front],
            appLanguage: appLanguage
        )

        let system: String
        if appLanguage == .zh {
            var s = """
            你是面向绝对初学者（CEFR A0–A1）的语言学习助教。
            为给定闪卡生成恰好 1 条全新的非常简单练习例句。

            只输出合法 JSON，不要 markdown 代码块，不要解释。
            JSON 结构：{"items":[{"parent_id","parent_front","sentence","translation","phonics"}]}

            结构规则（输出管线）：
            - 恰好 1 条 item。
            - parent_id 必须等于输入卡的 id。
            - parent_front 应与种子卡的 front 一致。
            - sentence 必须把 front 作为学习目标来使用。
            - 不要与“避免使用的句子”重复或仅做微小改写。
            - translation 为 sentence 的翻译（尽量与卡片 back 语言一致）。
            - phonics：若 sentence 为中文则填拼音；否则可省略或空字符串。

            硬性规则（幼儿式语言）：
            - 句子要短：英文优先 ≤ \(maxWords) 个词，中文优先 ≤ \(maxChars) 个汉字。
            - 只用简单主谓宾/日常句式。不要生僻习语、俚语或书面语。
            - 优先一般现在时/基本体貌，避免复杂从句。
            - 用最简单的词变化句式（肯定 / 疑问 / 否定）。若需要难词，不要强行使用职场、学术或新闻话题。

            脚手架优先级（高 → 低）：
            1. 必须使用种子 front 作为目标词。
            2. 非目标实词优先来自 KNOWN_VOCAB。
            3. 可以始终使用列表外的超常见虚词/功能词（助词、代词、系词、否定、疑问、基本介词/助动词等）。
            4. 该闪卡的 front 可以作为内容词。
            5. 避免生僻或专业领域实词；不要引入新的学习目标词。
            6. 脚手架用词尽量与种子 front 同一语言/文字系统。

            已知词很少时：
            - 若 KNOWN_VOCAB 为空或很少，依靠幼儿式语言 + 功能词，并仅允许构成语法通顺简单句所必需的超高频初学实词（例如：\(beginnerList)）。仍禁止习语/俚语/行话。

            不要发明与 front 无关的新词作为练习目标。
            """
            if sparse {
                s += """


                - KNOWN_VOCAB 有限——只用最简单的词；短句优于丰富词汇。可为基本主谓宾句使用超高频初学实词。
                """
            }
            system = s
        } else {
            var s = """
            You are a language-learning tutor for absolute beginners (CEFR A0–A1).
            Create exactly 1 new VERY SIMPLE practice sentence for the given flashcard.

            Output valid JSON only — no markdown fences, no commentary.
            Schema: {"items":[{"parent_id","parent_front","sentence","translation","phonics"}]}

            Structural rules (output plumbing):
            - Exactly 1 item.
            - parent_id MUST equal the seed card id.
            - parent_front should match the seed's front.
            - sentence MUST use the card's front word/phrase as the learning target.
            - Do not repeat or lightly rephrase any sentence listed under avoid.
            - translation is the meaning of sentence (same language as card back when possible).
            - phonics: pinyin when sentence is Chinese; else empty/omit.

            Hard rules (baby language):
            - Short sentences: prefer ≤ \(maxWords) English words or ≤ \(maxChars) Chinese characters.
            - Simple SVO / everyday patterns only. No rare idioms, slang, or literary style.
            - Prefer present tense / basic aspect. Avoid complex subordination.
            - Vary frame (affirmative / question / negation) using the simplest possible words. Do not force workplace, academic, or news topics if that requires hard vocabulary.

            Scaffold priority (highest → lowest):
            1. Use the seed front as the target.
            2. Prefer non-target content words from KNOWN_VOCAB.
            3. You MAY always use ultra-common function words not on the list.
            4. This flashcard's front may appear as content.
            5. Avoid rare or domain-specific content words; do not introduce new learning targets.
            6. Scaffold with KNOWN_VOCAB items written in the same language/script as the seed front.

            Sparse known set:
            - If KNOWN_VOCAB is empty or very small, use baby language + function words, and only the most basic beginner content words needed for a grammatical sentence (e.g. \(beginnerList)). Still ban idioms/slang/jargon.

            Do not invent unrelated new headwords as the learning target.
            """
            if sparse {
                s += """


                - KNOWN_VOCAB is limited — use only the simplest possible words; short pattern sentences are better than rich vocabulary. You may use ultra-common beginner content words for a basic SVO frame.
                """
            }
            system = s
        }

        let user: String
        if appLanguage == .zh {
            user = """
            KNOWN_VOCAB（脚手架优先用词，可为空）：
            \(knownJSON)

            闪卡：
            \(seedJSON)

            避免使用的句子：
            \(avoidedBlock)

            请生成 1 条新例句。
            """
        } else {
            user = """
            KNOWN_VOCAB (prefer these words for scaffolding; may be empty):
            \(knownJSON)

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

    // MARK: - JSON encoding helpers

    private static func encodeJSONArray<T: Encodable>(_ values: [T]) -> String {
        if let data = try? JSONEncoder().encode(values),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "[]"
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        encodeJSONArray(values)
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
        PracticeScaffolding.normalizeFrontKey(value)
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
