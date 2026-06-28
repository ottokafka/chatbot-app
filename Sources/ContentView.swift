import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var textInput = ""
    @State private var isShowingPromptModal = false
    @State private var isShowingEndpointModal = false
    @State private var isLogsExpanded = true
    @State private var logsHeight: CGFloat = 160
    
    @State private var isPromptHovered = false
    @State private var isEndpointsHovered = false
    @State private var isTranslationHovered = false
    @State private var isPhonicsHovered = false
    
    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            VStack(alignment: .leading, spacing: 12) {
                // New Chat Button
                Button(action: {
                    viewModel.startNewConversation()
                }) {
                    HStack {
                        Image(systemName: "plus.bubble")
                        Text("New Chat")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                
                // Conversations List
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
                            // Delete Button
                            Button(action: {
                                viewModel.deleteConversation(conversation)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .help("Delete conversation")
                        }
                    }
                    .tag(conversation)
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Conversations")
            .frame(minWidth: 200, idealWidth: 240)
        } detail: {
            // MAIN DETAIL VIEW
            VStack(spacing: 0) {
                if viewModel.activeConversation != nil {
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
                                    Text(viewModel.activeSystemPrompt?.title ?? "No Prompt")
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
                            .help("Select System Prompt")
                            
                            // Endpoints Button
                            Button(action: {
                                isShowingEndpointModal.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Text("🔌")
                                    Text("Endpoints")
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
                            .help("Manage Endpoint Configurations")
                            
                            // Translation Toggle Button
                            Button(action: {
                                viewModel.isTranslationEnabled.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Text(viewModel.isTranslationEnabled ? "🌐" : "🌐 (Off)")
                                    Text("Translation")
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
                            .help("Toggle translation feature")
                            
                            // Phonics Toggle Button
                            Button(action: {
                                viewModel.isPhonicsEnabled.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Text(viewModel.isPhonicsEnabled ? "🗣️" : "🗣️ (Off)")
                                    Text("Phonics")
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
                            .help("Toggle Pinyin phonics")
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
                                        isTranslationEnabled: viewModel.isTranslationEnabled,
                                        isPhonicsEnabled: viewModel.isPhonicsEnabled
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
                        TextField("Type a message to assistant...", text: $textInput, onCommit: {
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
                        Text("No Conversation Selected")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Create a new chat or select an existing conversation to get started.")
                            .foregroundColor(.secondary)
                        
                        Button("Start New Chat") {
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
            }
            .sheet(isPresented: $isShowingEndpointModal) {
                EndpointConfigModalView(viewModel: viewModel)
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
    let isTranslationEnabled: Bool
    let isPhonicsEnabled: Bool
    
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
                    Text(isUser ? "DEVELOPER" : "ASSISTANT")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(isUser ? .blue : .green)
                    
                    Text(message.createdAt, style: .time)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                // Content Bubble
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.content)
                        .font(.system(.body, design: .monospaced))
                    
                    if message.content.isChinese() {
                        // Source is Chinese
                        if isPhonicsEnabled, let pinyin = message.content.toPinyin() {
                            Divider()
                                .padding(.top, 2)
                            Text(pinyin)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        
                        if isTranslationEnabled && !translatedText.isEmpty {
                            Divider()
                                .padding(.top, 2)
                            Text(translatedText)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        // Source is English/Other
                        if isTranslationEnabled && !translatedText.isEmpty {
                            Divider()
                                .padding(.top, 2)
                            Text(translatedText)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            if isPhonicsEnabled, let pinyin = translatedText.toPinyin() {
                                Divider()
                                    .padding(.top, 2)
                                Text(pinyin)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .italic()
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
                    .textSelection(.enabled)
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
        .help(isActive ? "Stop listening" : "Start listening")
    }
}

// MARK: - Stop Playback Button View
struct StopPlaybackButton: View {
    let isPlaying: Bool
    let action: () -> Void
    
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
        .help(isPlaying ? "Stop audio playback" : "No audio playing")
    }
}

// MARK: - Console Log Panel View
struct LogConsolePanel: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isExpanded: Bool
    @Binding var height: CGFloat
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .font(.body)
                    Text("System Console Logs")
                        .font(.headline)
                        .fontDesign(.monospaced)
                }
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Copy Logs") {
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
                    
                    Button("Clear") {
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
                Text("Select").tag(0)
                Text("Create / Edit").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if iOSActiveTab == 0 {
                // Select System Prompt List
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select System Prompt")
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
                        TextField("Title (e.g. Grammar Expert)", text: $newTitle)
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
                            Text("Cancel")
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
                            Text(editingPrompt == nil ? "Save Prompt" : "Update Prompt")
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
                Text("Select System Prompt")
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
                                    .help("Edit system prompt")
                                    
                                    // Delete button
                                    Button(action: {
                                        viewModel.deleteSystemPrompt(prompt)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete system prompt")
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
                TextField("Title (e.g. Grammar Expert)", text: $newTitle)
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
                            Text("Generating...")
                        } else {
                            Text("✨ Generate Prompt with AI")
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
                    Text(editingPrompt == nil ? "Save Prompt" : "Update Prompt")
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
                    Text("Cancel")
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
    static let newName = "New Config"
    static let stt = "wss://speech_to_text.npro.ai?silence_duration_ms=1000"
    static let llm = "https://text_gen.npro.ai/v1/chat/completions"
    static let tts = "https://text_to_speech.npro.ai/v1/audio/speech"
}

private func endpointHostSummary(from urlString: String) -> String {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if let host = URL(string: trimmed)?.host, !host.isEmpty {
        return host
    }
    if trimmed.count > 40 {
        return String(trimmed.prefix(37)) + "..."
    }
    return trimmed.isEmpty ? "No URL set" : trimmed
}

// MARK: - Endpoint Configuration Modal View
struct EndpointConfigModalView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
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
                            "Configuration Not Found",
                            systemImage: "exclamationmark.triangle",
                            description: Text("This configuration may have been deleted.")
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
                        name: EndpointConfigTemplate.newName,
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
                        Text("New Configuration")
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
                
                Text("Configurations")
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
                    Text("Done")
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
                        Text("No Configuration Selected")
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
        .navigationTitle("Endpoints")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: createAndOpenNew) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Configuration")
            }
        }
    }
    
    private func createAndOpenNew() {
        viewModel.createEndpointConfig(
            name: EndpointConfigTemplate.newName,
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
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.name)
                    .font(.body)
                Text(endpointHostSummary(from: config.textGenURL))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 8)
            
            if config.isActive {
                Text("Active")
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
                TextField("Configuration Name", text: $name)
                
                Toggle("Use this configuration", isOn: Binding(
                    get: { currentConfig.isActive },
                    set: { newValue in
                        if newValue {
                            viewModel.selectEndpointConfig(currentConfig)
                        }
                    }
                ))
            }
            
            Section {
                DisclosureGroup("Text Generation", isExpanded: $isTextGenExpanded) {
                    TextField("Text Generation URL", text: $textGenURL, axis: .vertical)
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
                            Text(isTestingTextGen ? "Testing..." : "Test Connection")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isTestingTextGen || textGenURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Text(textGenResult.isEmpty ? "Sample text generated by the model will appear here." : textGenResult)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(textGenResult.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            Section {
                DisclosureGroup("Text-to-Speech", isExpanded: $isTTSExpanded) {
                    TextField("TTS URL", text: $ttsURL, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    if viewModel.voiceOptions.isEmpty {
                        Text("No voices loaded (check TTS server)")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    } else {
                        Picker("Voice", selection: $viewModel.ttsVoice) {
                            ForEach(viewModel.voiceOptions, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.2fx", viewModel.ttsSpeed))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $viewModel.ttsSpeed, in: 0.5...2.0, step: 0.05)
                    }
                    
                    TextField("Type text to synthesize...", text: $ttsInputText, axis: .vertical)
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
                            Text(isPlayingTTS ? "Playing..." : "Play Test Audio")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isPlayingTTS || ttsInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            Section {
                DisclosureGroup("Speech-to-Text", isExpanded: $isSTTExpanded) {
                    TextField("STT URL", text: $sttURL, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    Button(action: toggleDictation) {
                        HStack {
                            Spacer()
                            Text(isDictating ? "Stop Dictation" : "Start Dictation")
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
        .navigationTitle(name.isEmpty ? "Configuration" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveConfig()
                }
            }
            if !currentConfig.isActive {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
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
            return viewModel.testSTTText.isEmpty ? "Listening... Speak now." : viewModel.testSTTText
        }
        return "Live dictation text appears here as you speak."
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
        textGenResult = "Connecting and generating..."
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
                    Text("Config Name:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    TextField("Configuration Name", text: $name)
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
                    
                    Text(config.isActive ? "ACTIVE" : "INACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .monospaced()
                        .foregroundColor(config.isActive ? .blue : .gray)
                }
            }
            
            // Text Gen Field
            VStack(alignment: .leading, spacing: 6) {
                Text("TEXT GENERATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    TextField("Text Generation URL", text: $textGenURL)
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
                                Text("Test")
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
                Text(textGenResult.isEmpty ? "Sample text generated by the model will appear here." : textGenResult)
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
                Text("TTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                TextField("TTS URL", text: $ttsURL)
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
                    Text("TTS Voice")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    if viewModel.voiceOptions.isEmpty {
                        Text("No voices loaded (check TTS server)")
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
                    Text("TTS Speed")
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
                    Text("Enter Text for Speech")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    HStack(spacing: 8) {
                        TextField("Type text to synthesize...", text: $ttsInputText)
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
                Text("STT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    TextField("STT URL", text: $sttURL)
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
                        Text(isDictating ? "Stop Dictation" : "Start Dictation")
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
                let dictationDisplayText = isDictating ? (viewModel.testSTTText.isEmpty ? "Listening... Speak now." : viewModel.testSTTText) : "Live dictation text appears here as you speak."
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
                    Text("Save")
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
        textGenResult = "Connecting and generating..."
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
