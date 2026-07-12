import SwiftUI
#if canImport(Translation)
import Translation
#endif

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

                    if isUser, let raw = message.rawContent,
                       !raw.isEmpty,
                       raw != message.content {
                        Text("\(L10n.heardAs(lang)): \(raw)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    if isUser, let tip = message.tutorFeedback, !tip.isEmpty {
                        Text("\(L10n.pronunciationTip(lang)): \(tip)")
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.orange)
                            .textSelection(.enabled)

                        if isPhonicsEnabled,
                           tip.containsChineseCharacters,
                           let pinyin = tip.toPinyin(),
                           pinyin != tip {
                            Text(pinyin)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.85))
                                .italic()
                                .textSelection(.enabled)
                        }
                    }

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

