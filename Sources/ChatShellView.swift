import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Chat feature detail shell: conversation chrome, messages, input, and macOS log console.
/// Sheets for prompts/endpoints stay hosted on `ContentView` (root).
struct ChatShellView: View {
    @ObservedObject var nav: AppNavigationModel
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var flashcardVM: FlashcardViewModel
    @Binding var isShowingPromptModal: Bool
    @Binding var isShowingEndpointModal: Bool
    @Binding var isLogsExpanded: Bool
    @Binding var logsHeight: CGFloat
    /// Compact iOS: reveal the split-view sidebar column.
    var onPreferSidebar: () -> Void = {}

    @Environment(\.appLanguage) private var lang
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var textInput = ""
    @State private var isPromptHovered = false
    @State private var isEndpointsHovered = false
    @State private var isTranslationHovered = false
    @State private var isPhonicsHovered = false

    var body: some View {
        VStack(spacing: 0) {
            chatMain
            #if os(macOS)
            #if canImport(Translation)
            if #available(macOS 15.0, *) {
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
        .toolbar {
            #if os(iOS)
            // In-detail conversation switcher (C2): reachable while a thread is active.
            ToolbarItem(placement: .navigationBarTrailing) {
                conversationSwitcherMenu
            }
            if viewModel.activeConversation != nil {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        StatusIndicator(title: "STT", isActive: viewModel.isWebSocketConnected, activeColor: .green, showTitle: false)
                        StatusIndicator(title: "LLM", isActive: viewModel.isGeneratingText, activeColor: .yellow, showTitle: false)
                        StatusIndicator(title: "TTS", isActive: viewModel.isGeneratingSpeech, activeColor: .blue, showTitle: false)
                        StatusIndicator(title: "AUDIO", isActive: viewModel.isPlayingAudio, activeColor: .orange, showTitle: false)
                    }
                }
                // Regular width: tools live here. Compact: tools ride in compactFeatureChrome
                // extraTrailing after the Apps Menu so order is Apps → tools.
                if horizontalSizeClass != .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        ChatToolsMenuButton(
                            viewModel: viewModel,
                            isShowingPromptModal: $isShowingPromptModal,
                            isShowingEndpointModal: $isShowingEndpointModal
                        )
                    }
                }
            }
            #endif
        }
        // Empty + active both get Apps Menu on compact (K5a). Tools only when active.
        .compactFeatureChrome(
            nav: nav,
            lang: lang,
            dueCount: flashcardVM.dueCount,
            onPreferSidebar: onPreferSidebar
        ) {
            #if os(iOS)
            if viewModel.activeConversation != nil {
                ChatToolsMenuButton(
                    viewModel: viewModel,
                    isShowingPromptModal: $isShowingPromptModal,
                    isShowingEndpointModal: $isShowingEndpointModal
                )
            }
            #else
            EmptyView()
            #endif
        }
    }

    @ViewBuilder
    private var chatMain: some View {
        if viewModel.activeConversation != nil {
            activeConversationView
        } else {
            emptyState
        }
    }

    private var activeConversationView: some View {
        VStack(spacing: 0) {
            #if !os(iOS)
            chatHeader
            #endif

            Divider()

            messagesViewport

            Divider()

            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if !os(iOS)
    private var chatHeader: some View {
        HStack {
            HStack(spacing: 12) {
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

                Button(action: {
                    viewModel.isTranslationEnabled.toggle()
                }) {
                    HStack(spacing: 6) {
                        Text("🌐")
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

                Button(action: {
                    viewModel.isPhonicsEnabled.toggle()
                }) {
                    HStack(spacing: 6) {
                        Text("🗣️")
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

                Picker("", selection: $viewModel.speechPipelineMode) {
                    Text(L10n.speechPipelineDirect(lang)).tag(SpeechPipelineMode.directSTT)
                    Text(L10n.speechPipelineSTTPlusLLM(lang)).tag(SpeechPipelineMode.sttPlusLLM)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .help(L10n.speechPipelineModeHelp(lang))

                Picker("", selection: $viewModel.sttLanguage) {
                    ForEach(STTLanguage.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .help(L10n.sttLanguageHelp(lang))
            }

            Spacer()

            HStack(spacing: 12) {
                StatusIndicator(
                    title: viewModel.speechPipelineMode == .sttPlusLLM ? "STT+LLM" : "STT",
                    isActive: viewModel.isWebSocketConnected,
                    activeColor: .green
                )
                StatusIndicator(
                    title: viewModel.isCorrectingSpeech ? "FIX" : "LLM",
                    isActive: viewModel.isGeneratingText || viewModel.isCorrectingSpeech,
                    activeColor: .yellow
                )
                StatusIndicator(title: "TTS", isActive: viewModel.isGeneratingSpeech, activeColor: .blue)
                StatusIndicator(title: "AUDIO", isActive: viewModel.isPlayingAudio, activeColor: .orange)
            }
            .padding(.trailing, 10)
        }
        .padding()
        .background(Color.platformWindowBackground)
    }
    #endif

    private var messagesViewport: some View {
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
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
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

            TextField(L10n.messagePlaceholder(lang), text: $textInput, onCommit: {
                sendText()
            })
            .textFieldStyle(.roundedBorder)
            .font(.body)
            .controlSize(.large)

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
        .padding(.vertical, 8)
        #else
        .padding()
        #endif
        .background(Color.platformWindowBackground)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text(L10n.noConversationSelected(lang))
                    .font(.title2)
                    .fontWeight(.medium)
                Text(L10n.emptyStateHint(lang))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(L10n.startNewChat(lang)) {
                    viewModel.startNewConversation()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                #if os(iOS)
                // iOS empty/select flow: list when a true empty active state coexists with rows.
                if !viewModel.conversations.isEmpty {
                    recentConversationsList
                        .padding(.top, 8)
                }
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding()
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if os(iOS)
    /// Recent conversations capped for menus / empty-state list (full list remains in sidebar).
    private var recentConversations: [Conversation] {
        Array(viewModel.conversations.prefix(8))
    }

    /// Toolbar control: switch threads or start new without opening the sidebar.
    private var conversationSwitcherMenu: some View {
        Menu {
            Button {
                viewModel.startNewConversation()
            } label: {
                Label(L10n.startNewChat(lang), systemImage: "plus.bubble")
            }

            if !recentConversations.isEmpty {
                Divider()
                ForEach(recentConversations) { conversation in
                    Button {
                        viewModel.selectConversation(conversation)
                    } label: {
                        if viewModel.activeConversation?.id == conversation.id {
                            Label(conversation.title, systemImage: "checkmark")
                        } else {
                            Text(conversation.title)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .padding(6)
                .background(Circle().fill(Color.gray.opacity(0.12)))
                .overlay(Circle().stroke(Color.gray.opacity(0.25), lineWidth: 1))
        }
        .accessibilityLabel(L10n.conversations(lang))
        .accessibilityHint(L10n.emptyStateHint(lang))
    }

    /// Short recent list for empty/select flow when no conversation is active.
    private var recentConversationsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.conversations(lang))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(recentConversations.enumerated()), id: \.element.id) { index, conversation in
                    Button {
                        viewModel.selectConversation(conversation)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "message")
                                .foregroundStyle(.secondary)
                            Text(conversation.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < recentConversations.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.platformWindowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .frame(maxWidth: 420)
    }
    #endif

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
