import Foundation
import SwiftUI
import Combine

// MARK: - Feature flag

/// UserDefaults key `speaking.enabled`.
/// Default **false** until PR3 (first user-visible ship) lands, then default **true**.
enum SpeakingFeature {
    static let userDefaultsKey = "speaking.enabled"

    /// First feature-flag pattern in this codebase — keep the helper tiny.
    static var isEnabled: Bool {
        get {
            // Explicit false default when key is unset (object(forKey:) == nil).
            if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }
}

// MARK: - Session view model

/// Owns speaking presentation flags and the conversation state machine (D14).
/// Session-owned STT (`WebSocketManager` + `AudioRecorder`); shared ephemeral TTS via injected chat hooks (D11).
@MainActor
final class SpeakingSessionViewModel: ObservableObject {
    // MARK: Presentation (D14 — only on this VM)

    @Published var isShowingSetup = false
    @Published var isShowingSession = false
    @Published private(set) var session: SpeakingSession?

    /// Last user utterance that failed mid-turn LLM reply. Cleared on success.
    @Published private(set) var pendingUserText: String?

    /// Draft config from setup; frozen into `session` on `startSession`.
    @Published private(set) var pendingConfig: SpeakingSessionConfig?

    /// Session-owned mic is recording (always-on when `waitingUser`, off during TTS / LLM).
    @Published private(set) var isSpeakingMicActive = false
    /// Session-owned STT WebSocket connected.
    @Published private(set) var isSpeakingSTTConnected = false
    /// Auto-play assistant TTS (MVP default on).
    @Published var autoPlayTTS = true

    // MARK: Endpoints (wired from ChatViewModel; frozen languages also live on config)

    private(set) var llmURL: String = ""
    private(set) var llmModel: String = ""
    private(set) var sttURL: String = ""
    private(set) var ttsURL: String = ""
    private(set) var ttsVoice: String = ""
    private(set) var appLanguage: AppLanguage = .en
    private(set) var sttLanguage: STTLanguage = .auto
    private var onLog: ((String) -> Void)?

    // MARK: Chat audio injection (shared player only — no second AudioPlayer)

    private var yieldHardware: (() -> Void)?
    private var playEphemeral: ((String, String) -> Void)?
    private var isGeneratingEphemeral: ((String) -> Bool)?
    private var isPlayingEphemeral: ((String) -> Bool)?
    private var stopSharedPlayback: (() -> Void)?

    /// Own instance; do not inject via configureEndpoints.
    private let apiManager = APIManager()

    /// Session-owned STT (not chat's private instances) — D11 / D23.
    private var speakingWebSocket: WebSocketManager?
    private let speakingRecorder = AudioRecorder()

    /// Explicit completion params (APIManager defaults are 0.7 / 199 — do not rely on them).
    static let replyTemperature: Double = 0.6
    /// Midpoint of recommended 120…160 band.
    static let replyMaxTokens: Int = 140

    /// Serializes in-flight LLM work so double-taps cannot stack generations.
    private var generationTask: Task<Void, Never>?
    /// Watches shared ephemeral TTS idle for the in-flight playback id.
    private var ttsWatchTask: Task<Void, Never>?
    /// Local in-flight TTS id (covers generate + play window).
    private var inFlightTTSPlaybackId: String?

    // MARK: - Configuration

    func configureEndpoints(
        llmURL: String,
        llmModel: String,
        sttURL: String,
        ttsURL: String,
        ttsVoice: String,
        appLanguage: AppLanguage,
        sttLanguage: STTLanguage,
        onLog: ((String) -> Void)?
    ) {
        self.llmURL = llmURL
        self.llmModel = llmModel
        self.sttURL = sttURL
        self.ttsURL = ttsURL
        self.ttsVoice = ttsVoice
        self.appLanguage = appLanguage
        self.sttLanguage = sttLanguage
        self.onLog = onLog
        apiManager.onLog = onLog
    }

    /// Inject shared chat audio hooks. Speaking never owns a second `AudioPlayer`.
    func configureChatAudio(
        yieldHardware: @escaping () -> Void,
        playEphemeralSpeech: @escaping (_ text: String, _ playbackId: String) -> Void,
        isGeneratingEphemeral: @escaping (_ playbackId: String) -> Bool,
        isPlayingEphemeral: @escaping (_ playbackId: String) -> Bool,
        stopPlayback: @escaping () -> Void
    ) {
        self.yieldHardware = yieldHardware
        self.playEphemeral = playEphemeralSpeech
        self.isGeneratingEphemeral = isGeneratingEphemeral
        self.isPlayingEphemeral = isPlayingEphemeral
        self.stopSharedPlayback = stopPlayback
    }

    /// Stores setup draft. Caller owns when to set `isShowingSetup` (after mutual exclusion).
    func prepareSetup(
        seedSource: PracticeSeedSource,
        targets: [Flashcard],
        knownFronts: [String],
        topicHint: String,
        encourageTargetCoverage: Bool
    ) {
        pendingConfig = SpeakingSessionConfig(
            seedSource: seedSource,
            targetCards: targets,
            knownFronts: knownFronts,
            topicHint: topicHint,
            encourageTargetCoverage: encourageTargetCoverage,
            maxAssistantCharsChinese: PracticeGenerationConfig.babyLanguageMaxCharsChinese,
            maxAssistantWordsEnglish: PracticeGenerationConfig.babyLanguageMaxWordsEnglish,
            appLanguage: appLanguage,
            sttLanguage: sttLanguage,
            speechCorrectionEnabled: true
        )
        pendingUserText = nil
        log("Speaking: prepareSetup source=\(seedSource.analyticsName) targets=\(targets.count) known=\(knownFronts.count) encourage=\(encourageTargetCoverage)")
    }

    // MARK: - Session lifecycle

    /// Creates session from pending config, yields chat audio hardware, starts session STT, opening turn.
    func startSession() async {
        guard let config = pendingConfig else {
            log("Speaking: startSession aborted — no pendingConfig")
            return
        }
        generationTask?.cancel()
        generationTask = nil
        ttsWatchTask?.cancel()
        ttsWatchTask = nil
        inFlightTTSPlaybackId = nil

        isShowingSetup = false
        isShowingSession = true
        pendingUserText = nil

        var newSession = SpeakingSession(config: config, status: .ready)
        newSession.lastError = nil
        session = newSession
        log("Speaking: startSession id=\(newSession.id)")

        // D11: force-stop chat mic + player without re-arming chat mic.
        yieldHardware?()
        connectSpeakingSTT(language: config.sttLanguage)

        await generateOpening()
    }

    /// Opening LLM failure recovery (D24): stays `ready`, keeps banner + Retry.
    func retryOpening() async {
        guard var current = session else { return }
        guard current.status == .ready else {
            log("Speaking: retryOpening ignored — status=\(current.status)")
            return
        }
        current.lastError = nil
        session = current
        await generateOpening()
    }

    /// Re-send `pendingUserText` through the reply path after mid-turn LLM failure (D24).
    /// Does **not** re-append a user turn (already on the transcript).
    func retryLastReply() async {
        guard let pending = pendingUserText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pending.isEmpty else {
            log("Speaking: retryLastReply ignored — no pendingUserText")
            return
        }
        guard var current = session else { return }
        guard current.status == .waitingUser else {
            log("Speaking: retryLastReply ignored — status=\(current.status)")
            return
        }
        stopSpeakingRecorder()
        current.lastError = nil
        current.status = .generatingReply
        session = current
        await generateReply(isRetry: true)
    }

    /// Typed user turn (skips speech correction).
    func sendTypedText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var current = session else { return }
        guard current.status == .waitingUser else {
            log("Speaking: sendTypedText ignored — status=\(current.status)")
            return
        }

        stopSpeakingRecorder()

        // New typed turn supersedes any prior failed reply payload.
        pendingUserText = nil
        current.lastError = nil

        appendUserTurn(
            content: trimmed,
            rawASR: nil,
            tutorFeedback: nil,
            to: &current
        )
        current.status = .generatingReply
        session = current
        log("Speaking: user typed turn hits=\(current.turns.last?.targetHits.count ?? 0) uncovered=\(current.uncoveredTargetFronts.count)")

        await generateReply(isRetry: false)
    }

    func endSession() {
        generationTask?.cancel()
        generationTask = nil
        ttsWatchTask?.cancel()
        ttsWatchTask = nil
        inFlightTTSPlaybackId = nil

        // Disconnect speaking STT; stop shared player; leave chat mic OFF (D11).
        disconnectSpeakingSTT()
        stopSharedPlayback?()

        if var current = session {
            current.status = .ended
            current.lastError = nil
            session = current
        }
        pendingUserText = nil
        isShowingSession = false
        isShowingSetup = false
        log("Speaking: endSession")
    }

    /// Clears session state after dismiss (optional; keeps last transcript until next prepare).
    func discardSession() {
        generationTask?.cancel()
        generationTask = nil
        ttsWatchTask?.cancel()
        ttsWatchTask = nil
        inFlightTTSPlaybackId = nil
        disconnectSpeakingSTT()
        stopSharedPlayback?()
        session = nil
        pendingUserText = nil
        pendingConfig = nil
        isShowingSession = false
        isShowingSetup = false
    }

    // MARK: - Speech correction history

    /// Last ≤8 turns mapped to `ChatMessage` with **canonical content only** (no tips / raw ASR).
    static func correctionHistory(from turns: [SpeakingTurn], limit: Int = 8) -> [ChatMessage] {
        turns.suffix(limit).map { turn in
            ChatMessage(
                role: turn.role == .user ? "user" : "assistant",
                content: turn.content
            )
        }
    }

    // MARK: - Session STT (owned)

    private func connectSpeakingSTT(language: STTLanguage) {
        disconnectSpeakingSTT()

        let connectURL = SpeechCorrection.sttURL(base: sttURL, language: language)
        log("Speaking: connecting session STT → \(connectURL)")

        speakingRecorder.onLog = { [weak self] msg in
            self?.log(msg)
        }
        speakingRecorder.onError = { [weak self] err in
            self?.log("Speaking recorder error: \(err)")
            Task { @MainActor in
                self?.isSpeakingMicActive = false
            }
        }
        speakingRecorder.onAudioData = { [weak self] data in
            Task { @MainActor in
                self?.speakingWebSocket?.sendAudio(data: data)
            }
        }

        let ws = WebSocketManager(urlString: connectURL)
        ws.onLog = { [weak self] msg in
            self?.log(msg)
        }
        ws.onError = { [weak self] err in
            self?.log("Speaking STT error: \(err)")
        }
        ws.onConnectionStateChange = { [weak self] connected in
            Task { @MainActor in
                guard let self else { return }
                self.isSpeakingSTTConnected = connected
                if connected {
                    self.log("Speaking: STT connected")
                    // Recorder only while waiting for the user (not during TTS / LLM).
                    if self.session?.status == .waitingUser {
                        self.startSpeakingRecorderIfNeeded()
                    }
                } else {
                    self.log("Speaking: STT disconnected")
                    self.speakingRecorder.stop()
                    self.isSpeakingMicActive = false
                }
            }
        }
        ws.onMessageReceived = { [weak self] transcription in
            Task { @MainActor in
                await self?.handleFinalASR(transcription)
            }
        }
        speakingWebSocket = ws
        ws.connect()
    }

    private func disconnectSpeakingSTT() {
        speakingRecorder.stop()
        isSpeakingMicActive = false
        isSpeakingSTTConnected = false
        speakingWebSocket?.disconnect()
        speakingWebSocket = nil
        speakingRecorder.onAudioData = nil
        speakingRecorder.onError = nil
        speakingRecorder.onLog = nil
    }

    private func startSpeakingRecorderIfNeeded() {
        guard session?.status == .waitingUser else { return }
        guard speakingWebSocket?.isConnected == true else { return }
        guard !isSpeakingMicActive else { return }
        log("Speaking: starting session mic")
        isSpeakingMicActive = true
        speakingRecorder.start()
    }

    private func stopSpeakingRecorder() {
        // Always stop engine; flag may already be false after error.
        if isSpeakingMicActive {
            log("Speaking: pausing session mic")
        }
        speakingRecorder.stop()
        isSpeakingMicActive = false
    }

    // MARK: - Voice path

    private func handleFinalASR(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var current = session else { return }
        guard current.status == .waitingUser else {
            // Ignore finals while TTS / LLM / correction is busy (no barge-in).
            log("Speaking: ignoring ASR while status=\(current.status)")
            return
        }

        let sessionId = current.id
        stopSpeakingRecorder()

        pendingUserText = nil
        current.lastError = nil
        current.status = .correctingSpeech
        session = current
        log("Speaking: final ASR \"\(trimmed)\" — correcting")

        let history = Self.correctionHistory(from: current.turns, limit: 8)
        let sttLang = current.config.sttLanguage
        let appLang = current.config.appLanguage
        let endpoint = llmURL
        let model = llmModel

        // Forced on for whole session (D8); still respects config flag if ever toggled later.
        let result: SpeechCorrectionResult
        if current.config.speechCorrectionEnabled {
            result = await SpeechCorrection.correct(
                rawText: trimmed,
                history: history,
                targetLanguage: sttLang,
                appLanguage: appLang,
                endpoint: endpoint,
                model: model,
                apiManager: apiManager
            )
        } else {
            result = .fallback(trimmed)
        }

        guard session?.id == sessionId, session?.status == .correctingSpeech else {
            log("Speaking: correction result dropped (session ended or status changed)")
            return
        }

        if result.usedFallback {
            log("Speaking: correction fallback — raw ASR")
        } else {
            log("Speaking: corrected \"\(trimmed)\" → \"\(result.correctedText)\"")
        }

        guard var live = session else { return }
        let feedback = result.feedback.isEmpty ? nil : result.feedback
        appendUserTurn(
            content: result.correctedText,
            rawASR: trimmed,
            tutorFeedback: feedback,
            to: &live
        )
        live.status = .generatingReply
        session = live
        log("Speaking: user voice turn hits=\(live.turns.last?.targetHits.count ?? 0) uncovered=\(live.uncoveredTargetFronts.count)")

        await generateReply(isRetry: false)
    }

    private func appendUserTurn(
        content: String,
        rawASR: String?,
        tutorFeedback: String?,
        to current: inout SpeakingSession
    ) {
        let targets = current.config.targetFronts
        let hits = SpeakingTargetTracker.hits(
            in: content,
            targets: targets,
            script: current.config.script
        )
        let covered = Set(current.coveredTargetFronts + hits)
        current.uncoveredTargetFronts = SpeakingTargetTracker.remaining(
            targets: targets,
            covered: covered
        )
        let userTurn = SpeakingTurn(
            role: .user,
            content: content,
            rawASR: rawASR,
            tutorFeedback: tutorFeedback,
            targetHits: hits
        )
        current.turns.append(userTurn)
    }

    // MARK: - LLM

    private func generateOpening() async {
        guard var current = session else { return }
        generationTask?.cancel()

        stopSpeakingRecorder()
        current.status = .generatingReply
        current.lastError = nil
        session = current

        let config = current.config
        let messages = SpeakingPromptBuilder.buildOpeningMessages(config: config)
        let endpoint = llmURL
        let model = llmModel
        let sessionId = current.id

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.apiManager.generateText(
                    endpoint: endpoint,
                    model: model,
                    messages: messages,
                    temperature: Self.replyTemperature,
                    max_tokens: Self.replyMaxTokens
                )
                guard !Task.isCancelled else { return }
                guard self.session?.id == sessionId else { return }
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    self.failOpening(message: "Opening reply was empty.")
                    return
                }
                await self.presentAssistantText(text, clearPending: false, sessionId: sessionId)
            } catch is CancellationError {
                // Ignore
            } catch {
                guard !Task.isCancelled else { return }
                guard self.session?.id == sessionId else { return }
                self.failOpening(message: error.localizedDescription)
            }
        }
        generationTask = task
        await task.value
    }

    private func generateReply(isRetry: Bool) async {
        guard var current = session else { return }
        generationTask?.cancel()

        stopSpeakingRecorder()
        current.status = .generatingReply
        current.lastError = nil
        session = current

        let config = current.config
        let turns = current.turns
        let uncovered = current.uncoveredTargetFronts
        let messages = SpeakingPromptBuilder.buildReplyMessages(
            config: config,
            turns: turns,
            uncoveredTargets: uncovered
        )
        let endpoint = llmURL
        let model = llmModel
        let sessionId = current.id
        // Snapshot for D24: mid-turn fail retains pendingUserText for retryLastReply.
        let lastUserText = isRetry
            ? pendingUserText
            : current.turns.last(where: { $0.role == .user })?.content

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let raw = try await self.apiManager.generateText(
                    endpoint: endpoint,
                    model: model,
                    messages: messages,
                    temperature: Self.replyTemperature,
                    max_tokens: Self.replyMaxTokens
                )
                guard !Task.isCancelled else { return }
                guard self.session?.id == sessionId else { return }
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    self.failReply(message: "Assistant reply was empty.", userText: lastUserText)
                    return
                }
                await self.presentAssistantText(text, clearPending: true, sessionId: sessionId)
            } catch is CancellationError {
                // Ignore
            } catch {
                guard !Task.isCancelled else { return }
                guard self.session?.id == sessionId else { return }
                self.failReply(message: error.localizedDescription, userText: lastUserText)
            }
        }
        generationTask = task
        await task.value
    }

    /// Append assistant turn, soft-log coverage, then TTS window → waitingUser.
    private func presentAssistantText(_ text: String, clearPending: Bool, sessionId: String) async {
        guard var current = session, current.id == sessionId else { return }
        let turn = SpeakingTurn(role: .assistant, content: text)
        current.turns.append(turn)
        current.lastError = nil
        session = current
        if clearPending {
            pendingUserText = nil
        }
        logSoftAssistantCoverage(text: text, config: current.config)
        log("Speaking: assistant ok chars=\(text.count) id=\(turn.id)")

        await playAssistantTTSThenWaitForUser(turn: turn, sessionId: sessionId)
    }

    /// `playingTTS` covers network generate + play. Mic stays off until idle for playbackId.
    private func playAssistantTTSThenWaitForUser(turn: SpeakingTurn, sessionId: String) async {
        guard session?.id == sessionId, session?.status != .ended else { return }

        let shouldPlay = autoPlayTTS && playEphemeral != nil
        guard shouldPlay else {
            enterWaitingUser(sessionId: sessionId)
            return
        }

        let playbackId = "speaking-\(turn.id)"
        inFlightTTSPlaybackId = playbackId

        if var current = session, current.id == sessionId {
            current.status = .playingTTS
            session = current
        }
        stopSpeakingRecorder()

        log("Speaking: TTS start id=\(playbackId)")
        playEphemeral?(turn.content, playbackId)

        await waitForEphemeralTTSIdle(playbackId: playbackId, sessionId: sessionId)

        guard session?.id == sessionId else { return }
        inFlightTTSPlaybackId = nil
        // Only transition if still in playingTTS (not ended / cancelled mid-flight).
        if session?.status == .playingTTS {
            enterWaitingUser(sessionId: sessionId)
        }
    }

    /// Leave when `!isGenerating && !isPlaying` for this id (covers generate fail).
    private func waitForEphemeralTTSIdle(playbackId: String, sessionId: String) async {
        ttsWatchTask?.cancel()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            // Brief arming window: generate flag is set inside an async Task on chat.
            try? await Task.sleep(nanoseconds: 150_000_000)
            while !Task.isCancelled {
                guard self.session?.id == sessionId else { return }
                guard self.session?.status == .playingTTS else { return }

                let generating = self.isGeneratingEphemeral?(playbackId) ?? false
                let playing = self.isPlayingEphemeral?(playbackId) ?? false
                if !generating && !playing {
                    self.log("Speaking: TTS idle id=\(playbackId)")
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        ttsWatchTask = task
        await task.value
    }

    private func enterWaitingUser(sessionId: String) {
        guard var current = session, current.id == sessionId else { return }
        guard current.status != .ended else { return }
        current.status = .waitingUser
        session = current
        startSpeakingRecorderIfNeeded()
        log("Speaking: waitingUser (mic=\(isSpeakingMicActive) stt=\(isSpeakingSTTConnected))")
    }

    private func failOpening(message: String) {
        guard var current = session else { return }
        stopSpeakingRecorder()
        current.status = .ready
        current.lastError = message
        session = current
        log("Speaking: opening failed — \(message)")
    }

    private func failReply(message: String, userText: String?) {
        guard var current = session else { return }
        current.status = .waitingUser
        current.lastError = message
        session = current
        if let userText, !userText.isEmpty {
            pendingUserText = userText
        }
        startSpeakingRecorderIfNeeded()
        log("Speaking: reply failed — \(message)")
    }

    /// Soft leakage diagnostics on **assistant** text only (log-only; no auto-retry).
    /// `seedFronts` = all target fronts; `knownFronts` from frozen session config.
    private func logSoftAssistantCoverage(text: String, config: SpeakingSessionConfig) {
        let diagnostics = PracticeScaffoldValidator.diagnose(
            sentence: text,
            knownFronts: config.knownFronts,
            seedFronts: config.targetFronts
        )
        PracticeScaffoldValidator.logIfFlagged(
            diagnostics,
            knownFrontsCount: config.knownFronts.count,
            onLog: { [weak self] msg in
                self?.log(msg)
            }
        )
    }

    private func log(_ message: String) {
        onLog?(message)
        #if DEBUG
        print(message)
        #endif
    }
}
