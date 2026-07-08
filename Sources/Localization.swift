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