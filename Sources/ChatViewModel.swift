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
    private let audioStorage = AudioStorage()
    private var audioCache: [String: Data] = [:]
    
    // Published State
    @Published var conversations: [Conversation] = []
    @Published var activeConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var logs: [LogEntry] = []
    
    // Status states
    @Published var isMicrophoneActive = false
    @Published var isWebSocketConnected = false
    @Published var isPlayingAudio = false
    @Published var currentlyPlayingMessageId: String?
    @Published var isGeneratingText = false
    @Published var isGeneratingSpeech = false
    
    // Configuration Settings (persisted in UserDefaults)
    @Published var sttURL: String {
        didSet {
            UserDefaults.standard.set(sttURL, forKey: "sttURL")
            updateActiveConfigFromSettings()
        }
    }
    @Published var llmURL: String {
        didSet {
            UserDefaults.standard.set(llmURL, forKey: "llmURL")
            updateActiveConfigFromSettings()
        }
    }
    @Published var llmModel: String {
        didSet { UserDefaults.standard.set(llmModel, forKey: "llmModel") }
    }
    @Published var ttsURL: String {
        didSet {
            UserDefaults.standard.set(ttsURL, forKey: "ttsURL")
            updateActiveConfigFromSettings()
            Task {
                await fetchVoicesFromCurrentEndpoint()
            }
        }
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
    @Published var voiceOptions: [String] = []
    @Published var isTestingVoice = false
    @Published var systemPrompts: [SystemPrompt] = []
    @Published var activeSystemPrompt: SystemPrompt?
    
    @Published var endpointConfigs: [EndpointConfig] = []
    @Published var activeEndpointConfig: EndpointConfig?
    
    @Published var activeTestSTTConfigId: Int64? = nil
    @Published var testSTTText = ""
    private var testWebSocketManager: WebSocketManager?
    private var testAudioRecorder: AudioRecorder?
    
    @Published var isTranslationEnabled: Bool {
        didSet { UserDefaults.standard.set(isTranslationEnabled, forKey: "isTranslationEnabled") }
    }
    @Published var isPhonicsEnabled: Bool {
        didSet { UserDefaults.standard.set(isPhonicsEnabled, forKey: "isPhonicsEnabled") }
    }
    @Published var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage") }
    }
    
    init() {
        // Load settings from UserDefaults or use defaults from readme
        self.sttURL = UserDefaults.standard.string(forKey: "sttURL") ?? "wss://speech_to_text.npro.ai?silence_duration_ms=1000"
        self.llmURL = UserDefaults.standard.string(forKey: "llmURL") ?? "https://text_gen.npro.ai/v1/chat/completions"
        self.llmModel = UserDefaults.standard.string(forKey: "llmModel") ?? "Qwen3.5-35B-A3B-Q4_K_M.gguf"
        self.ttsURL = UserDefaults.standard.string(forKey: "ttsURL") ?? "https://text_to_speech.npro.ai/v1/audio/speech"
        self.ttsModel = UserDefaults.standard.string(forKey: "ttsModel") ?? "kokoro-v1"
        self.ttsVoice = UserDefaults.standard.string(forKey: "ttsVoice") ?? "bm_daniel"
        self.ttsSpeed = UserDefaults.standard.double(forKey: "ttsSpeed") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "ttsSpeed")
        
        self.isTranslationEnabled = UserDefaults.standard.object(forKey: "isTranslationEnabled") as? Bool ?? true
        self.isPhonicsEnabled = UserDefaults.standard.object(forKey: "isPhonicsEnabled") as? Bool ?? true
        if let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage"),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.appLanguage = language
        } else {
            self.appLanguage = .en
        }
        
        setupCallbacks()
        loadConversations()
        loadSystemPrompts()
        loadEndpointConfigs()
        
        Task {
            await fetchVoicesFromCurrentEndpoint()
        }
        
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
                self.currentlyPlayingMessageId = nil
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
        let title = L10n.newChat(appLanguage)
        let id = dbManager.createConversation(title: title)
        let newConv = Conversation(id: id, title: title, createdAt: Date())
        conversations.insert(newConv, at: 0)
        selectConversation(newConv)
        log("Created new conversation '\(title)' (\(id)).", tag: "DB")
    }
    
    func deleteConversation(_ conversation: Conversation) {
        let audioPaths = dbManager.fetchMessageAudioPaths(conversationId: conversation.id)
        dbManager.deleteConversation(id: conversation.id)
        for path in audioPaths {
            audioStorage.delete(filename: path)
            let messageId = (path as NSString).deletingPathExtension
            audioCache.removeValue(forKey: messageId)
        }
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
    
    func stopPlayback() {
        log("Stopping playback requested by user.", tag: "AUDIO")
        audioPlayer.stop()
        isPlayingAudio = false
        currentlyPlayingMessageId = nil
        // Resume mic recording if it's supposed to be active
        if isMicrophoneActive {
            log("Playback stopped: Resuming microphone recording.", tag: "AUDIO")
            audioRecorder.start()
        }
    }

    func playMessageAudio(_ message: Message) {
        guard message.role == "assistant" else { return }

        if currentlyPlayingMessageId == message.id && isPlayingAudio {
            stopPlayback()
            return
        }

        if isPlayingAudio {
            stopPlayback()
        }

        guard let audioData = loadAudioData(for: message) else {
            log("No saved audio for message \(message.id). Regenerating speech.", tag: "AUDIO")
            Task {
                await regenerateSpeech(for: message)
            }
            return
        }

        currentlyPlayingMessageId = message.id
        audioPlayer.play(data: audioData)
    }

    private func loadAudioData(for message: Message) -> Data? {
        if let cached = audioCache[message.id] {
            return cached
        }
        guard let filename = message.audioPath,
              let data = audioStorage.load(filename: filename) else {
            return nil
        }
        audioCache[message.id] = data
        return data
    }

    private func saveAudioData(_ data: Data, messageId: String, conversationId: String) {
        do {
            let filename = try audioStorage.save(messageId: messageId, data: data)
            audioCache[messageId] = data
            dbManager.updateMessageAudioPath(id: messageId, audioPath: filename)
            if activeConversation?.id == conversationId {
                messages = dbManager.fetchMessages(conversationId: conversationId)
            }
            log("Saved audio for message \(messageId) (\(data.count) bytes).", tag: "DB")
        } catch {
            log("Failed to save audio for message \(messageId): \(error.localizedDescription)", tag: "ERROR")
        }
    }

    private func regenerateSpeech(for message: Message) async {
        guard message.role == "assistant" else { return }
        isGeneratingSpeech = true
        log("Regenerating speech for message \(message.id)...", tag: "TTS")

        do {
            let audioData = try await apiManager.generateSpeech(
                endpoint: ttsURL,
                model: ttsModel,
                text: message.content,
                voice: ttsVoice,
                speed: ttsSpeed
            )
            isGeneratingSpeech = false
            saveAudioData(audioData, messageId: message.id, conversationId: message.conversationId)
            currentlyPlayingMessageId = message.id
            audioPlayer.play(data: audioData)
        } catch {
            log("TTS regeneration error: \(error.localizedDescription)", tag: "ERROR")
            isGeneratingSpeech = false
        }
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
        if conv.title == L10n.newChat(.en) || conv.title == L10n.newChat(.zh) {
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
        if let systemPromptText = activeSystemPrompt?.promptText, !systemPromptText.isEmpty {
            chatPayload.append(ChatMessage(role: "system", content: systemPromptText))
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
            await runSpeechGeneration(messageId: responseId, conversationId: conv.id, text: assistantText)
            
        } catch {
            log("LLM Error: \(error.localizedDescription)", tag: "ERROR")
            isGeneratingText = false
        }
    }
    
    private func runSpeechGeneration(messageId: String, conversationId: String, text: String) async {
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
            saveAudioData(audioData, messageId: messageId, conversationId: conversationId)
            currentlyPlayingMessageId = messageId
            audioPlayer.play(data: audioData)
            
        } catch {
            log("TTS Error: \(error.localizedDescription)", tag: "ERROR")
            isGeneratingSpeech = false
        }
    }
    
    // MARK: - System Prompt Manager Actions
    
    func loadSystemPrompts() {
        systemPrompts = dbManager.fetchSystemPrompts()
        activeSystemPrompt = systemPrompts.first(where: { $0.isActive }) ?? systemPrompts.first
        log("Loaded \(systemPrompts.count) system prompts. Active: '\(activeSystemPrompt?.title ?? "None")'.", tag: "DB")
    }
    
    func selectSystemPrompt(_ prompt: SystemPrompt) {
        dbManager.setActiveSystemPrompt(id: prompt.id)
        loadSystemPrompts()
    }
    
    func createSystemPrompt(title: String, promptText: String) {
        let _ = dbManager.createSystemPrompt(title: title, promptText: promptText)
        loadSystemPrompts()
    }
    
    func updateSystemPrompt(_ prompt: SystemPrompt, title: String, promptText: String) {
        dbManager.updateSystemPrompt(id: prompt.id, title: title, promptText: promptText)
        loadSystemPrompts()
    }
    
    func deleteSystemPrompt(_ prompt: SystemPrompt) {
        dbManager.deleteSystemPrompt(id: prompt.id)
        loadSystemPrompts()
    }
    
    func generatePromptText(for title: String) async -> String? {
        log("Generating system prompt instructions for title '\(title)'...", tag: "SYSTEM")
        let requestMessages = [
            ChatMessage(role: "system", content: "Keep your response short and concise."),
            ChatMessage(role: "user", content: "Create a \(title) system prompt! At the end of the prompt Respond with 1 to 2 sentences maximum.")
        ]
        
        do {
            let response = try await apiManager.generateText(
                endpoint: llmURL,
                model: llmModel,
                messages: requestMessages,
                temperature: 0.7,
                max_tokens: 199
            )
            return response
        } catch {
            log("Failed to generate AI prompt: \(error.localizedDescription)", tag: "ERROR")
            return nil
        }
    }
    
    // MARK: - Endpoint Configuration Actions
    
    func loadEndpointConfigs() {
        var fetched = dbManager.fetchEndpoints()
        if fetched.isEmpty {
            // Prepopulate a default
            let stt = "wss://speech_to_text.npro.ai?silence_duration_ms=1000"
            let llm = "https://text_gen.npro.ai/v1/chat/completions"
            let tts = "https://text_to_speech.npro.ai/v1/audio/speech"
            _ = dbManager.createEndpoint(name: L10n.defaultConfigName(appLanguage), textGenURL: llm, ttsURL: tts, sttURL: stt, isActive: true)
            fetched = dbManager.fetchEndpoints()
        }
        endpointConfigs = fetched
        activeEndpointConfig = endpointConfigs.first(where: { $0.isActive })
        
        if activeEndpointConfig == nil, let first = endpointConfigs.first {
            selectEndpointConfig(first)
        } else if let active = activeEndpointConfig {
            sttURL = active.sttURL
            llmURL = active.textGenURL
            ttsURL = active.ttsURL
        }
    }
    
    func selectEndpointConfig(_ config: EndpointConfig) {
        dbManager.setActiveEndpoint(id: config.id)
        loadEndpointConfigs()
        
        if isMicrophoneActive {
            log("Active endpoint switched to '\(config.name)'. Reconnecting microphone STT.", tag: "SYSTEM")
            stopMicrophonePipeline()
            startMicrophonePipeline()
        }
    }
    
    func createEndpointConfig(name: String, textGenURL: String, ttsURL: String, sttURL: String) {
        _ = dbManager.createEndpoint(name: name, textGenURL: textGenURL, ttsURL: ttsURL, sttURL: sttURL, isActive: false)
        loadEndpointConfigs()
    }
    
    func updateEndpointConfig(id: Int64, name: String, textGenURL: String, ttsURL: String, sttURL: String) {
        dbManager.updateEndpoint(id: id, name: name, textGenURL: textGenURL, ttsURL: ttsURL, sttURL: sttURL)
        loadEndpointConfigs()
        
        // If we updated the active configuration, reconnect pipeline if active
        if activeEndpointConfig?.id == id && isMicrophoneActive {
            log("Active endpoint '\(name)' updated. Reconnecting microphone STT.", tag: "SYSTEM")
            stopMicrophonePipeline()
            startMicrophonePipeline()
        }
    }
    
    func deleteEndpointConfig(id: Int64) {
        dbManager.deleteEndpoint(id: id)
        loadEndpointConfigs()
    }
    
    private func updateActiveConfigFromSettings() {
        guard let active = activeEndpointConfig else { return }
        if active.sttURL != sttURL || active.textGenURL != llmURL || active.ttsURL != ttsURL {
            dbManager.updateEndpoint(id: active.id, name: active.name, textGenURL: llmURL, ttsURL: ttsURL, sttURL: sttURL)
            // Update active config in memory too
            if var currentActive = activeEndpointConfig {
                currentActive.sttURL = sttURL
                currentActive.textGenURL = llmURL
                currentActive.ttsURL = ttsURL
                activeEndpointConfig = currentActive
            }
            if let idx = endpointConfigs.firstIndex(where: { $0.id == active.id }) {
                endpointConfigs[idx].sttURL = sttURL
                endpointConfigs[idx].textGenURL = llmURL
                endpointConfigs[idx].ttsURL = ttsURL
            }
        }
    }
    
    func fetchVoicesFromCurrentEndpoint() async {
        let currentTTSURL = ttsURL
        log("Fetching TTS voices list from endpoint: \(currentTTSURL)", tag: "TTS")
        do {
            let fetched = try await apiManager.fetchVoices(endpoint: currentTTSURL)
            self.voiceOptions = fetched
            self.log("Successfully loaded \(fetched.count) voices from server.", tag: "TTS")
            
            // If the currently selected voice is not in the fetched list, default to a sensible fallback
            if !fetched.isEmpty && !fetched.contains(ttsVoice) {
                if fetched.contains("bm_daniel") {
                    self.ttsVoice = "bm_daniel"
                } else if fetched.contains("zf_xiaoxiao") {
                    self.ttsVoice = "zf_xiaoxiao"
                } else if fetched.contains("zm_009") {
                    self.ttsVoice = "zm_009"
                } else if let first = fetched.first {
                    self.ttsVoice = first
                }
                self.log("Current voice not available. Switched voice to: \(self.ttsVoice)", tag: "TTS")
            }
        } catch {
            self.log("Failed to fetch voices from server: \(error.localizedDescription).", tag: "ERROR")
            self.voiceOptions = [] // clear options to show warning in UI
        }
    }
    
    func testTextGenEndpoint(url: String) async -> Bool {
        return await apiManager.testTextGenConnection(url: url)
    }
    
    func testTTSEndpoint(url: String) async -> Bool {
        do {
            let voices = try await apiManager.fetchVoices(endpoint: url)
            return !voices.isEmpty
        } catch {
            return false
        }
    }
    
    func testSTTEndpoint(url: String) async -> Bool {
        return await apiManager.testSTTConnection(url: url)
    }
    
    func testSelectedVoice() {
        guard !isTestingVoice else { return }
        isTestingVoice = true
        log("Testing voice '\(ttsVoice)'...", tag: "TTS")
        
        Task {
            do {
                let text: String
                let prefix = ttsVoice.prefix(1).lowercased()
                switch prefix {
                case "z":
                    text = "你好，这是测试声音。"
                case "j":
                    text = "こんにちは、テスト音声です。"
                case "e":
                    text = "Hola, esta es una voz de prueba."
                case "f":
                    text = "Bonjour, ceci est une voix de test."
                case "h":
                    text = "नमस्ते, यह एक परीक्षण आवाज़ है।"
                case "i":
                    text = "Ciao, questa è una voce di prova."
                case "p":
                    text = "Olá, esta é uma voz de teste."
                default:
                    text = "Hello, this is a test voice."
                }
                
                let audioData = try await apiManager.generateSpeech(
                    endpoint: ttsURL,
                    model: ttsModel,
                    text: text,
                    voice: ttsVoice,
                    speed: ttsSpeed
                )
                
                audioPlayer.play(data: audioData)
                log("Voice test audio generated and playing.", tag: "TTS")
            } catch {
                log("Failed to test voice: \(error.localizedDescription)", tag: "ERROR")
            }
            isTestingVoice = false
        }
    }
    
    func runTextGenTest(url: String) async throws -> String {
        log("Running Text Gen test on \(url)", tag: "LLM")
        let response = try await apiManager.generateText(
            endpoint: url,
            model: "default-test",
            messages: [
                ChatMessage(role: "user", content: "Write a short sentence about a quick brown fox.")
            ],
            temperature: 0.7,
            max_tokens: 50
        )
        return response
    }
    
    func runTTSTest(url: String, text: String) async throws {
        log("Running TTS test on \(url) with text: \(text)", tag: "TTS")
        let audioData = try await apiManager.generateSpeech(
            endpoint: url,
            model: ttsModel,
            text: text,
            voice: ttsVoice.isEmpty ? "bm_daniel" : ttsVoice,
            speed: ttsSpeed
        )
        audioPlayer.play(data: audioData)
    }
    
    func startSTTTest(configId: Int64, url: String) {
        stopSTTTest()
        
        log("Starting STT test for config \(configId) on \(url)", tag: "STT")
        activeTestSTTConfigId = configId
        testSTTText = ""
        
        if isMicrophoneActive {
            stopMicrophonePipeline()
        }
        
        testWebSocketManager = WebSocketManager(urlString: url)
        testWebSocketManager?.onLog = { [weak self] msg in
            self?.log("[Test STT] \(msg)", tag: "STT")
        }
        testWebSocketManager?.onError = { [weak self] err in
            self?.log("[Test STT] Error: \(err)", tag: "ERROR")
        }
        testWebSocketManager?.onConnectionStateChange = { [weak self] connected in
            guard let self = self else { return }
            Task { @MainActor in
                if connected {
                    self.log("[Test STT] Connected. Starting audio capture.", tag: "STT")
                    self.testAudioRecorder = AudioRecorder()
                    self.testAudioRecorder?.onLog = { msg in
                        self.log("[Test Audio] \(msg)", tag: "AUDIO")
                    }
                    self.testAudioRecorder?.onError = { err in
                        self.log("[Test Audio] Error: \(err)", tag: "ERROR")
                        Task { @MainActor in
                            self.stopSTTTest()
                        }
                    }
                    self.testAudioRecorder?.onAudioData = { data in
                        Task { @MainActor in
                            self.testWebSocketManager?.sendAudio(data: data)
                        }
                    }
                    self.testAudioRecorder?.start()
                } else {
                    self.log("[Test STT] Disconnected.", tag: "STT")
                    self.stopSTTTest()
                }
            }
        }
        testWebSocketManager?.onMessageReceived = { [weak self] transcription in
            guard let self = self else { return }
            Task { @MainActor in
                self.log("[Test STT] Transcription: \"\(transcription)\"", tag: "STT")
                self.testSTTText = transcription
            }
        }
        
        testWebSocketManager?.connect()
    }
    
    func stopSTTTest() {
        guard activeTestSTTConfigId != nil else { return }
        log("Stopping STT test.", tag: "STT")
        activeTestSTTConfigId = nil
        testSTTText = ""
        
        testAudioRecorder?.stop()
        testAudioRecorder = nil
        
        testWebSocketManager?.disconnect()
        testWebSocketManager = nil
    }
}
