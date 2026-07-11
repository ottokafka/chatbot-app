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

/// Owns speaking presentation flags and the typed conversation state machine (D14).
/// STT / TTS land in PR2b; this PR is text-only.
@MainActor
final class SpeakingSessionViewModel: ObservableObject {
    // MARK: Presentation (D14 — only on this VM)

    @Published var isShowingSetup = false
    @Published var isShowingSession = false
    @Published private(set) var session: SpeakingSession?

    /// Last user utterance that failed mid-turn LLM reply (typed path). Cleared on success.
    @Published private(set) var pendingUserText: String?

    /// Draft config from setup; frozen into `session` on `startSession`.
    @Published private(set) var pendingConfig: SpeakingSessionConfig?

    // MARK: Endpoints (wired from ChatViewModel; frozen languages also live on config)

    private(set) var llmURL: String = ""
    private(set) var llmModel: String = ""
    private(set) var sttURL: String = ""
    private(set) var ttsURL: String = ""
    private(set) var ttsVoice: String = ""
    private(set) var appLanguage: AppLanguage = .en
    private(set) var sttLanguage: STTLanguage = .auto
    private var onLog: ((String) -> Void)?

    /// Own instance; do not inject via configureEndpoints.
    private let apiManager = APIManager()

    /// Explicit completion params (APIManager defaults are 0.7 / 199 — do not rely on them).
    static let replyTemperature: Double = 0.6
    /// Midpoint of recommended 120…160 band.
    static let replyMaxTokens: Int = 140

    /// Serializes in-flight LLM work so double-taps cannot stack generations.
    private var generationTask: Task<Void, Never>?

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

    /// Creates session from pending config and requests the opening assistant turn.
    func startSession() async {
        guard let config = pendingConfig else {
            log("Speaking: startSession aborted — no pendingConfig")
            return
        }
        generationTask?.cancel()
        generationTask = nil

        isShowingSetup = false
        isShowingSession = true
        pendingUserText = nil

        var newSession = SpeakingSession(config: config, status: .ready)
        newSession.lastError = nil
        session = newSession
        log("Speaking: startSession id=\(newSession.id)")

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
        current.lastError = nil
        current.status = .generatingReply
        session = current
        await generateReply(isRetry: true)
    }

    /// Typed user turn (skips speech correction). No STT in this PR.
    func sendTypedText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var current = session else { return }
        guard current.status == .waitingUser else {
            log("Speaking: sendTypedText ignored — status=\(current.status)")
            return
        }

        // New typed turn supersedes any prior failed reply payload.
        pendingUserText = nil
        current.lastError = nil

        let targets = current.config.targetFronts
        let hits = SpeakingTargetTracker.hits(
            in: trimmed,
            targets: targets,
            script: current.config.script
        )
        // Learner production only: prior covered fronts ∪ hits from this turn.
        let covered = Set(current.coveredTargetFronts + hits)
        current.uncoveredTargetFronts = SpeakingTargetTracker.remaining(
            targets: targets,
            covered: covered
        )

        let userTurn = SpeakingTurn(
            role: .user,
            content: trimmed,
            targetHits: hits
        )
        current.turns.append(userTurn)
        current.status = .generatingReply
        session = current
        log("Speaking: user typed turn hits=\(hits.count) uncovered=\(current.uncoveredTargetFronts.count)")

        await generateReply(isRetry: false)
    }

    func endSession() {
        generationTask?.cancel()
        generationTask = nil
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
        session = nil
        pendingUserText = nil
        pendingConfig = nil
        isShowingSession = false
        isShowingSetup = false
    }

    // MARK: - LLM

    private func generateOpening() async {
        guard var current = session else { return }
        // Cancel any prior generation.
        generationTask?.cancel()

        current.status = .generatingReply
        current.lastError = nil
        session = current

        let config = current.config
        let messages = SpeakingPromptBuilder.buildOpeningMessages(config: config)
        let endpoint = llmURL
        let model = llmModel

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
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    self.failOpening(message: "Opening reply was empty.")
                    return
                }
                self.applyAssistantOpening(text: text)
            } catch is CancellationError {
                // Ignore
            } catch {
                guard !Task.isCancelled else { return }
                self.failOpening(message: error.localizedDescription)
            }
        }
        generationTask = task
        await task.value
    }

    private func generateReply(isRetry: Bool) async {
        guard var current = session else { return }
        generationTask?.cancel()

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
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    self.failReply(message: "Assistant reply was empty.", userText: lastUserText)
                    return
                }
                self.applyAssistantReply(text: text)
            } catch is CancellationError {
                // Ignore
            } catch {
                guard !Task.isCancelled else { return }
                self.failReply(message: error.localizedDescription, userText: lastUserText)
            }
        }
        generationTask = task
        await task.value
    }

    private func applyAssistantOpening(text: String) {
        guard var current = session else { return }
        let turn = SpeakingTurn(role: .assistant, content: text)
        current.turns.append(turn)
        current.status = .waitingUser
        current.lastError = nil
        session = current
        logSoftAssistantCoverage(text: text, config: current.config)
        log("Speaking: opening ok chars=\(text.count)")
        // PR2a: no TTS — stay in waitingUser (playingTTS lands in PR2b).
    }

    private func applyAssistantReply(text: String) {
        guard var current = session else { return }
        let turn = SpeakingTurn(role: .assistant, content: text)
        current.turns.append(turn)
        current.status = .waitingUser
        current.lastError = nil
        session = current
        pendingUserText = nil
        logSoftAssistantCoverage(text: text, config: current.config)
        log("Speaking: reply ok chars=\(text.count)")
    }

    private func failOpening(message: String) {
        guard var current = session else { return }
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
