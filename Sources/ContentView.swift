import SwiftUI
import Translation

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var textInput = ""
    @State private var isShowingSettings = false
    @State private var isShowingPromptModal = false
    @State private var isShowingEndpointModal = false
    @State private var isLogsExpanded = true
    @State private var logsHeight: CGFloat = 160
    
    @State private var isPromptHovered = false
    @State private var isEndpointsHovered = false
    
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
                if let activeConv = viewModel.activeConversation {
                    // Chat Window Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activeConv.title)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Conversation ID: \(activeConv.id)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
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
                                        .fill(isPromptHovered ? Color.gray.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.gray.opacity(isPromptHovered ? 0.5 : 0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isPromptHovered = $0 }
                            .help("Select System Prompt")
                            .sheet(isPresented: $isShowingPromptModal) {
                                SystemPromptModalView(viewModel: viewModel)
                            }
                            
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
                                        .fill(isEndpointsHovered ? Color.gray.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.gray.opacity(isEndpointsHovered ? 0.5 : 0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isEndpointsHovered = $0 }
                            .help("Manage Endpoint Configurations")
                            .sheet(isPresented: $isShowingEndpointModal) {
                                EndpointConfigModalView(viewModel: viewModel)
                            }
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
                        
                        // Settings Gear
                        Button(action: {
                            isShowingSettings.toggle()
                        }) {
                            Image(systemName: "gearshape")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .help("Settings")
                        .sheet(isPresented: $isShowingSettings) {
                            SettingsView(viewModel: viewModel)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))
                    
                    Divider()
                    
                    // Messages Viewport
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(viewModel.messages) { message in
                                    MessageRow(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                        .onChange(of: viewModel.messages) {
                            if let lastMessage = viewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
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
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))
                    
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
                
                // Verbose Console Logs Panel
                Divider()
                LogConsolePanel(
                    viewModel: viewModel,
                    isExpanded: $isLogsExpanded,
                    height: $logsHeight
                )
            }
        }
        .frame(minWidth: 800, minHeight: 600)
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
    
    @State private var englishTranslation: String = ""
    
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
                    
                    if message.content.containsChineseCharacters, let pinyin = message.content.toPinyin() {
                        Divider()
                            .padding(.top, 2)
                        Text(pinyin)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                            .italic()
                        
                        if !englishTranslation.isEmpty {
                            Divider()
                                .padding(.top, 2)
                            Text(englishTranslation)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isUser ? Color.blue.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
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
        .translationTask(
            source: Locale.Language(identifier: "zh-Hans"),
            target: Locale.Language(identifier: "en")
        ) { session in
            do {
                if message.content.containsChineseCharacters {
                    let response = try await session.translate(message.content)
                    await MainActor.run {
                        self.englishTranslation = response.targetText
                    }
                }
            } catch {
                print("Translation failed: \(error)")
            }
        }
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let title: String
    let isActive: Bool
    let activeColor: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? activeColor : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? activeColor.opacity(0.6) : .clear, radius: 2)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
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
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(logText, forType: .string)
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
            .background(Color(nsColor: .windowBackgroundColor))
            
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

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    let voiceOptions = [
        "af_aoede", "af_bella", "af_heart", "af_jessica", "af_kore", "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
    "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam", "am_michael", "am_onyx", "am_puck", "am_santa",
    "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
    "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    "ef_dora", "em_alex", "em_santa",
    "ff_siwis",
    "hf_alpha", "hf_beta", "hm_omega", "hm_psi",
    "if_sara", "im_nicola",
    "jf_alpha", "jf_gongitsune", "jf_nezumi", "jf_tebukuro", "jm_kumo",
    "pf_dora", "pm_alex", "pm_santa",
    "zf_xiaobei", "zf_xiaoni", "zf_xiaoxiao", "zf_xiaoyi",
    "zm_yunjian", "zm_yunxi", "zm_yunxia", "zm_yunyang"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Developer Configuration")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            Form {
                
                Section(header: Text("Text to Speech (TTS) Settings").fontWeight(.bold)) {
                    TextField("TTS Model Name", text: $viewModel.ttsModel)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("TTS Voice", selection: $viewModel.ttsVoice) {
                        ForEach(voiceOptions, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    HStack {
                        Text("Playback Speed (\(String(format: "%.1f", viewModel.ttsSpeed))x)")
                            .font(.body)
                        Slider(value: $viewModel.ttsSpeed, in: 0.5...2.0, step: 0.1)
                    }
                }
            }
            .padding()
            .formStyle(.grouped)
            .frame(width: 500, height: 265)
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
    
    var body: some View {
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
                Text(editingPrompt == nil ? "Create New Prompt" : "Edit Prompt")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
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

// MARK: - Endpoint Configuration Modal View
struct EndpointConfigModalView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Endpoint Configuration Manager")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // New Config Button
                NewConfigButton {
                    viewModel.createEndpointConfig(
                        name: "New Config",
                        textGenURL: "https://text_gen.npro.ai/v1/chat/completions",
                        ttsURL: "https://text_to_speech.npro.ai/v1/audio/speech",
                        sttURL: "wss://speech_to_text.npro.ai?silence_duration_ms=1000"
                    )
                }
                .help("Add new endpoint configuration")
                
                // Done Button
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(24)
            .background(Color(red: 0.08, green: 0.08, blue: 0.09))
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Cards Scroll View
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(viewModel.endpointConfigs) { config in
                        EndpointConfigCard(config: config, viewModel: viewModel)
                    }
                }
                .padding(24)
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.09))
        }
        .frame(width: 800, height: 550)
        .preferredColorScheme(.dark)
    }
}

struct NewConfigButton: View {
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("New Configuration")
            }
            .font(.body)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color(red: 0.55, green: 0.3, blue: 0.65) : Color(red: 0.45, green: 0.25, blue: 0.55))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Endpoint Config Card View
struct EndpointConfigCard: View {
    let config: EndpointConfig
    @ObservedObject var viewModel: ChatViewModel
    
    @State private var name: String = ""
    @State private var textGenURL: String = ""
    @State private var ttsURL: String = ""
    @State private var sttURL: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                
                // Delete button
                if !config.isActive {
                    Button(action: {
                        viewModel.deleteEndpointConfig(id: config.id)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete configuration")
                    .padding(.leading, 8)
                } else {
                    Image(systemName: "trash")
                        .foregroundColor(.gray.opacity(0.3))
                        .padding(.leading, 8)
                        .help("Cannot delete active configuration")
                }
            }
            
            // Text Gen Field
            VStack(alignment: .leading, spacing: 4) {
                Text("TEXT GENERATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
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
            }
            
            // TTS Field
            VStack(alignment: .leading, spacing: 4) {
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
            }
            
            // STT Field
            VStack(alignment: .leading, spacing: 4) {
                Text("STT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
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
        .padding(16)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(config.isActive ? Color.blue : Color.gray.opacity(0.2), lineWidth: config.isActive ? 2 : 1)
        )
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
}
