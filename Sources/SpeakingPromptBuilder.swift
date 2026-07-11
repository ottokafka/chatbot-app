import Foundation

/// Pure prompt construction for constrained speaking sessions.
/// Rebuilds a single system message each call; history is role/content only (no prior systems).
enum SpeakingPromptBuilder {
    /// Default LLM history window: last N speaking turns (≈ 6 exchanges).
    static let defaultHistoryLimit = 12

    /// Opening: one system + one user kickoff. No dialogue history yet.
    static func buildOpeningMessages(
        config: SpeakingSessionConfig
    ) -> [ChatMessage] {
        let system = buildSystemPrompt(
            config: config,
            uncoveredTargets: config.steersUncoveredTargets ? config.targetFronts : [],
            isOpening: true
        )
        let kickoff = openingKickoffUserMessage(config: config)
        return [
            ChatMessage(role: "system", content: system),
            ChatMessage(role: "user", content: kickoff)
        ]
    }

    /// Reply: one rebuilt system + last `historyLimit` turns as user/assistant only.
    static func buildReplyMessages(
        config: SpeakingSessionConfig,
        turns: [SpeakingTurn],
        uncoveredTargets: [String],
        historyLimit: Int = defaultHistoryLimit
    ) -> [ChatMessage] {
        let uncoveredForPrompt: [String]
        if config.steersUncoveredTargets {
            uncoveredForPrompt = uncoveredTargets
        } else {
            uncoveredForPrompt = []
        }

        let system = buildSystemPrompt(
            config: config,
            uncoveredTargets: uncoveredForPrompt,
            isOpening: false
        )

        var messages: [ChatMessage] = [
            ChatMessage(role: "system", content: system)
        ]

        let window = max(0, historyLimit)
        let recent = turns.suffix(window)
        for turn in recent {
            let role = turn.role == .user ? "user" : "assistant"
            messages.append(ChatMessage(role: role, content: turn.content))
        }
        return messages
    }

    // MARK: - System prompt

    private static func buildSystemPrompt(
        config: SpeakingSessionConfig,
        uncoveredTargets: [String],
        isOpening: Bool
    ) -> String {
        let maxWords = config.maxAssistantWordsEnglish
        let maxChars = config.maxAssistantCharsChinese
        let knownJSON = encodeStringArray(config.knownFronts)
        let targetJSON = encodeTargetWords(config.targetCards)
        let topic = config.topicHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let sparse = config.knownFronts.count < PracticeGenerationConfig.minKnownForRichScaffold
        let beginnerList = PracticeUltraCommonBeginnerContent.promptList(
            forSeedFronts: config.targetFronts,
            appLanguage: config.appLanguage
        )
        let includeUncovered = config.steersUncoveredTargets
        let forceCoverage = config.forceTargetCoverage
        let uncoveredJSON = encodeStringArray(uncoveredTargets)

        if config.appLanguage == .zh {
            return buildSystemPromptZh(
                maxWords: maxWords,
                maxChars: maxChars,
                knownJSON: knownJSON,
                targetJSON: targetJSON,
                uncoveredJSON: uncoveredJSON,
                includeUncovered: includeUncovered,
                forceCoverage: forceCoverage,
                topic: topic,
                sparse: sparse,
                beginnerList: beginnerList,
                isOpening: isOpening
            )
        }
        return buildSystemPromptEn(
            maxWords: maxWords,
            maxChars: maxChars,
            knownJSON: knownJSON,
            targetJSON: targetJSON,
            uncoveredJSON: uncoveredJSON,
            includeUncovered: includeUncovered,
            forceCoverage: forceCoverage,
            topic: topic,
            sparse: sparse,
            beginnerList: beginnerList,
            isOpening: isOpening
        )
    }

    private static func buildSystemPromptEn(
        maxWords: Int,
        maxChars: Int,
        knownJSON: String,
        targetJSON: String,
        uncoveredJSON: String,
        includeUncovered: Bool,
        forceCoverage: Bool,
        topic: String,
        sparse: Bool,
        beginnerList: String,
        isOpening: Bool
    ) -> String {
        var s = """
        You are a patient conversation partner for absolute beginners (CEFR A0–A1).
        You are NOT a free chat bot. Stay inside the learner's known vocabulary.

        Hard rules:
        - Replies: plain text only — 1–2 very short sentences (≤ \(maxWords) English words or ≤ \(maxChars) Chinese characters). No JSON, no markdown fences, no lists of vocabulary.
        - Prefer TARGET_WORDS situations.
        """
        if includeUncovered {
            if forceCoverage {
                s += """

                - CHALLENGE MODE: deliberately create natural situations so the learner can use each still-uncovered target word at least once. Prioritize remaining UNCOVERED_TARGETS with clear, simple questions or choices that make those words useful. Never dump a vocabulary quiz list as dialogue.
                """
            } else {
                s += """

                - Gently try to create situations where the learner can use still-uncovered targets; never dump a vocabulary quiz list as dialogue.
                """
            }
        }
        s += """

        - Content words: prefer KNOWN_VOCAB ∪ TARGET_WORDS; always allow common function words (pronouns, copulas, particles, basic prepositions/auxiliaries, negation, question words).
        - If KNOWN_VOCAB is sparse, only ultra-common beginner content words beyond targets (e.g. \(beginnerList)).
        - Do not introduce new learning targets, slang, idioms, or domain jargon.
        - Same script/language as the target words (front field). Speak in that language; do not switch to the UI language for content.
        - If the learner's last message is unclear, ask a simple yes/no or choice question.
        - Pedagogical repair: you may gently rephrase a broken learner sentence once in baby language, then continue. Do not lecture.

        TARGET_WORDS (use front script in speech; back is meaning for you only):
        \(targetJSON)
        """
        if includeUncovered {
            if forceCoverage {
                s += """


                UNCOVERED_TARGETS (challenge: steer each remaining word into the situation until used by the learner):
                \(uncoveredJSON)
                """
            } else {
                s += """


                UNCOVERED_TARGETS (soft, learner has not produced yet):
                \(uncoveredJSON)
                """
            }
        }
        s += """


        KNOWN_VOCAB (scaffold preference; may be empty):
        \(knownJSON)
        """
        if !topic.isEmpty {
            s += """


            TOPIC_HINT (optional situation to stay near):
            \(topic)
            """
        } else {
            s += """


            TOPIC_HINT: (none — choose a simple daily situation that fits the targets)
            """
        }
        if sparse {
            s += """


            Sparse known set: KNOWN_VOCAB is limited — use only the simplest words; short pattern turns are better than rich vocabulary.
            """
        }
        if isOpening {
            if includeUncovered {
                if forceCoverage {
                    s += """


                    Your task now: open with one short greeting and a simple question that makes an uncovered target natural to say. Plain text only.
                    """
                } else {
                    s += """


                    Your task now: open the conversation with one short greeting and a simple question that invites the learner to use a target word. Plain text only.
                    """
                }
            } else {
                s += """


                Your task now: open the conversation with one short greeting and a simple question about the topic / TARGET_WORDS situation. Plain text only.
                """
            }
        } else if includeUncovered {
            if forceCoverage {
                s += """


                Continue with one short reply (plain text only). If UNCOVERED_TARGETS is non-empty, prioritize a situation or question that invites one of those remaining words; if empty, free constrained chat.
                """
            } else {
                s += """


                Continue the conversation with one short reply (plain text only). Prefer questions that invite reuse of targets.
                """
            }
        } else {
            s += """


            Continue the conversation with one short reply (plain text only). Stay near the topic / TARGET_WORDS situation.
            """
        }
        return s
    }

    private static func buildSystemPromptZh(
        maxWords: Int,
        maxChars: Int,
        knownJSON: String,
        targetJSON: String,
        uncoveredJSON: String,
        includeUncovered: Bool,
        forceCoverage: Bool,
        topic: String,
        sparse: Bool,
        beginnerList: String,
        isOpening: Bool
    ) -> String {
        var s = """
        你是面向绝对初学者（CEFR A0–A1）的耐心对话伙伴。
        你不是自由聊天机器人。必须待在学习者已知词汇范围内。

        硬性规则：
        - 回复：仅纯文本——1–2 句极短句（英文优先 ≤ \(maxWords) 个词，中文优先 ≤ \(maxChars) 个汉字）。不要 JSON、不要 markdown 代码块、不要词汇表清单。
        - 优先围绕 TARGET_WORDS 创设情境。
        """
        if includeUncovered {
            if forceCoverage {
                s += """

                - 挑战模式：主动创设自然情境，让学习者至少使用每个尚未产出的目标词一次。优先围绕 UNCOVERED_TARGETS，用清晰简单的问句或选择问，让这些词自然可用。绝不要把词汇测验清单当作对话内容。
                """
            } else {
                s += """

                - 温和引导学习者使用尚未产出的目标词；绝不要把词汇测验清单当作对话内容。
                """
            }
        }
        s += """

        - 实词优先来自 KNOWN_VOCAB ∪ TARGET_WORDS；可始终使用常见虚词/功能词（代词、系词、助词、基本介词/助动词、否定、疑问词等）。
        - 若 KNOWN_VOCAB 很少，目标词以外仅允许超高频初学实词（例如：\(beginnerList)）。
        - 不要引入新的学习目标词、俚语、习语或专业行话。
        - 与目标词 front 同一语言/文字系统；内容语言跟种子 front，不要改用界面语言说内容。
        - 若学习者上一句不清楚，用简单是非问或选择问。
        - 纠错：可把不通顺的句子用幼儿式语言温和重述一次，然后继续，不要说教。

        TARGET_WORDS（口语中使用 front；back 仅供你理解含义）：
        \(targetJSON)
        """
        if includeUncovered {
            if forceCoverage {
                s += """


                UNCOVERED_TARGETS（挑战：引导每个剩余词进入情境，直到学习者产出）：
                \(uncoveredJSON)
                """
            } else {
                s += """


                UNCOVERED_TARGETS（软目标，学习者尚未产出）：
                \(uncoveredJSON)
                """
            }
        }
        s += """


        KNOWN_VOCAB（脚手架优先用词，可为空）：
        \(knownJSON)
        """
        if !topic.isEmpty {
            s += """


            TOPIC_HINT（尽量贴近的情境）：
            \(topic)
            """
        } else {
            s += """


            TOPIC_HINT：（无——选一个贴合目标词的简单日常情境）
            """
        }
        if sparse {
            s += """


            已知词很少：KNOWN_VOCAB 有限——只用最简单的词；短句轮次优于丰富词汇。
            """
        }
        if isOpening {
            if includeUncovered {
                if forceCoverage {
                    s += """


                    你的任务：用一句简短问候和简单问句开启对话，让某个未覆盖目标词自然可说。仅纯文本。
                    """
                } else {
                    s += """


                    你的任务：用一句简短问候和简单问句开启对话，引导学习者使用某个目标词。仅纯文本。
                    """
                }
            } else {
                s += """


                你的任务：用一句简短问候和简单问句开启对话，贴近话题 / TARGET_WORDS 情境。仅纯文本。
                """
            }
        } else if includeUncovered {
            if forceCoverage {
                s += """


                继续对话，用一句短回复（仅纯文本）。若 UNCOVERED_TARGETS 非空，优先创设能邀请其中一个剩余词的情境或问句；若已空，则自由约束对话。
                """
            } else {
                s += """


                继续对话，用一句短回复（仅纯文本）。优先用能邀请复用目标词的问句。
                """
            }
        } else {
            s += """


            继续对话，用一句短回复（仅纯文本）。保持贴近话题 / TARGET_WORDS 情境。
            """
        }
        return s
    }

    private static func openingKickoffUserMessage(config: SpeakingSessionConfig) -> String {
        if config.appLanguage == .zh {
            return "请现在开始对话。"
        }
        return "Please start the conversation now."
    }

    // MARK: - Encoding

    private struct TargetWordPayload: Encodable {
        let front: String
        let back: String
    }

    private static func encodeTargetWords(_ cards: [Flashcard]) -> String {
        // Same non-empty-front filter as `SpeakingSessionConfig.targetFronts` / coverage lists.
        let payloads = cards.compactMap { card -> TargetWordPayload? in
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty else { return nil }
            return TargetWordPayload(
                front: front,
                back: card.back.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return encodeJSONArray(payloads)
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        encodeJSONArray(values)
    }

    private static func encodeJSONArray<T: Encodable>(_ values: [T]) -> String {
        if let data = try? JSONEncoder().encode(values),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "[]"
    }
}
