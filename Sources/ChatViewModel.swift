import Foundation
import SwiftUI
import Combine

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let tag: String // "STT", "LLM", "TTS", "DB", "AUDIO", "ERROR", "SYSTEM"
    let message: String
}

@MainActor
class ChatViewModel: ObservableObject {
    // Database and APIs
    private let dbManager = DatabaseManager()
    private let apiManager = APIManager()
    private var webSocketManager: WebSocketManager?
    private let audioRecorder = AudioRecorder()
    private let audioPlayer = AudioPlayer()
    
    // Published State
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var logs: [LogEntry] = []
    
    // Status states
    @Published var isMicrophoneActive = false
    @Published var isWebSocketConnected = false
    @Published var isPlayingAudio = false
    @Published var isGeneratingText = false
    @Published var isGeneratingSpeech = false
    
    // Configuration Settings (persisted in UserDefaults)
    @Published var sttURL: String {
        didSet { UserDefaults.standard.set(sttURL, forKey: "sttURL") }
    }
    @Published var llmURL: String {
        didSet { UserDefaults.standard.set(llmURL, forKey: "llmURL") }
    }
    @Published var llmModel: String {
        didSet { UserDefaults.standard.set(llmModel, forKey: "llmModel") }
    }
    @Published var ttsURL: String {
        didSet { UserDefaults.standard.set(ttsURL, forKey: "ttsURL") }
    }
    @Published var ttsModel: String {
        didSet { UserDefaults.standard.set(ttsModel, forKey: "ttsModel") }
    }
    @Published var ttsVoice: String {
        didSet { UserDefaults.standard.set(ttsVoice, forKey: "ttsVoice") }
    }
    @Published var ttsSpeed: Double {
        didSet { UserDefaults.standard.set(ttsSpeed, forKey: "ttsSpeed") }
    }
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }
    
    init() {
        // Load settings from UserDefaults or use defaults from readme
        self.sttURL = UserDefaults.standard.string(forKey: "sttURL") ?? "wss://speech_to_text.npro.ai"
        self.llmURL = UserDefaults.standard.string(forKey: "llmURL") ?? "https://text_gen.npro.ai/v1/chat/completions"
        self.llmModel = UserDefaults.standard.string(forKey: "llmModel") ?? "Qwen3.5-35B-A3B-Q4_K_M.gguf"
        self.ttsURL = UserDefaults.standard.string(forKey: "ttsURL") ?? "https://text_to_speech.npro.ai/v1/audio/speech"
        self.ttsModel = UserDefaults.standard.string(forKey: "ttsModel") ?? "kokoro-v1"
        self.ttsVoice = UserDefaults.standard.string(forKey: "ttsVoice") ?? "zf_001"
        self.ttsSpeed = UserDefaults.standard.double(forKey: "ttsSpeed") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "ttsSpeed")
        self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? "You are a conversational chatbot keep response short concise 1 - 2 sentences."
        
        setupCallbacks()
        loadConversations()
        log("Developer Chatbot Initialized.", tag: "SYSTEM")
    }
    
    // MARK: - Logging Interface
    
    func log(_ message: String, tag: String = "SYSTEM") {
        let entry = LogEntry(timestamp: Date(), tag: tag, message: message)
        DispatchQueue.main.async {
            self.logs.append(entry)
            // Cap logs at 1000 items to prevent memory issues
            if self.logs.count > 1000 {
                self.logs.removeFirst(100)
            }
        }
    }
    
    func clearLogs() {
        logs.removeAll()
        log("Logs cleared.", tag: "SYSTEM")
    }
    
    // MARK: - Setup
    
    private func setupCallbacks() {
        // APIManager log callback
        apiManager.onLog = { [weak self] msg in
            self?.log(msg, tag: "LLM")
        }
        
        // AudioPlayer callbacks
        audioPlayer.onLog = { [weak self] msg in
            self?.log(msg, tag: "AUDIO")
        }
        
        audioPlayer.onPlaybackStarted = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.isPlayingAudio = true
                // Pause mic recording during playback to avoid recording own output
                if self.isMicrophoneActive {
                    self.log("Playback started: Pausing microphone recording.", tag: "AUDIO")
                    self.audioRecorder.stop()
                }
            }
        }
        
        audioPlayer.onPlaybackFinished = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.isPlayingAudio = false
                // Resume mic recording if it's supposed to be active
                if self.isMicrophoneActive {
                    self.log("Playback finished: Resuming microphone recording.", tag: "AUDIO")
                    self.audioRecorder.start()
                }
            }
        }
        
        // AudioRecorder callbacks
        audioRecorder.onLog = { [weak self] msg in
            self?.log(msg, tag: "AUDIO")
        }
        
        audioRecorder.onError = { [weak self] err in
            self?.log("AudioRecorder Error: \(err)", tag: "ERROR")
            Task { @MainActor in
                self?.isMicrophoneActive = false
            }
        }
        
        audioRecorder.onAudioData = { [weak self] data in
            guard let self = self else { return }
            Task { @MainActor in
                self.webSocketManager?.sendAudio(data: data)
            }
        }
    }
    
    // MARK: - Database Actions
    
    func loadConversations() {
        conversations = dbManager.fetchConversations()
        log("Loaded \(conversations.count) conversations from database.", tag: "DB")
        if let first = conversations.first {
            selectConversation(first)
        }
    }
    
    func selectConversation(_ conversation: Conversation) {
        activeConversation = conversation
        messages = dbManager.fetchMessages(conversationId: conversation.id)
        log("Selected conversation '\(conversation.title)' with \(messages.count) messages.", tag: "DB")
    }
    
    func startNewConversation() {
        let title = "New Chat"
        let id = dbManager.createConversation(title: title)
        let newConv = Conversation(id: id, title: title, createdAt: Date())
        conversations.insert(newConv, at: 0)
        selectConversation(newConv)
        log("Created new conversation '\(title)' (\(id)).", tag: "DB")
    }
    
    func deleteConversation(_ conversation: Conversation) {
        dbManager.deleteConversation(id: conversation.id)
        log("Deleted conversation '\(conversation.title)' from DB.", tag: "DB")
        
        if activeConversation?.id == conversation.id {
            activeConversation = nil
            messages = []
        }
        loadConversations()
    }
    
    // MARK: - Mic / WebSocket Actions
    
    func toggleMicrophone() {
        if isMicrophoneActive {
            stopMicrophonePipeline()
        } else {
            startMicrophonePipeline()
        }
    }
    
    private func startMicrophonePipeline() {
        log("Activating microphone and Speech-To-Text WebSocket connection.", tag: "SYSTEM")
        isMicrophoneActive = true
        
        // Re-create WebSocketManager
        webSocketManager = WebSocketManager(urlString: sttURL)
        webSocketManager?.onLog = { [weak self] msg in
            self?.log(msg, tag: "STT")
        }
        webSocketManager?.onError = { [weak self] err in
            self?.log("WebSocket error: \(err)", tag: "ERROR")
        }
        webSocketManager?.onConnectionStateChange = { [weak self] connected in
            guard let self = self else { return }
            Task { @MainActor in
                self.isWebSocketConnected = connected
                if connected {
                    self.log("WebSocket connected. Starting audio recording.", tag: "STT")
                    // If not currently playing audio, start recording
                    if !self.isPlayingAudio {
                        self.audioRecorder.start()
                    } else {
                        self.log("Audio is currently playing. Postponing microphone start.", tag: "AUDIO")
                    }
                } else {
                    self.log("WebSocket disconnected. Stopping audio recording.", tag: "STT")
                    self.audioRecorder.stop()
                }
            }
        }
        webSocketManager?.onMessageReceived = { [weak self] transcription in
            guard let self = self else { return }
            Task { @MainActor in
                self.log("Received Speech-to-Text transcription: \"\(transcription)\"", tag: "STT")
                await self.handleUserMessage(transcription)
            }
        }
        
        webSocketManager?.connect()
    }
    
    private func stopMicrophonePipeline() {
        log("Deactivating microphone and Speech-To-Text WebSocket.", tag: "SYSTEM")
        isMicrophoneActive = false
        isWebSocketConnected = false
        audioRecorder.stop()
        webSocketManager?.disconnect()
        webSocketManager = nil
    }
    
    // MARK: - Chat Logic
    
    /// Sends a manually typed message
    func sendTextMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await handleUserMessage(text)
        }
    }
    
    private func handleUserMessage(_ text: String) async {
        // 1. Ensure we have an active conversation
        if activeConversation == nil {
            startNewConversation()
        }
        
        guard let conv = activeConversation else { return }
        
        // 2. Insert user message in database
        let messageId = UUID().uuidString
        dbManager.insertMessage(id: messageId, conversationId: conv.id, role: "user", content: text)
        log("Saved user message to DB.", tag: "DB")
        
        // 3. Reload messages list
        messages = dbManager.fetchMessages(conversationId: conv.id)
        
        // 4. Update conversation title if it is "New Chat" and this is the first message
        if conv.title == "New Chat" {
            let truncatedTitle = String(text.prefix(30)) + (text.count > 30 ? "..." : "")
            dbManager.updateConversationTitle(id: conv.id, title: truncatedTitle)
            activeConversation?.title = truncatedTitle
            loadConversations()
            // Make sure the active selection stays the same
            if let updated = conversations.first(where: { $0.id == conv.id }) {
                activeConversation = updated
            }
        }
        
        // 5. Trigger LLM Text Generation
        await runTextGeneration()
    }
    
    private func runTextGeneration() async {
        guard let conv = activeConversation else { return }
        
        isGeneratingText = true
        log("Triggering text generation from LLM...", tag: "SYSTEM")
        
        // Prepare openai payload
        var chatPayload: [ChatMessage] = []
        // Add system message if configured
        if !systemPrompt.isEmpty {
            chatPayload.append(ChatMessage(role: "system", content: systemPrompt))
        }
        
        // Add last 10 messages from db history for context
        let history = dbManager.fetchMessages(conversationId: conv.id)
        let lastMessages = history.suffix(10).map { ChatMessage(role: $0.role, content: $0.content) }
        chatPayload.append(contentsOf: lastMessages)
        
        do {
            let assistantText = try await apiManager.generateText(
                endpoint: llmURL,
                model: llmModel,
                messages: chatPayload
            )
            
            // Save LLM response to DB
            let responseId = UUID().uuidString
            dbManager.insertMessage(id: responseId, conversationId: conv.id, role: "assistant", content: assistantText)
            log("Saved assistant message to DB.", tag: "DB")
            
            // Reload message UI
            messages = dbManager.fetchMessages(conversationId: conv.id)
            isGeneratingText = false
            
            // Trigger TTS
            await runSpeechGeneration(for: assistantText)
            
        } catch {
            log("LLM Error: \(error.localizedDescription)", tag: "ERROR")
            isGeneratingText = false
        }
    }
    
    private func runSpeechGeneration(for text: String) async {
        isGeneratingSpeech = true
        log("Triggering speech synthesis for text length \(text.count)...", tag: "SYSTEM")
        
        do {
            let audioData = try await apiManager.generateSpeech(
                endpoint: ttsURL,
                model: ttsModel,
                text: text,
                voice: ttsVoice,
                speed: ttsSpeed
            )
            
            isGeneratingSpeech = false
            
            // Play WAV bytes
            audioPlayer.play(data: audioData)
            
        } catch {
            log("TTS Error: \(error.localizedDescription)", tag: "ERROR")
            isGeneratingSpeech = false
        }
    }
}
