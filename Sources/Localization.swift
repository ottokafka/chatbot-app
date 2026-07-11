import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case zh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "EN"
        case .zh: return "中文"
        }
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .en
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

enum L10n {
    // MARK: - Sidebar
    static func newChat(_ lang: AppLanguage) -> String {
        lang == .zh ? "新建对话" : "New Chat"
    }

    static func conversations(_ lang: AppLanguage) -> String {
        lang == .zh ? "对话" : "Conversations"
    }

    static func deleteConversation(_ lang: AppLanguage) -> String {
        lang == .zh ? "删除对话" : "Delete conversation"
    }

    // MARK: - Empty State
    static func noConversationSelected(_ lang: AppLanguage) -> String {
        lang == .zh ? "未选择对话" : "No Conversation Selected"
    }

    static func emptyStateHint(_ lang: AppLanguage) -> String {
        lang == .zh ? "新建对话或选择已有对话开始使用。" : "Create a new chat or select an existing conversation to get started."
    }

    static func startNewChat(_ lang: AppLanguage) -> String {
        lang == .zh ? "开始新对话" : "Start New Chat"
    }

    // MARK: - Chat Header
    static func noPrompt(_ lang: AppLanguage) -> String {
        lang == .zh ? "无提示词" : "No Prompt"
    }

    static func endpoints(_ lang: AppLanguage) -> String {
        lang == .zh ? "接口配置" : "Endpoints"
    }

    static func messageTranslation(_ lang: AppLanguage) -> String {
        lang == .zh ? "消息翻译" : "Translation"
    }

    static func messageTranslationOff(_ lang: AppLanguage) -> String {
        lang == .zh ? "消息翻译 (关)" : "Translation (Off)"
    }

    static func phonics(_ lang: AppLanguage) -> String {
        lang == .zh ? "拼音" : "Phonics"
    }

    static func phonicsOff(_ lang: AppLanguage) -> String {
        lang == .zh ? "拼音 (关)" : "Phonics (Off)"
    }

    static func selectSystemPromptHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "选择系统提示词" : "Select System Prompt"
    }

    static func manageEndpointsHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "管理接口配置" : "Manage Endpoint Configurations"
    }

    static func toggleMessageTranslationHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "开关消息翻译" : "Toggle message translation"
    }

    static func togglePhonicsHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "开关拼音显示" : "Toggle Pinyin phonics"
    }

    static func speechPipelineModeHelp(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "直接语音识别，或 语音识别 + LLM 纠错练习"
            : "Direct speech-to-text, or speech-to-text + LLM practice correction"
    }

    static func speechPipelineDirect(_ lang: AppLanguage) -> String {
        lang == .zh ? "直接 STT" : "Direct STT"
    }

    static func speechPipelineSTTPlusLLM(_ lang: AppLanguage) -> String {
        lang == .zh ? "STT + LLM" : "STT + LLM"
    }

    static func speechPipelineDirectHelp(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "识别结果直接进入对话，不做纠错"
            : "Send raw speech-to-text into the chat with no correction"
    }

    static func speechPipelineSTTPlusLLMHelp(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "识别后再用 LLM 纠错并给出发音提示（练习模式）"
            : "Correct ASR with the LLM and show pronunciation tips (practice mode)"
    }

    static func speechPipelineLabel(_ mode: SpeechPipelineMode, lang: AppLanguage) -> String {
        switch mode {
        case .directSTT: return speechPipelineDirect(lang)
        case .sttPlusLLM: return speechPipelineSTTPlusLLM(lang)
        }
    }

    static func sttLanguageHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "强制语音识别语言（传给 NVIDIA STT）" : "Force STT language for NVIDIA speech server"
    }

    static func heardAs(_ lang: AppLanguage) -> String {
        lang == .zh ? "识别为" : "Heard"
    }

    static func pronunciationTip(_ lang: AppLanguage) -> String {
        lang == .zh ? "发音提示" : "Tip"
    }

    // MARK: - iOS Chat Tools Menu
    static func chatTools(_ lang: AppLanguage) -> String {
        lang == .zh ? "聊天工具" : "Chat tools"
    }

    static func chatToolsHint(_ lang: AppLanguage) -> String {
        lang == .zh ? "打开工具菜单" : "Opens the tools menu"
    }

    static func toolPrompt(_ lang: AppLanguage) -> String {
        lang == .zh ? "提示词" : "Prompt"
    }

    static func toolEndpoints(_ lang: AppLanguage) -> String {
        lang == .zh ? "接口" : "Endpoints"
    }

    static func toolTranslation(_ lang: AppLanguage) -> String {
        lang == .zh ? "翻译" : "Translation"
    }

    static func toolPhonics(_ lang: AppLanguage) -> String {
        lang == .zh ? "拼音" : "Phonics"
    }

    static func toolSpeechMode(_ lang: AppLanguage) -> String {
        lang == .zh ? "语音" : "Speech"
    }

    static func toolsBack(_ lang: AppLanguage) -> String {
        lang == .zh ? "返回" : "Back"
    }

    static func a11yOn(_ lang: AppLanguage) -> String {
        lang == .zh ? "开" : "On"
    }

    static func a11yOff(_ lang: AppLanguage) -> String {
        lang == .zh ? "关" : "Off"
    }

    // MARK: - Input Area
    static func messagePlaceholder(_ lang: AppLanguage) -> String {
        lang == .zh ? "输入消息发送给助手…" : "Type a message to assistant..."
    }

    static func startListening(_ lang: AppLanguage) -> String {
        lang == .zh ? "开始聆听" : "Start listening"
    }

    static func stopListening(_ lang: AppLanguage) -> String {
        lang == .zh ? "停止聆听" : "Stop listening"
    }

    static func stopAudioPlayback(_ lang: AppLanguage) -> String {
        lang == .zh ? "停止播放" : "Stop audio playback"
    }

    static func noAudioPlaying(_ lang: AppLanguage) -> String {
        lang == .zh ? "暂无音频播放" : "No audio playing"
    }

    static func playMessageAudio(_ lang: AppLanguage) -> String {
        lang == .zh ? "播放回复音频" : "Play response audio"
    }

    static func playQuestionAudio(_ lang: AppLanguage) -> String {
        lang == .zh ? "播放问题音频" : "Play question audio"
    }

    static func playFlashcardAudio(_ lang: AppLanguage) -> String {
        lang == .zh ? "播放词汇音频" : "Play vocabulary audio"
    }

    // MARK: - Message Roles
    static func developerRole(_ lang: AppLanguage) -> String {
        lang == .zh ? "用户" : "DEVELOPER"
    }

    static func assistantRole(_ lang: AppLanguage) -> String {
        lang == .zh ? "助手" : "ASSISTANT"
    }

    // MARK: - System Prompt Modal
    static func selectSystemPrompt(_ lang: AppLanguage) -> String {
        lang == .zh ? "选择系统提示词" : "Select System Prompt"
    }

    static func tabSelect(_ lang: AppLanguage) -> String {
        lang == .zh ? "选择" : "Select"
    }

    static func tabCreateEdit(_ lang: AppLanguage) -> String {
        lang == .zh ? "创建 / 编辑" : "Create / Edit"
    }

    static func promptTitlePlaceholder(_ lang: AppLanguage) -> String {
        lang == .zh ? "标题（如：语法专家）" : "Title (e.g. Grammar Expert)"
    }

    static func cancel(_ lang: AppLanguage) -> String {
        lang == .zh ? "取消" : "Cancel"
    }

    static func savePrompt(_ lang: AppLanguage) -> String {
        lang == .zh ? "保存提示词" : "Save Prompt"
    }

    static func updatePrompt(_ lang: AppLanguage) -> String {
        lang == .zh ? "更新提示词" : "Update Prompt"
    }

    static func generatePromptWithAI(_ lang: AppLanguage) -> String {
        lang == .zh ? "✨ 用 AI 生成提示词" : "✨ Generate Prompt with AI"
    }

    static func generating(_ lang: AppLanguage) -> String {
        lang == .zh ? "生成中…" : "Generating..."
    }

    static func editSystemPromptHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "编辑系统提示词" : "Edit system prompt"
    }

    static func deleteSystemPromptHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "删除系统提示词" : "Delete system prompt"
    }

    // MARK: - Endpoint Modal
    static func newConfiguration(_ lang: AppLanguage) -> String {
        lang == .zh ? "新建配置" : "New Configuration"
    }

    static func configurations(_ lang: AppLanguage) -> String {
        lang == .zh ? "配置列表" : "Configurations"
    }

    static func done(_ lang: AppLanguage) -> String {
        lang == .zh ? "完成" : "Done"
    }

    static func noConfigurationSelected(_ lang: AppLanguage) -> String {
        lang == .zh ? "未选择配置" : "No Configuration Selected"
    }

    static func configurationName(_ lang: AppLanguage) -> String {
        lang == .zh ? "配置名称" : "Configuration Name"
    }

    static func configNameLabel(_ lang: AppLanguage) -> String {
        lang == .zh ? "配置名称：" : "Config Name:"
    }

    static func active(_ lang: AppLanguage) -> String {
        lang == .zh ? "启用" : "ACTIVE"
    }

    static func inactive(_ lang: AppLanguage) -> String {
        lang == .zh ? "未启用" : "INACTIVE"
    }

    static func textGeneration(_ lang: AppLanguage) -> String {
        lang == .zh ? "文本生成" : "TEXT GENERATION"
    }

    static func textGenerationURL(_ lang: AppLanguage) -> String {
        lang == .zh ? "文本生成 URL" : "Text Generation URL"
    }

    static func test(_ lang: AppLanguage) -> String {
        lang == .zh ? "测试" : "Test"
    }

    static func testConnection(_ lang: AppLanguage) -> String {
        lang == .zh ? "测试连接" : "Test Connection"
    }

    static func testing(_ lang: AppLanguage) -> String {
        lang == .zh ? "测试中…" : "Testing..."
    }

    static func textGenSamplePlaceholder(_ lang: AppLanguage) -> String {
        lang == .zh ? "模型生成的示例文本将显示在这里。" : "Sample text generated by the model will appear here."
    }

    static func tts(_ lang: AppLanguage) -> String {
        lang == .zh ? "语音合成" : "TTS"
    }

    static func ttsURL(_ lang: AppLanguage) -> String {
        lang == .zh ? "语音合成 URL" : "TTS URL"
    }

    static func ttsVoice(_ lang: AppLanguage) -> String {
        lang == .zh ? "语音" : "TTS Voice"
    }

    static func voice(_ lang: AppLanguage) -> String {
        lang == .zh ? "语音" : "Voice"
    }

    static func noVoicesLoaded(_ lang: AppLanguage) -> String {
        lang == .zh ? "未加载语音（请检查语音合成服务）" : "No voices loaded (check TTS server)"
    }

    static func ttsSpeed(_ lang: AppLanguage) -> String {
        lang == .zh ? "语速" : "TTS Speed"
    }

    static func speed(_ lang: AppLanguage) -> String {
        lang == .zh ? "语速" : "Speed"
    }

    static func enterTextForSpeech(_ lang: AppLanguage) -> String {
        lang == .zh ? "输入要合成的文本" : "Enter Text for Speech"
    }

    static func synthesizePlaceholder(_ lang: AppLanguage) -> String {
        lang == .zh ? "输入要合成的文本…" : "Type text to synthesize..."
    }

    static func playTestAudio(_ lang: AppLanguage) -> String {
        lang == .zh ? "播放测试音频" : "Play Test Audio"
    }

    static func playing(_ lang: AppLanguage) -> String {
        lang == .zh ? "播放中…" : "Playing..."
    }

    static func stt(_ lang: AppLanguage) -> String {
        lang == .zh ? "语音识别" : "STT"
    }

    static func sttURL(_ lang: AppLanguage) -> String {
        lang == .zh ? "语音识别 URL" : "STT URL"
    }

    static func startDictation(_ lang: AppLanguage) -> String {
        lang == .zh ? "开始听写" : "Start Dictation"
    }

    static func stopDictation(_ lang: AppLanguage) -> String {
        lang == .zh ? "停止听写" : "Stop Dictation"
    }

    static func listeningSpeakNow(_ lang: AppLanguage) -> String {
        lang == .zh ? "正在聆听，请说话。" : "Listening... Speak now."
    }

    static func dictationPlaceholder(_ lang: AppLanguage) -> String {
        lang == .zh ? "听写文本将实时显示在这里。" : "Live dictation text appears here as you speak."
    }

    static func save(_ lang: AppLanguage) -> String {
        lang == .zh ? "保存" : "Save"
    }

    static func delete(_ lang: AppLanguage) -> String {
        lang == .zh ? "删除" : "Delete"
    }

    static func useThisConfiguration(_ lang: AppLanguage) -> String {
        lang == .zh ? "使用此配置" : "Use this configuration"
    }

    static func configuration(_ lang: AppLanguage) -> String {
        lang == .zh ? "配置" : "Configuration"
    }

    static func configurationNotFound(_ lang: AppLanguage) -> String {
        lang == .zh ? "未找到配置" : "Configuration Not Found"
    }

    static func configurationDeletedHint(_ lang: AppLanguage) -> String {
        lang == .zh ? "该配置可能已被删除。" : "This configuration may have been deleted."
    }

    static func noURLSet(_ lang: AppLanguage) -> String {
        lang == .zh ? "未设置 URL" : "No URL set"
    }

    static func connectingAndGenerating(_ lang: AppLanguage) -> String {
        lang == .zh ? "正在连接并生成…" : "Connecting and generating..."
    }

    // MARK: - Default Names
    static func defaultConfigName(_ lang: AppLanguage) -> String {
        lang == .zh ? "默认配置" : "Default Config"
    }

    static func newConfigName(_ lang: AppLanguage) -> String {
        lang == .zh ? "新建配置" : "New Config"
    }

    // MARK: - Console (header only)
    static func systemConsoleLogs(_ lang: AppLanguage) -> String {
        lang == .zh ? "系统控制台日志" : "System Console Logs"
    }

    static func copyLogs(_ lang: AppLanguage) -> String {
        lang == .zh ? "复制日志" : "Copy Logs"
    }

    static func clear(_ lang: AppLanguage) -> String {
        lang == .zh ? "清空" : "Clear"
    }

    static func uiLanguageHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "切换界面语言" : "Switch interface language"
    }

    // MARK: - Flashcards
    static func addToFlashcard(_ lang: AppLanguage) -> String {
        lang == .zh ? "添加到闪卡" : "Add to Flashcard"
    }

    static func addEntireMessage(_ lang: AppLanguage) -> String {
        lang == .zh ? "添加整条消息" : "Add Entire Message"
    }

    static func createFlashcard(_ lang: AppLanguage) -> String {
        lang == .zh ? "创建闪卡" : "Create Flashcard"
    }

    static func flashcardFront(_ lang: AppLanguage) -> String {
        lang == .zh ? "正面" : "Front"
    }

    static func flashcardBack(_ lang: AppLanguage) -> String {
        lang == .zh ? "背面" : "Back"
    }

    static func flashcardPhonics(_ lang: AppLanguage) -> String {
        lang == .zh ? "拼音" : "Phonics"
    }

    static func flashcardFrontPlaceholder(_ lang: AppLanguage) -> String {
        lang == .zh ? "词汇或句子…" : "Word or sentence..."
    }

    static func flashcardBackPlaceholder(_ lang: AppLanguage) -> String {
        lang == .zh ? "翻译或释义…" : "Translation or definition..."
    }

    static func flashcardPhonicsPlaceholder(_ lang: AppLanguage) -> String {
        lang == .zh ? "自动生成的拼音…" : "Auto-generated pinyin..."
    }

    static func saveFlashcard(_ lang: AppLanguage) -> String {
        lang == .zh ? "保存闪卡" : "Save Flashcard"
    }

    static func flashcardDuplicate(_ lang: AppLanguage) -> String {
        lang == .zh ? "该词条已存在" : "This entry already exists"
    }

    static func flashcardFrontRequired(_ lang: AppLanguage) -> String {
        lang == .zh ? "请填写正面内容" : "Front text is required"
    }

    static func flashcardBackRequired(_ lang: AppLanguage) -> String {
        lang == .zh ? "请填写背面内容" : "Back text is required"
    }

    static func flashcardSaveFailed(_ lang: AppLanguage) -> String {
        lang == .zh ? "保存闪卡失败" : "Failed to save flashcard"
    }

    static func translating(_ lang: AppLanguage) -> String {
        lang == .zh ? "翻译中…" : "Translating..."
    }

    static func flashcards(_ lang: AppLanguage) -> String {
        lang == .zh ? "闪卡" : "Flashcards"
    }

    static func flashcardsWithDue(_ lang: AppLanguage, due: Int) -> String {
        if lang == .zh {
            return due > 0 ? "闪卡 (\(due))" : "闪卡"
        }
        return due > 0 ? "Flashcards (\(due))" : "Flashcards"
    }

    static func flashcardDeckSummary(_ lang: AppLanguage, total: Int, due: Int) -> String {
        if lang == .zh {
            return "\(total) 张闪卡 · \(due) 张待复习"
        }
        return "\(total) cards · \(due) due"
    }

    static func flashcardKindVocabTab(_ lang: AppLanguage, due: Int) -> String {
        if lang == .zh {
            return due > 0 ? "词汇 (\(due))" : "词汇"
        }
        return due > 0 ? "Vocabulary (\(due))" : "Vocabulary"
    }

    static func flashcardKindExampleTab(_ lang: AppLanguage, due: Int) -> String {
        if lang == .zh {
            return due > 0 ? "例句 (\(due))" : "例句"
        }
        return due > 0 ? "Examples (\(due))" : "Examples"
    }

    static func flashcardKindSummary(
        _ lang: AppLanguage,
        kind: FlashcardKind,
        total: Int,
        due: Int
    ) -> String {
        if lang == .zh {
            let label = kind == .vocab ? "词汇" : "例句"
            return "\(label) \(total) 张 · \(due) 张待复习"
        }
        let label = kind == .vocab ? "Vocabulary" : "Examples"
        return "\(label): \(total) cards · \(due) due"
    }

    static func noExampleFlashcards(_ lang: AppLanguage) -> String {
        lang == .zh ? "暂无保存的例句" : "No saved examples yet"
    }

    static func noExampleFlashcardsHint(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "用「AI 练习」生成例句，并在预览中保存到例句库。"
            : "Use Practice with AI, then save favorites into Examples."
    }

    static func studyNow(_ lang: AppLanguage, count: Int) -> String {
        if lang == .zh {
            return count > 0 ? "开始学习 (\(count))" : "开始学习"
        }
        return count > 0 ? "Study Now (\(count))" : "Study Now"
    }

    static func noFlashcards(_ lang: AppLanguage) -> String {
        lang == .zh ? "暂无闪卡" : "No flashcards yet"
    }

    static func noFlashcardsHint(_ lang: AppLanguage) -> String {
        lang == .zh ? "在对话中选中文本，右键添加到闪卡。" : "Select text in a conversation and add it to a flashcard."
    }

    static func searchFlashcards(_ lang: AppLanguage) -> String {
        lang == .zh ? "搜索闪卡…" : "Search flashcards…"
    }

    static func clearSearch(_ lang: AppLanguage) -> String {
        lang == .zh ? "清空搜索" : "Clear search"
    }

    static func noSearchResults(_ lang: AppLanguage) -> String {
        lang == .zh ? "没有匹配的闪卡" : "No flashcards match your search"
    }

    static func noSearchResultsHint(_ lang: AppLanguage) -> String {
        lang == .zh ? "试试其他关键词，或清空搜索。" : "Try a different keyword, or clear the search."
    }

    static func dueToday(_ lang: AppLanguage) -> String {
        lang == .zh ? "今日到期" : "Due today"
    }

    static func dueInDays(_ lang: AppLanguage, days: Int) -> String {
        lang == .zh ? "\(days) 天后" : "Due in \(days)d"
    }

    static func editFlashcard(_ lang: AppLanguage) -> String {
        lang == .zh ? "编辑" : "Edit"
    }

    static func editFlashcardTitle(_ lang: AppLanguage) -> String {
        lang == .zh ? "编辑闪卡" : "Edit Flashcard"
    }

    static func updateFlashcard(_ lang: AppLanguage) -> String {
        lang == .zh ? "更新闪卡" : "Update Flashcard"
    }

    static func reviewProgress(_ lang: AppLanguage, current: Int, total: Int) -> String {
        lang == .zh ? "第 \(current) / \(total) 张" : "Card \(current) of \(total)"
    }

    static func autoPlayAudio(_ lang: AppLanguage) -> String {
        lang == .zh ? "自动播放" : "Auto-play"
    }

    static func autoPlayAudioHelp(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "自动朗读每张卡片的正面"
            : "Automatically play the front of each card"
    }

    static func tapToReveal(_ lang: AppLanguage) -> String {
        lang == .zh ? "点击或按空格显示答案" : "Tap or press Space to reveal"
    }

    static func revealAnswer(_ lang: AppLanguage) -> String {
        lang == .zh ? "显示答案" : "Reveal Answer"
    }

    static func spaceToReveal(_ lang: AppLanguage) -> String {
        lang == .zh ? "空格：显示答案" : "Space: reveal answer"
    }

    static func spaceToGradeGood(_ lang: AppLanguage) -> String {
        lang == .zh ? "空格：良好" : "Space: Good"
    }

    static func spaceToAdvancePractice(_ lang: AppLanguage) -> String {
        lang == .zh ? "空格：下一张" : "Space: Next"
    }

    static func reviewComplete(_ lang: AppLanguage) -> String {
        lang == .zh ? "复习完成！" : "Review complete!"
    }

    static func noCardsDue(_ lang: AppLanguage) -> String {
        lang == .zh ? "暂无待复习的闪卡" : "No cards due for review"
    }

    static func gradeAgain(_ lang: AppLanguage) -> String {
        lang == .zh ? "重来" : "Again"
    }

    static func gradeHard(_ lang: AppLanguage) -> String {
        lang == .zh ? "困难" : "Hard"
    }

    static func gradeGood(_ lang: AppLanguage) -> String {
        lang == .zh ? "良好" : "Good"
    }

    static func gradeEasy(_ lang: AppLanguage) -> String {
        lang == .zh ? "简单" : "Easy"
    }

    static func deleteFlashcardHelp(_ lang: AppLanguage) -> String {
        lang == .zh ? "删除闪卡" : "Delete flashcard"
    }

    // MARK: - Practice Pack

    static func practiceWithAI(_ lang: AppLanguage) -> String {
        lang == .zh ? "AI 练习" : "Practice with AI"
    }

    static func practiceTheseWithAI(_ lang: AppLanguage) -> String {
        lang == .zh ? "用 AI 练习这些词" : "Practice these with AI"
    }

    static func practiceSelectCards(_ lang: AppLanguage) -> String {
        lang == .zh ? "选择" : "Select"
    }

    static func practiceSelectCardsHelp(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "选择词汇卡生成 AI 练习（最多 \(PracticeGenerationConfig.maxDueSeeds) 张）"
            : "Choose vocabulary cards for AI practice (up to \(PracticeGenerationConfig.maxDueSeeds))"
    }

    static func practiceCancelSelection(_ lang: AppLanguage) -> String {
        lang == .zh ? "取消选择" : "Cancel selection"
    }

    static func practiceSelectedWithAI(_ lang: AppLanguage, count: Int) -> String {
        if lang == .zh {
            return count > 0 ? "练习所选 (\(count))" : "练习所选"
        }
        return count > 0 ? "Practice selected (\(count))" : "Practice selected"
    }

    static func practiceSelectedWithAIHelp(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "根据所选词汇生成例句；不影响复习进度，保存则进入例句库"
            : "Generate examples from selected vocabulary; does not affect schedule; saves go to Examples"
    }

    static func practiceSelectionCount(
        _ lang: AppLanguage,
        selected: Int,
        max: Int
    ) -> String {
        if lang == .zh {
            return "已选 \(selected)/\(max)"
        }
        return "\(selected)/\(max) selected"
    }

    static func practiceSelectionLimitReached(_ lang: AppLanguage, max: Int) -> String {
        if lang == .zh {
            return "最多选择 \(max) 张卡作为练习种子"
        }
        return "You can select up to \(max) cards for practice"
    }

    static func practiceSelectAllVisible(_ lang: AppLanguage) -> String {
        lang == .zh ? "全选可见" : "Select visible"
    }

    static func practiceAfterStudySubtitle(_ lang: AppLanguage, count: Int) -> String {
        if lang == .zh {
            return "把刚学过的 \(count) 个词变成例句练习（不影响复习进度）"
        }
        let word = count == 1 ? "word" : "words"
        return "Turn the \(count) \(word) you just studied into example sentences (does not affect your schedule)"
    }

    static func practiceWithAIHelp(
        _ lang: AppLanguage,
        hasDueVocab: Bool = true,
        lastSessionCount: Int = 0
    ) -> String {
        if hasDueVocab {
            return lang == .zh
                ? "根据到期词汇生成练习例句；默认不保存，保存则进入例句库"
                : "Generate practice from due vocabulary; ephemeral unless saved to Examples"
        }
        if lastSessionCount > 0 {
            if lang == .zh {
                return "没有到期卡 — 根据上次学习的 \(lastSessionCount) 个词生成例句；保存则进入例句库"
            }
            let word = lastSessionCount == 1 ? "word" : "words"
            return "No cards due — practice example sentences from your last study session (\(lastSessionCount) \(word)); saves go to Examples"
        }
        return lang == .zh
            ? "根据词汇生成练习例句；默认不保存，保存则进入例句库"
            : "Generate practice from vocabulary; ephemeral unless saved to Examples"
    }

    static func practiceWithAIMenuHelp(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "点击用默认来源生成练习；打开菜单可在到期词汇与上次学习之间选择"
            : "Click to practice from the default source; open the menu to choose due vocabulary or your last study session"
    }

    static func practiceFromDueVocab(_ lang: AppLanguage, count: Int) -> String {
        if lang == .zh {
            return "到期词汇 (\(count))"
        }
        return "Due vocabulary (\(count))"
    }

    static func practiceFromLastStudySession(_ lang: AppLanguage, count: Int) -> String {
        if lang == .zh {
            return "上次学习 (\(count))"
        }
        return "Last study session (\(count))"
    }

    static func practiceGenerating(_ lang: AppLanguage) -> String {
        lang == .zh ? "正在生成练习…" : "Generating practice…"
    }

    static func practicePreviewTitle(_ lang: AppLanguage) -> String {
        lang == .zh ? "练习预览" : "Practice Preview"
    }

    static func practicePreviewSummary(_ lang: AppLanguage, cards: Int, seeds: Int) -> String {
        if lang == .zh {
            return "基于 \(seeds) 张词汇卡生成了 \(cards) 条例句"
        }
        return "\(cards) examples from \(seeds) seed card\(seeds == 1 ? "" : "s")"
    }

    static func practicePreviewAINote(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "由 AI 用你已学的词生成简单练习句。可编辑、重生成；保存会进入「例句」库，不会写入词汇。"
            : "AI-generated simple practice using words you know. Edit or regenerate; saves go to Examples, not Vocabulary."
    }

    static func practiceSelectAll(_ lang: AppLanguage) -> String {
        lang == .zh ? "全选" : "Select all"
    }

    static func practiceDeselectAll(_ lang: AppLanguage) -> String {
        lang == .zh ? "取消全选" : "Deselect all"
    }

    static func practiceSaveSelected(_ lang: AppLanguage, count: Int) -> String {
        if lang == .zh {
            return count > 0 ? "保存到例句 (\(count))" : "保存到例句"
        }
        return count > 0 ? "Save to Examples (\(count))" : "Save to Examples"
    }

    static func practiceSaveOne(_ lang: AppLanguage) -> String {
        lang == .zh ? "保存到例句" : "Save to Examples"
    }

    static func practiceSavedBadge(_ lang: AppLanguage) -> String {
        lang == .zh ? "已保存" : "Saved"
    }

    static func practiceRegenerateOne(_ lang: AppLanguage) -> String {
        lang == .zh ? "重生成此条" : "Regenerate"
    }

    static func practiceRegenerateMissingParent(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "找不到对应的原闪卡，无法重生成此例句。"
            : "Could not find the source flashcard for this example."
    }

    static func practiceSaveResultSummary(
        _ lang: AppLanguage,
        saved: Int,
        duplicates: Int,
        failed: Int
    ) -> String {
        if lang == .zh {
            var parts: [String] = []
            if saved > 0 { parts.append("已保存 \(saved) 条到例句库") }
            if duplicates > 0 { parts.append("重复 \(duplicates) 张") }
            if failed > 0 { parts.append("失败 \(failed) 张") }
            if parts.isEmpty { return "没有可保存的例句" }
            return parts.joined(separator: " · ")
        }
        var parts: [String] = []
        if saved > 0 { parts.append("Saved \(saved) to Examples") }
        if duplicates > 0 { parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s")") }
        if failed > 0 { parts.append("\(failed) failed") }
        if parts.isEmpty { return "Nothing to save" }
        return parts.joined(separator: " · ")
    }

    static func practiceInfoTitle(_ lang: AppLanguage) -> String {
        lang == .zh ? "练习" : "Practice"
    }

    static func practiceCompleteSaveHint(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "可选中喜欢的例句保存到卡组。未保存的练习不会影响复习进度。"
            : "Optionally save favorites into your deck. Unsaved practice does not affect review schedules."
    }

    static func practiceMarkForSave(_ lang: AppLanguage) -> String {
        lang == .zh ? "标记保存" : "Mark to save"
    }

    static func practiceRegenerate(_ lang: AppLanguage) -> String {
        lang == .zh ? "重新生成" : "Regenerate"
    }

    static func practiceMissingLLMEndpoint(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "未配置文本生成接口，请先在接口配置中设置。"
            : "No text-generation endpoint configured. Set one in Endpoints."
    }

    static func practiceGenerationFailedDetail(_ lang: AppLanguage, detail: String) -> String {
        if lang == .zh {
            return "生成练习失败：\(detail)"
        }
        return "Failed to generate practice: \(detail)"
    }

    static func practiceSentenceLabel(_ lang: AppLanguage) -> String {
        lang == .zh ? "例句" : "Sentence"
    }

    static func practiceTranslationLabel(_ lang: AppLanguage) -> String {
        lang == .zh ? "翻译" : "Translation"
    }

    static func practiceFromWord(_ lang: AppLanguage, word: String) -> String {
        lang == .zh ? "来自：\(word)" : "From: \(word)"
    }

    static func startPractice(_ lang: AppLanguage) -> String {
        lang == .zh ? "开始练习" : "Start Practice"
    }

    static func discardPractice(_ lang: AppLanguage) -> String {
        lang == .zh ? "丢弃练习" : "Discard Practice"
    }

    static func removePracticeCard(_ lang: AppLanguage) -> String {
        lang == .zh ? "移除" : "Remove"
    }

    static func practiceSessionTitle(_ lang: AppLanguage) -> String {
        lang == .zh ? "练习" : "Practice"
    }

    static func practiceProgress(_ lang: AppLanguage, current: Int, total: Int) -> String {
        lang == .zh ? "练习 \(current) / \(total)" : "Practice \(current) of \(total)"
    }

    static func practiceComplete(_ lang: AppLanguage) -> String {
        lang == .zh ? "练习完成！" : "Practice complete!"
    }

    static func practiceCompleteHint(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "练习本身不影响复习进度。喜欢的例句可勾选后保存到卡组。"
            : "Practice itself does not affect review schedules. Select favorites below to save into your deck."
    }

    static func practiceNext(_ lang: AppLanguage) -> String {
        lang == .zh ? "下一张" : "Next"
    }

    static func practiceEmptyPreview(_ lang: AppLanguage) -> String {
        lang == .zh ? "没有可练习的卡片" : "No practice cards left"
    }

    static func practiceEmptyPreviewHint(_ lang: AppLanguage) -> String {
        lang == .zh ? "移除了全部例句。可以丢弃后重新生成。" : "You removed every example. Discard and generate again."
    }

    static func practiceNoDueCards(_ lang: AppLanguage) -> String {
        practiceNoSeeds(lang)
    }

    static func practiceNoSeeds(_ lang: AppLanguage) -> String {
        lang == .zh
            ? "没有可练习的词汇。请先学习一些卡片，或等到有卡片到期。"
            : "No vocabulary available to practice. Study some cards first, or wait until cards are due."
    }

    static func practiceGenerationFailed(_ lang: AppLanguage) -> String {
        lang == .zh ? "生成练习失败" : "Failed to generate practice cards"
    }

    static func practiceErrorTitle(_ lang: AppLanguage) -> String {
        lang == .zh ? "练习出错" : "Practice error"
    }

    static func dismissError(_ lang: AppLanguage) -> String {
        lang == .zh ? "关闭" : "Dismiss"
    }
}

// MARK: - Language Toggle

struct LanguageToggle: View {
    @Binding var language: AppLanguage

    var body: some View {
        Picker("", selection: $language) {
            ForEach(AppLanguage.allCases) { lang in
                Text(lang.displayName).tag(lang)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help(L10n.uiLanguageHelp(language))
    }
}