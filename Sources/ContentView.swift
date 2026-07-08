import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var flashcardVM = FlashcardViewModel()
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var textInput = ""
    @State private var isShowingPromptModal = false
    @State private var isShowingEndpointModal = false
    @State private var isLogsExpanded = true
    @State private var logsHeight: CGFloat = 160
    
    @State private var isPromptHovered = false
    @State private var isEndpointsHovered = false
    @State private var isTranslationHovered = false
    @State private var isPhonicsHovered = false
    @State private var appSection: AppSection = .conversations
    @State private var selectedFlashcard: Flashcard?
    
    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $appSection) {
                    Text(L10n.conversations(lang)).tag(AppSection.conversations)
                    Text(L10n.flashcardsWithDue(lang, due: flashcardVM.dueCount)).tag(AppSection.flashcards)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if appSection == .conversations {
                    Button(action: {
                        viewModel.startNewConversation()
                    }) {
                        HStack {
                            Image(systemName: "plus.bubble")
                            Text(L10n.newChat(lang))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)

                    List(viewModel.conversations, selection: Binding(
                        get: { viewModel.activeConversation },
                        set: { val in if let v = val { viewModel.selectConversation(v) } }
                    )) { conversation in
                        NavigationLink(value: conversation) {
                            HStack {
                                Image(systemName: "message")
                                    .foregroundColor(.secondary)
                                Text(conversation.title)
                                    .lineLimit(1)
                                    .font(.body)
                                Spacer()
                                Button(action: {
                                    viewModel.deleteConversation(conversation)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .help(L10n.deleteConversation(lang))
                            }
                        }
                        .tag(conversation)
                    }
                    .listStyle(.sidebar)
                } else {
                    List(flashcardVM.flashcards, selection: $selectedFlashcard) { card in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.front)
                                    .lineLimit(1)
                                    .font(.body)
                                Text(flashcardVM.dueLabel(for: card, language: lang))
                                    .font(.caption2)
                                    .foregroundColor(flashcardVM.isDue(card) ? .orange : .secondary)
                            }
                            Spacer()
                            Button(action: {
                                flashcardVM.deleteFlashcard(card)
                                if selectedFlashcard?.id == card.id {
                                    selectedFlashcard = nil
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help(L10n.deleteFlashcardHelp(lang))
                        }
                        .tag(card)
                    }
                    .listStyle(.sidebar)
                }
                
                Divider()
                    .padding(.horizontal)
                
                LanguageToggle(language: $viewModel.appLanguage)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle(appSection == .conversations ? L10n.conversations(lang) : L10n.flashcards(lang))
            .frame(minWidth: 200, idealWidth: 240)
            .onChange(of: appSection) { _, newSection in
                if newSection == .flashcards {
                    flashcardVM.loadFlashcards()
                }
            }
        } detail: {
            // MAIN DETAIL VIEW
            VStack(spacing: 0) {
                if appSection == .flashcards {
                    FlashcardDeckView(flashcardVM: flashcardVM)
                } else if viewModel.activeConversation != nil {
                    // Chat Window Header
                    #if !os(iOS)
                    HStack {
                        // Centered Buttons Group
                        HStack(spacing: 12) {
                            // Context Switcher Pill Button (Click #1)
                            Button(action: {
                                isShowingPromptModal.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Text("💬")
                                    Text(viewModel.activeSystemPrompt?.title ?? L10n.noPrompt(lang))
                                    Text("▾")
                                }
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isPromptHovered ? Color.gray.opacity(0.2) : Color.platformControlBackground)
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.gray.opacity(isPromptHovered ? 0.5 : 0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isPromptHovered = $0 }
                            .help(L10n.selectSystemPromptHelp(lang))
                            
                            // Endpoints Button
                            Button(action: {
                                isShowingEndpointModal.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Text("🔌")
                                    Text(L10n.endpoints(lang))
                                }
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(isEndpointsHovered ? Color.gray.opacity(0.2) : Color.platformControlBackground)
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.gray.opacity(isEndpointsHovered ? 0.5 : 0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isEndpointsHovered = $0 }
                            .help(L10n.manageEndpointsHelp(lang))
                            
                            // Translation Toggle Button
                            Button(action: {
                                viewModel.isTranslationEnabled.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Text(viewModel.isTranslationEnabled ? "🌐" : "🌐")
                                    Text(viewModel.isTranslationEnabled ? L10n.messageTranslation(lang) : L10n.messageTranslationOff(lang))
                                }
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(viewModel.isTranslationEnabled ? Color.blue.opacity(0.15) : (isTranslationHovered ? Color.gray.opacity(0.2) : Color.platformControlBackground))
                                        .overlay(
                                            Capsule()
                                                .stroke(viewModel.isTranslationEnabled ? Color.blue.opacity(0.6) : (Color.gray.opacity(isTranslationHovered ? 0.5 : 0.3)), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isTranslationHovered = $0 }
                            .help(L10n.toggleMessageTranslationHelp(lang))
                            
                            // Phonics Toggle Button
                            Button(action: {
                                viewModel.isPhonicsEnabled.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Text(viewModel.isPhonicsEnabled ? "🗣️" : "🗣️")
                                    Text(viewModel.isPhonicsEnabled ? L10n.phonics(lang) : L10n.phonicsOff(lang))
                                }
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(viewModel.isPhonicsEnabled ? Color.blue.opacity(0.15) : (isPhonicsHovered ? Color.gray.opacity(0.2) : Color.platformControlBackground))
                                        .overlay(
                                            Capsule()
                                                .stroke(viewModel.isPhonicsEnabled ? Color.blue.opacity(0.6) : (Color.gray.opacity(isPhonicsHovered ? 0.5 : 0.3)), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isPhonicsHovered = $0 }
                            .help(L10n.togglePhonicsHelp(lang))
                        }
                        
                        Spacer()
                        
                        // Status Bar Indicators
                        HStack(spacing: 12) {
                            StatusIndicator(title: "STT", isActive: viewModel.isWebSocketConnected, activeColor: .green)
                            StatusIndicator(title: "LLM", isActive: viewModel.isGeneratingText, activeColor: .yellow)
                            StatusIndicator(title: "TTS", isActive: viewModel.isGeneratingSpeech, activeColor: .blue)
                            StatusIndicator(title: "AUDIO", isActive: viewModel.isPlayingAudio, activeColor: .orange)
                        }
                        .padding(.trailing, 10)
                    }
                    .padding()
                    .background(Color.platformWindowBackground)
                    #endif
                    
                    Divider()
                    
                    // Messages Viewport
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(viewModel.messages) { message in
                                    MessageRow(
                                        message: message,
                                        flashcardVM: flashcardVM,
                                        isTranslationEnabled: viewModel.isTranslationEnabled,
                                        isPhonicsEnabled: viewModel.isPhonicsEnabled,
                                        isPlaying: viewModel.currentlyPlayingMessageId == message.id && viewModel.isPlayingAudio,
                                        isGeneratingAudio: viewModel.generatingAudioMessageId == message.id,
                                        onPlayAudio: {
                                            viewModel.playMessageAudio(message)
                                        }
                                    )
                                    .id(messageRowID(message.id))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color.platformControlBackground)
                        .onChange(of: viewModel.messages) {
                            if let lastMessage = viewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(messageRowID(lastMessage.id), anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Bottom Input Area
                    HStack(spacing: 12) {
                        // Microphone Button
                        RecordButton(
                            isActive: viewModel.isMicrophoneActive,
                            isConnected: viewModel.isWebSocketConnected,
                            action: {
                                viewModel.toggleMicrophone()
                            }
                        )
                        
                        StopPlaybackButton(
                            isPlaying: viewModel.isPlayingAudio,
                            action: {
                                viewModel.stopPlayback()
                            }
                        )
                        
                        // Message Input Field
                        TextField(L10n.messagePlaceholder(lang), text: $textInput, onCommit: {
                            sendText()
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .controlSize(.large)
                        
                        // Send Button
                        Button(action: {
                            sendText()
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.body)
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    #if os(iOS)
                    .padding(.horizontal)
                    .padding(.vertical, )
                    #else
                    .padding()
                    #endif
                    .background(Color.platformWindowBackground)
                    
                } else {
                    // Empty State
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text(L10n.noConversationSelected(lang))
                            .font(.title2)
                            .fontWeight(.medium)
                        Text(L10n.emptyStateHint(lang))
                            .foregroundColor(.secondary)
                        
                        Button(L10n.startNewChat(lang)) {
                            viewModel.startNewConversation()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                #if os(macOS)
                #if canImport(Translation)
                if #available(macOS 15.0, *) {
                    // Verbose Console Logs Panel
                    Divider()
                    LogConsolePanel(
                        viewModel: viewModel,
                        isExpanded: $isLogsExpanded,
                        height: $logsHeight
                    )
                }
                #endif
                #endif
            }
            .sheet(isPresented: $isShowingPromptModal) {
                SystemPromptModalView(viewModel: viewModel)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $isShowingEndpointModal) {
                EndpointConfigModalView(viewModel: viewModel)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $flashcardVM.isShowingCreateSheet, onDismiss: {
                if flashcardVM.draft != nil {
                    flashcardVM.cancelDraft()
                }
            }) {
                FlashcardCreateSheet(flashcardVM: flashcardVM)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .sheet(isPresented: $flashcardVM.isShowingReviewSession, onDismiss: {
                flashcardVM.endReviewSession()
            }) {
                FlashcardReviewView(flashcardVM: flashcardVM, chatVM: viewModel)
                    .environment(\.appLanguage, viewModel.appLanguage)
            }
            .onAppear {
                flashcardVM.onLog = { message in
                    viewModel.log(message, tag: "DB")
                }
            }
            .onChange(of: flashcardVM.flashcards) { _, _ in
                if let selected = selectedFlashcard,
                   !flashcardVM.flashcards.contains(where: { $0.id == selected.id }) {
                    selectedFlashcard = nil
                }
            }
            .toolbar {
                #if os(iOS)
                if viewModel.activeConversation != nil {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 6) {
                            StatusIndicator(title: "STT", isActive: viewModel.isWebSocketConnected, activeColor: .green, showTitle: false)
                            StatusIndicator(title: "LLM", isActive: viewModel.isGeneratingText, activeColor: .yellow, showTitle: false)
                            StatusIndicator(title: "TTS", isActive: viewModel.isGeneratingSpeech, activeColor: .blue, showTitle: false)
                            StatusIndicator(title: "AUDIO", isActive: viewModel.isPlayingAudio, activeColor: .orange, showTitle: false)
                        }
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        HStack(spacing: 12) {
                            Button(action: {
                                isShowingPromptModal.toggle()
                            }) {
                                Text("💬")
                                    .padding(6)
                                    .background(Circle().fill(Color.gray.opacity(0.12)))
                                    .overlay(Circle().stroke(Color.gray.opacity(0.25), lineWidth: 1))
                            }
                            
                            Button(action: {
                                isShowingEndpointModal.toggle()
                            }) {
                                Text("🔌")
                                    .padding(6)
                                    .background(Circle().fill(Color.gray.opacity(0.12)))
                                    .overlay(Circle().stroke(Color.gray.opacity(0.25), lineWidth: 1))
                            }
                            
                            Button(action: {
                                viewModel.isTranslationEnabled.toggle()
                            }) {
                                Text("🌐")
                                    .padding(6)
                                    .background(Circle().fill(viewModel.isTranslationEnabled ? Color.blue.opacity(0.18) : Color.gray.opacity(0.12)))
                                    .overlay(Circle().stroke(viewModel.isTranslationEnabled ? Color.blue.opacity(0.8) : Color.gray.opacity(0.25), lineWidth: 1))
                            }
                            
                            Button(action: {
                                viewModel.isPhonicsEnabled.toggle()
                            }) {
                                Text("🗣️")
                                    .padding(6)
                                    .background(Circle().fill(viewModel.isPhonicsEnabled ? Color.blue.opacity(0.18) : Color.gray.opacity(0.12)))
                                    .overlay(Circle().stroke(viewModel.isPhonicsEnabled ? Color.blue.opacity(0.8) : Color.gray.opacity(0.25), lineWidth: 1))
                            }
                        }
                    }
                }
                #endif
            }
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .environment(\.appLanguage, viewModel.appLanguage)
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
        #endif
    }
    
    private func messageRowID(_ messageID: String) -> String {
        "\(messageID)-translation-\(viewModel.isTranslationEnabled)"
    }
    
    private func sendText() {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.sendTextMessage(text)
        textInput = ""
    }
}

// MARK: - Message Row View
struct MessageRow: View {
    let message: Message
    @ObservedObject var flashcardVM: FlashcardViewModel
    let isTranslationEnabled: Bool
    let isPhonicsEnabled: Bool
    let isPlaying: Bool
    let isGeneratingAudio: Bool
    let onPlayAudio: () -> Void
    
    @Environment(\.appLanguage) private var lang
    @State private var translatedText: String = ""
    #if canImport(Translation) && !targetEnvironment(simulator)
    @State private var translationConfiguration: TranslationSession.Configuration?
    #endif
    
    var isUser: Bool { message.role == "user" }
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Header (Role & Timestamp)
                HStack(spacing: 8) {
                    Text(isUser ? L10n.developerRole(lang) : L10n.assistantRole(lang))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isUser ? .blue : .green)
                    
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    MessageAudioButton(
                        accent: isUser ? .user : .assistant,
                        isPlaying: isPlaying,
                        isGenerating: isGeneratingAudio,
                        action: onPlayAudio
                    )
                }
                
                // Content Bubble
                VStack(alignment: .leading, spacing: 6) {
                    SelectableMessageText(
                        text: message.content,
                        addToFlashcardLabel: L10n.addToFlashcard(lang),
                        addEntireMessageLabel: L10n.addEntireMessage(lang),
                        onAddFlashcard: { selection in
                            flashcardVM.prepareDraft(
                                front: selection,
                                message: message,
                                translatedText: translatedText
                            )
                        }
                    )

                    if message.content.isChinese() {
                        // Source is Chinese
                        if isPhonicsEnabled, let pinyin = message.content.toPinyin() {
                            Divider()
                                .padding(.top, 2)
                            Text(pinyin)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                                .italic()
                                .textSelection(.enabled)
                        }
                        
                        if isTranslationEnabled && !translatedText.isEmpty {
                            Divider()
                                .padding(.top, 2)
                            Text(translatedText)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        // Source is English/Other
                        if isTranslationEnabled && !translatedText.isEmpty {
                            Divider()
                                .padding(.top, 2)
                            Text(translatedText)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                            
                            if isPhonicsEnabled, let pinyin = translatedText.toPinyin() {
                                Divider()
                                    .padding(.top, 2)
                                Text(pinyin)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isUser ? Color.blue.opacity(0.15) : Color.platformControlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isUser ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                )
                .foregroundColor(.primary)
            }
            
            if !isUser { Spacer() }
        }
        .onAppear {
            updateTranslationConfiguration()
        }
        .onChange(of: isTranslationEnabled) {
            updateTranslationConfiguration()
            if !isTranslationEnabled {
                translatedText = ""
            }
        }
        .onChange(of: message.content) {
            updateTranslationConfiguration()
        }
        #if canImport(Translation) && !targetEnvironment(simulator)
        .translationTask(translationConfiguration) { session in
            do {
                let response = try await session.translate(message.content)
                await MainActor.run {
                    self.translatedText = response.targetText
                }
            } catch {
                print("Translation failed: \(error)")
            }
        }
        #endif
    }
    
    private func updateTranslationConfiguration() {
        guard isTranslationEnabled else {
            #if canImport(Translation) && !targetEnvironment(simulator)
            if #available(macOS 15.0, iOS 17.4, *) {
                translationConfiguration = nil
            }
            #endif
            return
        }
        
        #if canImport(Translation) && !targetEnvironment(simulator)
        if #available(macOS 15.0, iOS 17.4, *) {
            let content = message.content
            if content.isChinese() {
                translationConfiguration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "zh-Hans"),
                    target: Locale.Language(identifier: "en")
                )
            } else if content.detectedLanguage() == "en" || !content.containsChineseCharacters {
                translationConfiguration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "zh-Hans")
                )
            }
        }
        #endif
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let title: String
    let isActive: Bool
    let activeColor: Color
    var showTitle: Bool = true
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? activeColor : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? activeColor.opacity(0.6) : .clear, radius: 2)
            if showTitle {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
        }
        .padding(.horizontal, showTitle ? 6 : 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? activeColor.opacity(0.1) : Color.clear)
        )
    }
}

// MARK: - Record Button View
struct RecordButton: View {
    let isActive: Bool
    let isConnected: Bool
    let action: () -> Void
    
    @Environment(\.appLanguage) private var lang
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? (isConnected ? Color.red : Color.orange) : Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .scaleEffect(isActive ? pulseScale : 1.0)
                    .animation(isActive ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default, value: pulseScale)
                
                Image(systemName: isActive ? "mic.fill" : "mic.slash.fill")
                    .font(.title2)
                    .foregroundColor(isActive ? .white : .primary)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            pulseScale = 1.15
        }
        .help(isActive ? L10n.stopListening(lang) : L10n.startListening(lang))
    }
}

// MARK: - Message Audio Button View
enum MessageAudioAccent {
    case user
    case assistant
    case flashcard

    var idleColor: Color {
        switch self {
        case .user: return .blue
        case .assistant: return .green
        case .flashcard: return .orange
        }
    }
}

struct MessageAudioButton: View {
    let accent: MessageAudioAccent
    let isPlaying: Bool
    let isGenerating: Bool
    let action: () -> Void

    @Environment(\.appLanguage) private var lang
    @State private var isHovered = false

    private var fillColor: Color {
        if isGenerating {
            return Color.secondary.opacity(0.12)
        }
        if isPlaying {
            return isHovered ? Color.red.opacity(0.22) : Color.red.opacity(0.14)
        }
        let base = accent.idleColor
        return isHovered ? base.opacity(0.22) : base.opacity(0.14)
    }

    private var strokeColor: Color {
        if isGenerating {
            return Color.secondary.opacity(0.3)
        }
        if isPlaying {
            return isHovered ? Color.red.opacity(0.65) : Color.red.opacity(0.4)
        }
        let base = accent.idleColor
        return isHovered ? base.opacity(0.65) : base.opacity(0.4)
    }

    private var iconColor: Color {
        if isPlaying { return .red }
        return accent.idleColor
    }

    private var helpText: String {
        if isPlaying { return L10n.stopAudioPlayback(lang) }
        switch accent {
        case .user: return L10n.playQuestionAudio(lang)
        case .assistant: return L10n.playMessageAudio(lang)
        case .flashcard: return L10n.playFlashcardAudio(lang)
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(strokeColor, lineWidth: 1.5)
                    )
                    .scaleEffect(isHovered && !isGenerating ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(iconColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .help(helpText)
    }
}

// MARK: - Stop Playback Button View
struct StopPlaybackButton: View {
    let isPlaying: Bool
    let action: () -> Void
    
    @Environment(\.appLanguage) private var lang
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            if isPlaying {
                action()
            }
        }) {
            ZStack {
                Circle()
                    .fill(isPlaying ? (isHovered ? Color.red.opacity(0.28) : Color.red.opacity(0.18)) : Color.secondary.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(isPlaying ? (isHovered ? Color.red.opacity(0.6) : Color.red.opacity(0.3)) : Color.clear, lineWidth: 1)
                    )
                    .scaleEffect(isPlaying && isHovered ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                
                Image(systemName: "square.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isPlaying ? .red : .secondary.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isPlaying)
        .onHover { hovering in
            if isPlaying {
                isHovered = hovering
            }
        }
        .help(isPlaying ? L10n.stopAudioPlayback(lang) : L10n.noAudioPlaying(lang))
    }
}

// MARK: - Console Log Panel View
struct LogConsolePanel: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isExpanded: Bool
    @Binding var height: CGFloat
    
    private var lang: AppLanguage { viewModel.appLanguage }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .font(.body)
                    Text(L10n.systemConsoleLogs(lang))
                        .font(.headline)
                        .fontDesign(.monospaced)
                }
                Spacer()
                
                HStack(spacing: 12) {
                    Button(L10n.copyLogs(lang)) {
                        let logText = viewModel.logs.map { "[\($0.timestamp.formatted())] [\($0.tag)] \($0.message)" }.joined(separator: "\n")
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(logText, forType: .string)
                        #else
                        UIPasteboard.general.string = logText
                        #endif
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    
                    Button(L10n.clear(lang)) {
                        viewModel.clearLogs()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    
                    Button(action: {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.platformWindowBackground)
            
            if isExpanded {
                Divider()
                // Logs Viewport
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.logs) { log in
                                LogRow(log: log)
                                    .id(log.id)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(red: 0.08, green: 0.08, blue: 0.1)) // Dark terminal color
                    .onChange(of: viewModel.logs) {
                        if let lastLog = viewModel.logs.last {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
                .frame(height: height)
            }
        }
    }
}

// MARK: - Log Row
struct LogRow: View {
    let log: LogEntry
    
    var colorForTag: Color {
        switch log.tag {
        case "SYSTEM": return .gray
        case "STT": return .green
        case "LLM": return .yellow
        case "TTS": return .cyan
        case "AUDIO": return .orange
        case "DB": return .purple
        case "ERROR": return .red
        default: return .white
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Timestamp
            Text("[\(log.timestamp.formatted(date: .omitted, time: .standard))]")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            
            // Tag
            Text("[\(log.tag)]")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(colorForTag)
                .frame(width: 60, alignment: .leading)
            
            // Message
            Text(log.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .textSelection(.enabled)
        }
    }
}

// MARK: - System Prompt Modal View
struct SystemPromptModalView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var newTitle = ""
    @State private var newPromptText = ""
    @State private var isGenerating = false
    @State private var editingPrompt: SystemPrompt? = nil
    @State private var hoveredPromptId: String? = nil
    @State private var iOSActiveTab = 0
    
    var body: some View {
        #if os(iOS)
        VStack(spacing: 0) {
            Picker("", selection: $iOSActiveTab) {
                Text(L10n.tabSelect(lang)).tag(0)
                Text(L10n.tabCreateEdit(lang)).tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if iOSActiveTab == 0 {
                // Select System Prompt List
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.selectSystemPrompt(lang))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.systemPrompts) { prompt in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .center) {
                                        Text(prompt.title)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        // Edit button
                                        Button(action: {
                                            editingPrompt = prompt
                                            newTitle = prompt.title
                                            newPromptText = prompt.promptText
                                            iOSActiveTab = 1
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // Delete button
                                        Button(action: {
                                            viewModel.deleteSystemPrompt(prompt)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Text(prompt.promptText)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(prompt.isActive ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(prompt.isActive ? Color.blue : Color.gray.opacity(0.2), lineWidth: prompt.isActive ? 2 : 1)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.selectSystemPrompt(prompt)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            } else {
                // Create/Edit Prompt Form
                VStack(alignment: .leading, spacing: 16) {
                    
                    HStack(spacing: 8) {
                        // Title Field
                        TextField(L10n.promptTitlePlaceholder(lang), text: $newTitle)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .font(.body)
                        
                        // AI Prompt Generation Button
                        Button(action: {
                            generatePromptWithAI()
                        }) {
                            HStack(spacing: 6) {
                                if isGenerating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("AI")
                                }
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.purple.opacity(0.3) : Color.purple)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                    }
                    
                    // Prompt Content Area
                    TextEditor(text: $newPromptText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(6)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    HStack(spacing: 12) {
                        // Cancel button
                        Button(action: {
                            if editingPrompt != nil {
                                editingPrompt = nil
                                newTitle = ""
                                newPromptText = ""
                                iOSActiveTab = 0
                            } else {
                                dismiss()
                            }
                        }) {
                            Text(L10n.cancel(lang))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        // Save/Update Button
                        Button(action: {
                            savePrompt()
                            iOSActiveTab = 0
                        }) {
                            Text(editingPrompt == nil ? L10n.savePrompt(lang) : L10n.updatePrompt(lang))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(newTitle.isEmpty || newPromptText.isEmpty ? Color.blue.opacity(0.3) : Color.blue)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTitle.isEmpty || newPromptText.isEmpty)
                    }
                }
                .padding(20)
                .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            }
        }
        .preferredColorScheme(.dark)
        #else
        HStack(spacing: 0) {
            // LEFT COLUMN: Select System Prompt (60% width)
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.selectSystemPrompt(lang))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.systemPrompts) { prompt in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .center) {
                                    Text(prompt.title)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    // Edit button
                                    Button(action: {
                                        editingPrompt = prompt
                                        newTitle = prompt.title
                                        newPromptText = prompt.promptText
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .help(L10n.editSystemPromptHelp(lang))
                                    
                                    // Delete button
                                    Button(action: {
                                        viewModel.deleteSystemPrompt(prompt)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help(L10n.deleteSystemPromptHelp(lang))
                                }
                                
                                Text(prompt.promptText)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(prompt.isActive ? Color.blue.opacity(0.15) : (hoveredPromptId == prompt.id ? Color.gray.opacity(0.18) : Color.gray.opacity(0.1)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(prompt.isActive ? Color.blue : Color.gray.opacity(0.2), lineWidth: prompt.isActive ? 2 : 1)
                            )
                            .contentShape(Rectangle())
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredPromptId = prompt.id
                                } else if hoveredPromptId == prompt.id {
                                    hoveredPromptId = nil
                                }
                            }
                            .onTapGesture {
                                viewModel.selectSystemPrompt(prompt)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // RIGHT COLUMN: Create/Edit Prompt (40% width)
            VStack(alignment: .leading, spacing: 16) {
                
                // Title Field
                TextField(L10n.promptTitlePlaceholder(lang), text: $newTitle)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .font(.body)
                
                // AI Prompt Generation Button
                Button(action: {
                    generatePromptWithAI()
                }) {
                    HStack {
                        Spacer()
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text(L10n.generating(lang))
                        } else {
                            Text(L10n.generatePromptWithAI(lang))
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.purple.opacity(0.3) : Color.purple)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                
                // Prompt Content Area
                TextEditor(text: $newPromptText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                // Save/Update Button
                Button(action: {
                    savePrompt()
                }) {
                    Text(editingPrompt == nil ? L10n.savePrompt(lang) : L10n.updatePrompt(lang))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(newTitle.isEmpty || newPromptText.isEmpty ? Color.blue.opacity(0.3) : Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(newTitle.isEmpty || newPromptText.isEmpty)
                
                // Cancel button
                Button(action: {
                    if editingPrompt != nil {
                        editingPrompt = nil
                        newTitle = ""
                        newPromptText = ""
                    } else {
                        dismiss()
                    }
                }) {
                    Text(L10n.cancel(lang))
                        .foregroundColor(.gray)
                        .underline()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(minWidth: 320, maxWidth: 320, maxHeight: .infinity)
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
        }
        .frame(width: 780, height: 480)
        .preferredColorScheme(.dark)
        #endif
    }
    
    private func generatePromptWithAI() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        
        isGenerating = true
        Task {
            if let result = await viewModel.generatePromptText(for: title) {
                newPromptText = result
            }
            isGenerating = false
        }
    }
    
    private func savePrompt() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptText = newPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !title.isEmpty && !promptText.isEmpty else { return }
        
        if let existing = editingPrompt {
            viewModel.updateSystemPrompt(existing, title: title, promptText: promptText)
        } else {
            viewModel.createSystemPrompt(title: title, promptText: promptText)
        }
        
        newTitle = ""
        newPromptText = ""
        editingPrompt = nil
    }
}

// MARK: - Endpoint Configuration
private enum EndpointConfigTemplate {
    static let stt = "wss://speech_to_text.npro.ai?silence_duration_ms=1000"
    static let llm = "https://text_gen.npro.ai/v1/chat/completions"
    static let tts = "https://text_to_speech.npro.ai/v1/audio/speech"
}

private func endpointHostSummary(from urlString: String, language: AppLanguage) -> String {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if let host = URL(string: trimmed)?.host, !host.isEmpty {
        return host
    }
    if trimmed.count > 40 {
        return String(trimmed.prefix(37)) + "..."
    }
    return trimmed.isEmpty ? L10n.noURLSet(language) : trimmed
}

// MARK: - Endpoint Configuration Modal View
struct EndpointConfigModalView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var selectedConfig: EndpointConfig?
    #if os(iOS)
    @State private var navigationPath = NavigationPath()
    #endif
    
    var body: some View {
        #if os(iOS)
        NavigationStack(path: $navigationPath) {
            EndpointConfigListView(viewModel: viewModel, navigationPath: $navigationPath)
                .navigationDestination(for: EndpointConfig.self) { config in
                    if let current = viewModel.endpointConfigs.first(where: { $0.id == config.id }) {
                        EndpointConfigDetailView(config: current, viewModel: viewModel)
                    } else {
                        ContentUnavailableView(
                            L10n.configurationNotFound(lang),
                            systemImage: "exclamationmark.triangle",
                            description: Text(L10n.configurationDeletedHint(lang))
                        )
                    }
                }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        HStack(spacing: 0) {
            // SIDEBAR
            VStack(alignment: .leading, spacing: 16) {
                // New Config Button
                Button(action: {
                    viewModel.createEndpointConfig(
                        name: L10n.newConfigName(lang),
                        textGenURL: EndpointConfigTemplate.llm,
                        ttsURL: EndpointConfigTemplate.tts,
                        sttURL: EndpointConfigTemplate.stt
                    )
                    // Select the newly created configuration
                    if let last = viewModel.endpointConfigs.last {
                        selectedConfig = last
                    }
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text(L10n.newConfiguration(lang))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Text(L10n.configurations(lang))
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.endpointConfigs) { config in
                            HStack {
                                Button(action: {
                                    selectedConfig = config
                                }) {
                                    Text(config.name)
                                        .font(.body)
                                        .foregroundColor(selectedConfig?.id == config.id ? .white : .gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.plain)
                                .background(selectedConfig?.id == config.id ? Color.blue : Color.clear)
                                .cornerRadius(6)
                                
                                if !config.isActive {
                                    Button(action: {
                                        viewModel.deleteEndpointConfig(id: config.id)
                                        if selectedConfig?.id == config.id {
                                            selectedConfig = viewModel.endpointConfigs.first(where: { $0.id != config.id })
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 4)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Done button at the bottom of the sidebar
                Button(action: {
                    dismiss()
                }) {
                    Text(L10n.done(lang))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(width: 240)
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // DETAIL VIEW
            VStack(spacing: 0) {
                if let config = selectedConfig {
                    ScrollView {
                        EndpointConfigCard(config: config, viewModel: viewModel)
                            .id(config.id) // Resets state when config changes
                            .padding(24)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text(L10n.noConfigurationSelected(lang))
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        }
        .frame(width: 850, height: 600)
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedConfig == nil {
                selectedConfig = viewModel.activeEndpointConfig ?? viewModel.endpointConfigs.first
            }
        }
        .onChange(of: viewModel.endpointConfigs) {
            // Keep selectedConfig pointer in sync if config is deleted or updated
            if let current = selectedConfig {
                if !viewModel.endpointConfigs.contains(where: { $0.id == current.id }) {
                    selectedConfig = viewModel.activeEndpointConfig ?? viewModel.endpointConfigs.first
                }
            } else {
                selectedConfig = viewModel.activeEndpointConfig ?? viewModel.endpointConfigs.first
            }
        }
        #endif
    }
}

#if os(iOS)
// MARK: - iOS Endpoint Config List
struct EndpointConfigListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var navigationPath: NavigationPath
    @Environment(\.dismiss) private var dismiss
    
    private var lang: AppLanguage { viewModel.appLanguage }
    
    var body: some View {
        List {
            ForEach(viewModel.endpointConfigs) { config in
                NavigationLink(value: config) {
                    EndpointConfigRowView(config: config)
                }
                .deleteDisabled(config.isActive)
            }
            .onDelete(perform: deleteConfigs)
        }
        .navigationTitle(L10n.endpoints(lang))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.done(lang)) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: createAndOpenNew) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.newConfiguration(lang))
            }
        }
    }
    
    private func createAndOpenNew() {
        viewModel.createEndpointConfig(
            name: L10n.newConfigName(lang),
            textGenURL: EndpointConfigTemplate.llm,
            ttsURL: EndpointConfigTemplate.tts,
            sttURL: EndpointConfigTemplate.stt
        )
        if let newConfig = viewModel.endpointConfigs.last {
            navigationPath.append(newConfig)
        }
    }
    
    private func deleteConfigs(at offsets: IndexSet) {
        for index in offsets {
            let config = viewModel.endpointConfigs[index]
            guard !config.isActive else { continue }
            viewModel.deleteEndpointConfig(id: config.id)
        }
    }
}

struct EndpointConfigRowView: View {
    let config: EndpointConfig
    
    @Environment(\.appLanguage) private var lang
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.name)
                    .font(.body)
                Text(endpointHostSummary(from: config.textGenURL, language: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 8)
            
            if config.isActive {
                Text(L10n.active(lang))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - iOS Endpoint Config Detail
struct EndpointConfigDetailView: View {
    let config: EndpointConfig
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var name: String = ""
    @State private var textGenURL: String = ""
    @State private var ttsURL: String = ""
    @State private var sttURL: String = ""
    
    @State private var textGenResult: String = ""
    @State private var isTestingTextGen = false
    
    @State private var ttsInputText = "Hello, this is a test of the text to speech endpoint."
    @State private var isPlayingTTS = false
    
    @State private var isTextGenExpanded = true
    @State private var isTTSExpanded = false
    @State private var isSTTExpanded = false
    
    private var currentConfig: EndpointConfig {
        viewModel.endpointConfigs.first(where: { $0.id == config.id }) ?? config
    }
    
    private var isDictating: Bool {
        viewModel.activeTestSTTConfigId == config.id
    }
    
    var body: some View {
        Form {
            Section {
                TextField(L10n.configurationName(lang), text: $name)
                
                Toggle(L10n.useThisConfiguration(lang), isOn: Binding(
                    get: { currentConfig.isActive },
                    set: { newValue in
                        if newValue {
                            viewModel.selectEndpointConfig(currentConfig)
                        }
                    }
                ))
            }
            
            Section {
                DisclosureGroup(L10n.textGeneration(lang), isExpanded: $isTextGenExpanded) {
                    TextField(L10n.textGenerationURL(lang), text: $textGenURL, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: runTextGenTest) {
                        HStack {
                            Spacer()
                            if isTestingTextGen {
                                ProgressView()
                            }
                            Text(isTestingTextGen ? L10n.testing(lang) : L10n.testConnection(lang))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isTestingTextGen || textGenURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Text(textGenResult.isEmpty ? L10n.textGenSamplePlaceholder(lang) : textGenResult)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(textGenResult.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            Section {
                DisclosureGroup(L10n.tts(lang), isExpanded: $isTTSExpanded) {
                    TextField(L10n.ttsURL(lang), text: $ttsURL, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    if viewModel.voiceOptions.isEmpty {
                        Text(L10n.noVoicesLoaded(lang))
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    } else {
                        Picker(L10n.voice(lang), selection: $viewModel.ttsVoice) {
                            ForEach(viewModel.voiceOptions, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.speed(lang))
                            Spacer()
                            Text(String(format: "%.2fx", viewModel.ttsSpeed))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.ttsSpeed, in: 0.5...2.0, step: 0.05)
                    }
                    
                    TextField(L10n.synthesizePlaceholder(lang), text: $ttsInputText, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: playTTSTest) {
                        HStack {
                            Spacer()
                            if isPlayingTTS {
                                ProgressView()
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isPlayingTTS ? L10n.playing(lang) : L10n.playTestAudio(lang))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isPlayingTTS || ttsInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            Section {
                DisclosureGroup(L10n.stt(lang), isExpanded: $isSTTExpanded) {
                    TextField(L10n.sttURL(lang), text: $sttURL, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: toggleDictation) {
                        HStack {
                            Spacer()
                            Text(isDictating ? L10n.stopDictation(lang) : L10n.startDictation(lang))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .tint(isDictating ? .red : .blue)
                    
                    Text(dictationDisplayText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(isDictating && !viewModel.testSTTText.isEmpty ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .navigationTitle(name.isEmpty ? L10n.configuration(lang) : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.save(lang)) {
                    saveConfig()
                }
            }
            if !currentConfig.isActive {
                ToolbarItem(placement: .destructiveAction) {
                    Button(L10n.delete(lang), role: .destructive) {
                        deleteConfig()
                    }
                }
            }
        }
        .onAppear {
            syncFieldsFromConfig()
        }
        .onChange(of: config) {
            syncFieldsFromConfig()
        }
    }
    
    private var dictationDisplayText: String {
        if isDictating {
            return viewModel.testSTTText.isEmpty ? L10n.listeningSpeakNow(lang) : viewModel.testSTTText
        }
        return L10n.dictationPlaceholder(lang)
    }
    
    private func syncFieldsFromConfig() {
        let source = currentConfig
        name = source.name
        textGenURL = source.textGenURL
        ttsURL = source.ttsURL
        sttURL = source.sttURL
    }
    
    private func saveConfig() {
        viewModel.updateEndpointConfig(
            id: config.id,
            name: name,
            textGenURL: textGenURL,
            ttsURL: ttsURL,
            sttURL: sttURL
        )
    }
    
    private func deleteConfig() {
        viewModel.deleteEndpointConfig(id: config.id)
        dismiss()
    }
    
    private func runTextGenTest() {
        isTestingTextGen = true
        textGenResult = L10n.connectingAndGenerating(lang)
        Task {
            do {
                let response = try await viewModel.runTextGenTest(url: textGenURL)
                textGenResult = response
            } catch {
                textGenResult = "Error: \(error.localizedDescription)"
            }
            isTestingTextGen = false
        }
    }
    
    private func playTTSTest() {
        guard !ttsInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPlayingTTS = true
        Task {
            do {
                try await viewModel.runTTSTest(url: ttsURL, text: ttsInputText)
            } catch {
                viewModel.log("TTS test failed: \(error.localizedDescription)", tag: "ERROR")
            }
            isPlayingTTS = false
        }
    }
    
    private func toggleDictation() {
        if isDictating {
            viewModel.stopSTTTest()
        } else {
            viewModel.startSTTTest(configId: config.id, url: sttURL)
        }
    }
}
#endif

// MARK: - Endpoint Config Card View
struct EndpointConfigCard: View {
    let config: EndpointConfig
    @ObservedObject var viewModel: ChatViewModel
    
    private var lang: AppLanguage { viewModel.appLanguage }
    @State private var name: String = ""
    @State private var textGenURL: String = ""
    @State private var ttsURL: String = ""
    @State private var sttURL: String = ""
    
    @State private var textGenResult: String = ""
    @State private var isTestingTextGen: Bool = false
    
    @State private var ttsInputText: String = "Hello, this is a test of the text to speech endpoint."
    @State private var isPlayingTTS: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Name, Active Toggle, Delete Button
            HStack {
                HStack(spacing: 6) {
                    Text(L10n.configNameLabel(lang))
                        .font(.headline)
                        .foregroundColor(.secondary)
                    TextField(L10n.configurationName(lang), text: $name)
                        .font(.headline)
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Toggle ACTIVE
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { config.isActive },
                        set: { newValue in
                            if newValue {
                                viewModel.selectEndpointConfig(config)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    
                    Text(config.isActive ? L10n.active(lang) : L10n.inactive(lang))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .monospaced()
                        .foregroundColor(config.isActive ? .blue : .gray)
                }
            }
            
            // Text Gen Field
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.textGeneration(lang))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    TextField(L10n.textGenerationURL(lang), text: $textGenURL)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: {
                        runTextGenTest()
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue)
                            
                            if isTestingTextGen {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                            } else {
                                Text(L10n.test(lang))
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 60, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingTextGen)
                }
                
                // Text Gen Response Box
                Text(textGenResult.isEmpty ? L10n.textGenSamplePlaceholder(lang) : textGenResult)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(textGenResult.isEmpty ? .gray : .white)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
            }
            
            // TTS Field
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tts(lang))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                TextField(L10n.ttsURL(lang), text: $ttsURL)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .font(.system(.body, design: .monospaced))
                
                // TTS Voice Selection Dropdown Inline
                HStack {
                    Text(L10n.ttsVoice(lang))
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    if viewModel.voiceOptions.isEmpty {
                        Text(L10n.noVoicesLoaded(lang))
                            .font(.caption)
                            .foregroundColor(.yellow)
                    } else {
                        Picker("", selection: $viewModel.ttsVoice) {
                            ForEach(viewModel.voiceOptions, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                .padding(.vertical, 2)
                
                // TTS Speed Slider
                HStack {
                    Text(L10n.ttsSpeed(lang))
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2fx", viewModel.ttsSpeed))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(width: 48, alignment: .trailing)
                    Slider(value: $viewModel.ttsSpeed, in: 0.5...2.0, step: 0.05)
                        .frame(width: 150)
                }
                .padding(.vertical, 2)
                
                // Enter Text for Speech Section
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.enterTextForSpeech(lang))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    HStack(spacing: 8) {
                        TextField(L10n.synthesizePlaceholder(lang), text: $ttsInputText)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .font(.system(.body, design: .monospaced))
                        
                        Button(action: {
                            playTTSTest()
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue)
                                    .frame(width: 36, height: 32)
                                
                                if isPlayingTTS {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isPlayingTTS || ttsInputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            
            // STT Field
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.stt(lang))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    TextField(L10n.sttURL(lang), text: $sttURL)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .font(.system(.body, design: .monospaced))
                    
                    let isDictating = viewModel.activeTestSTTConfigId == config.id
                    Button(action: {
                        if isDictating {
                            viewModel.stopSTTTest()
                        } else {
                            viewModel.startSTTTest(configId: config.id, url: sttURL)
                        }
                    }) {
                        Text(isDictating ? L10n.stopDictation(lang) : L10n.startDictation(lang))
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isDictating ? Color.red : Color.blue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                // Dictation Text Output Box
                let isDictating = viewModel.activeTestSTTConfigId == config.id
                let dictationDisplayText = isDictating ? (viewModel.testSTTText.isEmpty ? L10n.listeningSpeakNow(lang) : viewModel.testSTTText) : L10n.dictationPlaceholder(lang)
                Text(dictationDisplayText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isDictating && !viewModel.testSTTText.isEmpty ? .white : .gray)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
            }
            
            // Save Button
            HStack {
                Spacer()
                Button(action: {
                    viewModel.updateEndpointConfig(
                        id: config.id,
                        name: name,
                        textGenURL: textGenURL,
                        ttsURL: ttsURL,
                        sttURL: sttURL
                    )
                }) {
                    Text(L10n.save(lang))
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            self.name = config.name
            self.textGenURL = config.textGenURL
            self.ttsURL = config.ttsURL
            self.sttURL = config.sttURL
        }
        .onChange(of: config) {
            self.name = config.name
            self.textGenURL = config.textGenURL
            self.ttsURL = config.ttsURL
            self.sttURL = config.sttURL
        }
    }
    
    private func runTextGenTest() {
        isTestingTextGen = true
        textGenResult = L10n.connectingAndGenerating(lang)
        Task {
            do {
                let response = try await viewModel.runTextGenTest(url: textGenURL)
                textGenResult = response
            } catch {
                textGenResult = "Error: \(error.localizedDescription)"
            }
            isTestingTextGen = false
        }
    }
    
    private func playTTSTest() {
        guard !ttsInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isPlayingTTS = true
        Task {
            do {
                try await viewModel.runTTSTest(url: ttsURL, text: ttsInputText)
            } catch {
                viewModel.log("TTS test failed: \(error.localizedDescription)", tag: "ERROR")
            }
            isPlayingTTS = false
        }
    }
}
