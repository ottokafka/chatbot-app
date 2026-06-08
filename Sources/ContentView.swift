import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var textInput = ""
    @State private var isShowingSettings = false
    @State private var isLogsExpanded = true
    @State private var logsHeight: CGFloat = 160
    
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
                Text(message.content)
                    .font(.system(.body, design: .monospaced))
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
        "af_heart", "af_bella", "af_nicole", "af_sarah", "am_adam", "am_michael", "bf_emma", "bf_isabella", "bm_george", "bm_lewis"
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
                Section(header: Text("Speech to Text (STT) Settings").fontWeight(.bold)) {
                    TextField("STT WebSocket URL", text: $viewModel.sttURL)
                        .textFieldStyle(.roundedBorder)
                        .help("WebSocket endpoint for streaming audio data.")
                }
                .padding(.bottom, 8)
                
                Section(header: Text("Text Generation (LLM) Settings").fontWeight(.bold)) {
                    TextField("LLM HTTP URL", text: $viewModel.llmURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("LLM Model Name", text: $viewModel.llmModel)
                        .textFieldStyle(.roundedBorder)
                    TextField("System Prompt", text: $viewModel.systemPrompt)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.bottom, 8)
                
                Section(header: Text("Text to Speech (TTS) Settings").fontWeight(.bold)) {
                    TextField("TTS HTTP URL", text: $viewModel.ttsURL)
                        .textFieldStyle(.roundedBorder)
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
            .frame(width: 500, height: 420)
        }
    }
}
