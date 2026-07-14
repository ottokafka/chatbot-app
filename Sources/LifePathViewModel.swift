import Foundation
import SwiftUI
import Combine
import AVFoundation

@MainActor
final class LifePathViewModel: ObservableObject {
    @Published private(set) var language: LifePathLanguage?
    @Published private(set) var showLanguagePicker = false
    @Published private(set) var stages: [LifePathStageMeta] = []
    @Published private(set) var entries: [LifePathEntry] = []
    @Published private(set) var listRowsByEntryId: [String: LifePathListRow] = [:]
    @Published private(set) var profile: LifePathProfile?
    @Published private(set) var loadError: String?
    @Published var actionError: String?

    // Session
    @Published private(set) var isPlaying = false
    @Published private(set) var sessionQueue: [LifePathEntry] = []
    @Published private(set) var sessionIndex = 0
    @Published private(set) var isAnswerRevealed = false
    @Published private(set) var sessionCorrect = 0
    @Published private(set) var sessionWrong = 0
    @Published private(set) var sessionFinished = false

    // Level-up
    @Published var pendingLevelUp: LifePathLevelUpNotify?
    @Published var showLevelUp = false

    // Pronunciation Assessment
    enum PronunciationState: Equatable {
        case idle
        case recording
        case assessing
        case feedback(PronunciationAssessmentResponse)
        case error(String)
    }
    @Published private(set) var pronunciationState: PronunciationState = .idle

    /// The word currently being assessed. Set when recording starts.
    private(set) var pronunciationTargetWord: String = ""

    /// Latest assessment result (mirrors `.feedback` for convenient view binding).
    var latestPronunciationResult: PronunciationAssessmentResponse? {
        if case .feedback(let r) = pronunciationState { return r }
        return nil
    }

    private let pronunciationRecorder = AudioRecorder()
    private var pronunciationAccumulatedData: Data = Data()
    private var pronunciationAPIManager: APIManager?
    private var pronunciationAssessWS: WebSocketManager?
    private var pronunciationWSReady = false
    private var pronunciationResultFromWS = false
    private var pronunciationAutoGradeTask: Task<Void, Never>?

    // Client-side energy VAD (does not require correct STT recognition)
    private var vadHeardSpeech = false
    private var vadSpeechSamples = 0
    private var vadSilenceSamples = 0
    private var vadTotalSamples = 0
    private let vadSampleRate = 16000
    private let vadSpeechRMS: Float = 0.012
    private let vadMinSpeechMs = 280
    private let vadSilenceMs = 700
    private let vadMaxMs = 5000

    private var dbManager: DatabaseManager
    private weak var flashcardVM: FlashcardViewModel?
    private var entriesById: [String: LifePathEntry] = [:]

    var onLog: ((String) -> Void)?
    /// Host sets this so language-picker cancel can leave the feature (route `onExit`).
    var onRequestExit: (() -> Void)?
    /// Must be provided by the host (LifePathRootView) so assessment uses the active endpoint.
    var pronunciationURLProvider: (() -> String)?
    /// Optional STT base URL (no longer required for pronunciation auto-stop).
    var sttURLProvider: (() -> String)?

    init(dbManager: DatabaseManager = DatabaseManager(), flashcardVM: FlashcardViewModel? = nil) {
        self.dbManager = dbManager
        self.flashcardVM = flashcardVM
        self.pronunciationAPIManager = APIManager()
        self.pronunciationAPIManager?.onLog = { [weak self] msg in self?.onLog?(msg) }
        configurePronunciationRecorder()
    }

    private func configurePronunciationRecorder() {
        pronunciationRecorder.onLog = { [weak self] msg in
            self?.onLog?("Pronunciation mic: \(msg)")
        }
        pronunciationRecorder.onError = { [weak self] err in
            Task { @MainActor in
                self?.pronunciationState = .error(err)
            }
        }
        pronunciationRecorder.onAudioData = { [weak self] data in
            Task { @MainActor in
                self?.handlePronunciationAudioChunk(data)
            }
        }
    }

    func attach(flashcardVM: FlashcardViewModel, dbManager: DatabaseManager? = nil) {
        self.flashcardVM = flashcardVM
        if let dbManager {
            self.dbManager = dbManager
        }
    }

    // MARK: - Derived

    var currentStage: LifePathStageMeta? {
        guard let stageId = profile?.currentStageId else { return stages.first }
        return stages.first { $0.id == stageId } ?? stages.first
    }

    var currentStageEntries: [LifePathEntry] {
        guard let stageId = profile?.currentStageId else { return [] }
        return entries.filter { $0.stageId == stageId }.sorted { $0.rankInStage < $1.rankInStage }
    }

    var masteredInCurrentStage: Int {
        guard let stageId = profile?.currentStageId else { return 0 }
        return listRowsByEntryId.values.filter { $0.stageId == stageId && $0.status == .mastered }.count
    }

    var totalInCurrentStage: Int {
        currentStageEntries.count
    }

    var stageProgress: Double {
        guard totalInCurrentStage > 0 else { return 0 }
        return Double(masteredInCurrentStage) / Double(totalInCurrentStage)
    }

    var currentCard: LifePathEntry? {
        guard isPlaying, sessionIndex < sessionQueue.count else { return nil }
        return sessionQueue[sessionIndex]
    }

    func isStageUnlocked(_ stageId: String) -> Bool {
        guard let profile else { return stageId == stages.first?.id }
        if profile.stagesCleared.contains(stageId) { return true }
        if profile.currentStageId == stageId { return true }
        // highest unlocked
        let order = stages.sorted { $0.order < $1.order }
        guard let highestIdx = order.firstIndex(where: { $0.id == profile.highestStageId }),
              let stageIdx = order.firstIndex(where: { $0.id == stageId }) else {
            return stageId == order.first?.id
        }
        return stageIdx <= highestIdx
    }

    func isStageCleared(_ stageId: String) -> Bool {
        profile?.stagesCleared.contains(stageId) == true
    }

    // MARK: - Load

    func load() {
        loadError = nil
        guard let language = LifePathPreferences.language else {
            self.language = nil
            showLanguagePicker = true
            stages = []
            entries = []
            listRowsByEntryId = [:]
            profile = nil
            return
        }
        showLanguagePicker = false
        self.language = language
        do {
            let file = try LifePathCatalog.loadList(language: language)
            stages = file.stages.sorted { $0.order < $1.order }
            entries = file.entries
            entriesById = Dictionary(uniqueKeysWithValues: file.entries.map { ($0.id, $0) })
            seedIfNeeded(language: language, file: file)
            reloadFromDB(language: language)
            restorePendingNotify()
            onLog?("Life Path loaded: \(language.listId) (\(entries.count) entries)")
        } catch {
            loadError = error.localizedDescription
            onLog?("Life Path load failed: \(loadError ?? "unknown")")
        }
    }

    func setLanguage(_ lang: LifePathLanguage) {
        LifePathPreferences.language = lang
        language = lang
        showLanguagePicker = false
        load()
    }

    func cancelLanguagePicker() {
        onRequestExit?()
    }

    /// DEV/testing only: wipe progress for the active language and clear language choice
    /// so the study-language picker is shown again.
    func resetProgressForTesting() {
        guard let language else { return }
        let cleared = language.rawValue
        endSession()
        showLevelUp = false
        pendingLevelUp = nil
        loadError = nil
        actionError = nil
        dbManager.resetLifePathProgress(language: cleared)
        listRowsByEntryId = [:]
        profile = nil
        stages = []
        entries = []
        entriesById = [:]
        // Clear chosen learning language so load() presents the picker.
        LifePathPreferences.language = nil
        self.language = nil
        load()
        onLog?("Life Path DEV reset for \(cleared) — language cleared, back to picker")
    }

    // MARK: - Play

    /// Starts a full-stage session: every unmastered word in the current life stage.
    /// Words that are not yet mastered are re-queued so the player can finish the stage in one go.
    func startRound() {
        guard let profile, language != nil else { return }
        let stageId = profile.currentStageId
        let pool = entries.filter { $0.stageId == stageId }
        let playable = pool.filter { entry in
            guard let row = listRowsByEntryId[entry.id] else { return false }
            return row.status == .available || row.status == .learning
        }
        let queue = playable.sorted { a, b in
            let ra = listRowsByEntryId[a.id]
            let rb = listRowsByEntryId[b.id]
            let da = ra?.dueAt ?? .distantPast
            let db = rb?.dueAt ?? .distantPast
            if da != db { return da < db }
            if a.rankInStage != b.rankInStage { return a.rankInStage < b.rankInStage }
            return (ra?.wrongCount ?? 0) > (rb?.wrongCount ?? 0)
        }
        guard !queue.isEmpty else {
            actionError = "No words left in this stage."
            return
        }
        sessionQueue = queue
        sessionIndex = 0
        sessionCorrect = 0
        sessionWrong = 0
        isAnswerRevealed = false
        sessionFinished = false
        isPlaying = true
        onLog?("Life Path stage session started (\(queue.count) unmastered cards in \(stageId))")
    }

    /// Cards still ahead in the current full-stage session (including current).
    var sessionRemainingCount: Int {
        max(0, sessionQueue.count - sessionIndex)
    }

    func revealAnswer() {
        isAnswerRevealed = true
    }

    func gradeCorrect() {
        grade(correct: true)
    }

    func gradeWrong() {
        grade(correct: false)
    }

    func endSession() {
        cancelPronunciationRecording()
        isPlaying = false
        sessionQueue = []
        sessionIndex = 0
        isAnswerRevealed = false
        sessionFinished = false
    }

    func dismissLevelUp() {
        guard var profile else {
            showLevelUp = false
            pendingLevelUp = nil
            return
        }
        profile.pendingNotifyJSON = nil
        profile.updatedAt = Date()
        dbManager.upsertLifePathProfile(profile)
        self.profile = profile
        showLevelUp = false
        pendingLevelUp = nil
    }

    // MARK: - Pronunciation Assessment

    /// When true, recording will auto-start for the current card after the host signals TTS finished.
    @Published private(set) var isWaitingToAutoRecord = false

    func triggerAutoRecordIfWaiting(for word: String) {
        guard isWaitingToAutoRecord, pronunciationState == .idle else { return }
        isWaitingToAutoRecord = false
        onLog?("Pronunciation: auto-record after TTS for '\(word)'")
        startPronunciationRecording(for: word)
    }

    func armAutoRecord() {
        guard pronunciationState == .idle else { return }
        isWaitingToAutoRecord = true
        onLog?("Pronunciation: armed (will record after TTS finishes)")
    }

    func startPronunciationRecording(for word: String) {
        guard pronunciationState == .idle || isFeedbackOrError else { return }
        pronunciationAutoGradeTask?.cancel()
        pronunciationAutoGradeTask = nil

        teardownPronunciationWS()
        pronunciationRecorder.stop()

        pronunciationTargetWord = word
        pronunciationAccumulatedData = Data()
        pronunciationWSReady = false
        pronunciationResultFromWS = false
        resetVAD()
        isWaitingToAutoRecord = false

        let endpoint = PronunciationEndpoint.resolvedAssessURL(pronunciationURLProvider?())
        if endpoint.isEmpty {
            onLog?("Pronunciation: ERROR — URL not configured (Settings → Endpoint Config)")
            pronunciationState = .error("Pronunciation URL not configured. Set it in Settings → Endpoint Config.")
            return
        }

        onLog?("Pronunciation: start word='\(word)' http=\(endpoint)")

        // Prefer streaming WebSocket for lower latency; HTTP POST remains the fallback.
        if let wsURL = PronunciationEndpoint.webSocketURL(from: endpoint) {
            onLog?("Pronunciation: streaming WS \(wsURL)")
            connectPronunciationWS(url: wsURL, targetWord: word)
        } else {
            onLog?("Pronunciation: no WS URL derived — will use HTTP POST on stop")
        }

        pronunciationState = .recording
        pronunciationRecorder.start()
        onLog?("Pronunciation: mic recording started for '\(word)'")
    }

    /// Tap-to-stop: ends capture and runs assessment (WS end frame or HTTP fallback).
    func stopPronunciationRecordingAndAssess() {
        guard case .recording = pronunciationState else { return }
        finalizeRecordingAndAssess(reason: "manual")
    }

    func cancelPronunciationRecording() {
        onLog?("Pronunciation: cancelled (state was \(String(describing: pronunciationState)))")
        pronunciationAutoGradeTask?.cancel()
        pronunciationAutoGradeTask = nil
        pronunciationRecorder.stop()
        teardownPronunciationWS()
        pronunciationAccumulatedData = Data()
        resetVAD()
        pronunciationState = .idle
        isWaitingToAutoRecord = false
    }

    func dismissPronunciationFeedback() {
        onLog?("Pronunciation: feedback dismissed")
        pronunciationAutoGradeTask?.cancel()
        pronunciationAutoGradeTask = nil
        teardownPronunciationWS()
        pronunciationState = .idle
        isWaitingToAutoRecord = false
    }

    private var isFeedbackOrError: Bool {
        switch pronunciationState {
        case .feedback, .error: return true
        default: return false
        }
    }

    private func resetVAD() {
        vadHeardSpeech = false
        vadSpeechSamples = 0
        vadSilenceSamples = 0
        vadTotalSamples = 0
    }

    private func handlePronunciationAudioChunk(_ data: Data) {
        guard case .recording = pronunciationState else { return }
        guard !data.isEmpty else { return }

        pronunciationAccumulatedData.append(data)
        if pronunciationWSReady {
            pronunciationAssessWS?.sendAudio(data: data)
        }

        // Energy VAD — stop after speech + silence, independent of correct recognition.
        let sampleCount = data.count / MemoryLayout<Float32>.size
        guard sampleCount > 0 else { return }
        let rms: Float = data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: Float32.self)
            var sum: Float = 0
            for i in 0..<sampleCount {
                let v = buf[i]
                sum += v * v
            }
            return sqrt(sum / Float(sampleCount))
        }

        vadTotalSamples += sampleCount
        if rms >= vadSpeechRMS {
            vadHeardSpeech = true
            vadSpeechSamples += sampleCount
            vadSilenceSamples = 0
        } else if vadHeardSpeech {
            vadSilenceSamples += sampleCount
        }

        let minSpeech = vadSampleRate * vadMinSpeechMs / 1000
        let silenceNeed = vadSampleRate * vadSilenceMs / 1000
        let maxSamples = vadSampleRate * vadMaxMs / 1000

        if vadTotalSamples >= maxSamples {
            onLog?("Pronunciation: max duration reached — auto-stopping")
            finalizeRecordingAndAssess(reason: "max_duration")
        } else if vadHeardSpeech && vadSpeechSamples >= minSpeech && vadSilenceSamples >= silenceNeed {
            onLog?("Pronunciation: silence after speech — auto-stopping")
            finalizeRecordingAndAssess(reason: "silence")
        }
    }

    private func finalizeRecordingAndAssess(reason: String) {
        guard case .recording = pronunciationState else { return }
        pronunciationRecorder.stop()
        pronunciationState = .assessing
        let bytes = pronunciationAccumulatedData.count
        let ms = bytes / (MemoryLayout<Float32>.size * 16) // 16 kHz float32 mono ≈ samples/ms
        onLog?(
            "Pronunciation: stop reason=\(reason) bytes=\(bytes) ~\(ms)ms speechDetected=\(vadHeardSpeech)"
        )

        // If WS session is live, ask server to score streamed audio (instant path).
        if pronunciationWSReady, let ws = pronunciationAssessWS, ws.isConnected {
            pronunciationResultFromWS = false
            onLog?("Pronunciation: sending WS end (awaiting result…)")
            ws.sendText("{\"type\":\"end\"}")
            // Safety: if WS never replies, fall back to HTTP after a short wait.
            let raw = pronunciationAccumulatedData
            let word = pronunciationTargetWord
            let endpoint = PronunciationEndpoint.resolvedAssessURL(pronunciationURLProvider?())
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self else { return }
                guard case .assessing = self.pronunciationState, !self.pronunciationResultFromWS else { return }
                self.onLog?("Pronunciation: WS timeout — falling back to HTTP POST")
                await self.runHTTPAssessment(audioData: raw, word: word, endpoint: endpoint)
            }
            return
        }

        // HTTP fallback (no WS or not ready)
        onLog?("Pronunciation: assessing via HTTP POST (WS not ready)")
        let raw = pronunciationAccumulatedData
        let word = pronunciationTargetWord
        let endpoint = PronunciationEndpoint.resolvedAssessURL(pronunciationURLProvider?())
        Task {
            await runHTTPAssessment(audioData: raw, word: word, endpoint: endpoint)
        }
    }

    private func connectPronunciationWS(url: String, targetWord: String) {
        let ws = WebSocketManager(urlString: url)
        pronunciationAssessWS = ws
        pronunciationWSReady = false

        ws.onLog = { [weak self] msg in
            self?.onLog?("Pronunciation WS: \(msg)")
        }
        ws.onError = { [weak self] err in
            Task { @MainActor in
                self?.onLog?("Pronunciation WS error: \(err)")
                // Stay recording — HTTP fallback will handle assess on stop.
                self?.pronunciationWSReady = false
            }
        }
        ws.onConnectionStateChange = { [weak self] connected in
            Task { @MainActor in
                guard let self else { return }
                if connected {
                    // Request debug metadata so logs show RMS / heard phonemes on device.
                    let payload = "{\"type\":\"start\",\"target_text\":\(Self.jsonString(targetWord)),\"debug\":true}"
                    ws.sendText(payload)
                } else {
                    self.pronunciationWSReady = false
                }
            }
        }
        ws.onMessageReceived = { [weak self] text in
            Task { @MainActor in
                self?.handlePronunciationWSMessage(text)
            }
        }
        ws.connect()
    }

    private func handlePronunciationWSMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            onLog?("Pronunciation WS: unparseable message: \(text.prefix(120))")
            return
        }

        switch type {
        case "ready":
            pronunciationWSReady = true
            onLog?("Pronunciation WS: ready")
            // Flush any audio already buffered before ready.
            if case .recording = pronunciationState, !pronunciationAccumulatedData.isEmpty {
                pronunciationAssessWS?.sendAudio(data: pronunciationAccumulatedData)
            }

        case "result":
            pronunciationResultFromWS = true
            do {
                let result = try JSONDecoder().decode(PronunciationAssessmentResponse.self, from: data)
                applyAssessmentResult(result)
            } catch {
                // `type` field is extra — strip and decode the rest if needed.
                if let result = decodeAssessmentFromWS(obj) {
                    applyAssessmentResult(result)
                } else {
                    pronunciationState = .error("Could not parse assessment result")
                    onLog?("Pronunciation WS decode error: \(error.localizedDescription)")
                }
            }

        case "error":
            let msg = obj["message"] as? String ?? "Assessment error"
            onLog?("Pronunciation WS server error: \(msg)")
            if case .assessing = pronunciationState {
                // Fall back to HTTP with whatever we captured.
                let raw = pronunciationAccumulatedData
                let word = pronunciationTargetWord
                let endpoint = PronunciationEndpoint.resolvedAssessURL(pronunciationURLProvider?())
                Task {
                    await runHTTPAssessment(audioData: raw, word: word, endpoint: endpoint)
                }
            }

        default:
            break
        }
    }

    private func decodeAssessmentFromWS(_ obj: [String: Any]) -> PronunciationAssessmentResponse? {
        var copy = obj
        copy.removeValue(forKey: "type")
        guard let data = try? JSONSerialization.data(withJSONObject: copy) else { return nil }
        return try? JSONDecoder().decode(PronunciationAssessmentResponse.self, from: data)
    }

    private func runHTTPAssessment(audioData: Data, word: String, endpoint: String) async {
        guard !endpoint.isEmpty else {
            onLog?("Pronunciation: ERROR — empty endpoint on HTTP assess")
            pronunciationState = .error("Pronunciation URL not configured. Set it in Settings → Endpoint Config.")
            return
        }
        if audioData.isEmpty {
            onLog?("Pronunciation: ERROR — no audio captured (0 bytes)")
            pronunciationState = .error("No audio captured — try speaking closer to the mic.")
            return
        }
        // Prefer WAV so any server version can decode via soundfile.
        let payload = Self.wrapFloat32PCMasWAV(audioData, sampleRate: 16000) ?? audioData
        onLog?("Pronunciation: HTTP POST word='\(word)' pcm=\(audioData.count)B wav=\(payload.count)B")
        do {
            let result = try await pronunciationAPIManager!.submitPronunciationAssessment(
                endpoint: endpoint,
                audioData: payload,
                targetWord: word
            )
            applyAssessmentResult(result)
        } catch {
            onLog?("Pronunciation: ERROR assess failed — \(error.localizedDescription)")
            pronunciationState = .error("Assessment failed: \(error.localizedDescription)")
        }
    }

    private func applyAssessmentResult(_ result: PronunciationAssessmentResponse) {
        teardownPronunciationWS()
        onLog?("Pronunciation: RESULT word='\(pronunciationTargetWord)' \(result.diagnosticSummary)")
        if !result.phonemes.isEmpty {
            let chips = result.phonemes.map { p in
                let mark = p.is_correct ? "✓" : "✗"
                return "\(p.grapheme):\(Int((p.score * 100).rounded()))%\(mark)"
            }.joined(separator: " ")
            onLog?("Pronunciation: phonemes \(chips)")
        }
        if let tip = result.feedback, !tip.isEmpty {
            onLog?("Pronunciation: feedback \"\(tip)\"")
        }
        pronunciationState = .feedback(result)

        // Instant learning loop: pass → auto-grade correct after a short celebration beat.
        if result.is_correct {
            pronunciationAutoGradeTask?.cancel()
            pronunciationAutoGradeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                guard let self, !Task.isCancelled else { return }
                guard case .feedback(let r) = self.pronunciationState, r.is_correct else { return }
                self.onLog?("Pronunciation: auto-grading correct → next card")
                self.pronunciationState = .idle
                self.gradeCorrect()
            }
        } else {
            onLog?("Pronunciation: not correct — waiting for Try Again or manual grade")
        }
    }

    private func teardownPronunciationWS() {
        pronunciationAssessWS?.disconnect()
        pronunciationAssessWS = nil
        pronunciationWSReady = false
    }

    private static func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    // MARK: - WAV encoding

    /// Wraps raw interleaved Float32 PCM samples (mono, 16 kHz) in a standard WAV/RIFF header.
    /// Returns nil if data is empty or would produce a malformed header.
    nonisolated static func wrapFloat32PCMasWAV(_ pcmData: Data, sampleRate: Int) -> Data? {
        guard !pcmData.isEmpty else { return nil }
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 32
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign: UInt16 = numChannels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize  // = fileSize - 8

        var wav = Data()
        // RIFF header
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian, Array.init))
        wav.append(contentsOf: Array("WAVE".utf8))
        // fmt  sub-chunk
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian,  Array.init)) // sub-chunk size
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian,   Array.init)) // PCM float = 3
        wav.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian,    Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian,  Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        // data sub-chunk
        wav.append(contentsOf: Array("data".utf8))
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        wav.append(pcmData)
        return wav
    }

    // MARK: - Private game logic

    private func grade(correct: Bool) {
        guard language != nil,
              let entry = currentCard,
              var row = listRowsByEntryId[entry.id],
              var profile else { return }

        let now = Date()
        let wasMastered = row.status == .mastered

        if correct {
            row.correctCount += 1
            row.correctStreak += 1
            if row.status != .mastered {
                row.status = .learning
            }
            sessionCorrect += 1

            if !wasMastered && row.correctStreak >= LifePathGame.masteryStreak {
                row.status = .mastered
                row.masteredAt = now
                row.correctStreak = LifePathGame.masteryStreak
                profile.totalMastered += 1
            }
            row.dueAt = now.addingTimeInterval(wasMastered || row.status == .mastered ? 86400 : 3600)
        } else {
            row.wrongCount += 1
            row.correctStreak = 0
            if row.status != .mastered {
                row.status = .learning
            } else {
                // Drop mastered back to learning on fail (gentle)
                row.status = .learning
                row.masteredAt = nil
                if profile.totalMastered > 0 {
                    profile.totalMastered -= 1
                }
            }
            sessionWrong += 1
            row.dueAt = now.addingTimeInterval(300)
        }

        row.lastReviewedAt = now
        row.updatedAt = now
        dbManager.upsertLifePathListRow(row)
        listRowsByEntryId[entry.id] = row

        profile.totalReviews += 1
        profile.updatedAt = now
        dbManager.upsertLifePathProfile(profile)
        self.profile = profile

        // Re-queue if not mastered so the player can clear the whole stage in one session.
        let stillNeedsPractice = listRowsByEntryId[entry.id]?.status != .mastered
        if stillNeedsPractice {
            let alreadyAhead = sessionQueue[(sessionIndex + 1)..<sessionQueue.count]
                .contains(where: { $0.id == entry.id })
            if !alreadyAhead {
                sessionQueue.append(entry)
            }
        }

        // Stage clear check before advancing card
        checkStageClear()

        // Level-up ends the session; do not advance further cards.
        if showLevelUp {
            isAnswerRevealed = false
            return
        }

        advanceOrFinish()
    }

    private func advanceOrFinish() {
        isAnswerRevealed = false
        // Drop mastered cards that were already past the cursor? keep simple: only advance.
        if sessionIndex + 1 < sessionQueue.count {
            sessionIndex += 1
            // Skip any cards that became mastered while waiting (shouldn't normally happen)
            while sessionIndex < sessionQueue.count {
                let id = sessionQueue[sessionIndex].id
                if listRowsByEntryId[id]?.status == .mastered {
                    sessionIndex += 1
                    continue
                }
                break
            }
            if sessionIndex >= sessionQueue.count {
                finishRound()
            }
        } else {
            finishRound()
        }
    }

    private func finishRound() {
        sessionFinished = true
        isPlaying = false
        onLog?("Life Path stage session finished correct=\(sessionCorrect) wrong=\(sessionWrong)")
    }

    private func checkStageClear() {
        guard let language,
              var profile,
              !profile.stagesCleared.contains(profile.currentStageId) else { return }

        let stageId = profile.currentStageId
        let stageEntries = entries.filter { $0.stageId == stageId }
        guard !stageEntries.isEmpty else { return }
        let allMastered = stageEntries.allSatisfy { listRowsByEntryId[$0.id]?.status == .mastered }
        guard allMastered else { return }

        let stageMeta = stages.first { $0.id == stageId }
        let next = LifePathGame.nextStage(after: stageId, available: stages)

        profile.stagesCleared.append(stageId)
        profile.updatedAt = Date()

        let toStageId = next?.id ?? stageId
        if let next {
            dbManager.unlockLifePathStage(language: language.rawValue, stageId: next.id)
            profile.currentStageId = next.id
            profile.highestStageId = next.id
        }

        let notify = LifePathLevelUpNotify(
            type: "stage_clear",
            fromStageId: stageId,
            toStageId: toStageId,
            title: [
                "en": "You grew up!",
                "zh": "你长大了！"
            ],
            body: [
                "en": next != nil
                    ? "\(stageMeta?.title(for: .en) ?? stageId) vocabulary complete. Welcome to \(next?.title(for: .en) ?? toStageId)!"
                    : "\(stageMeta?.title(for: .en) ?? stageId) vocabulary complete. You've finished the current path!",
                "zh": next != nil
                    ? "\(stageMeta?.title(for: .zh) ?? stageId) 词汇已掌握，欢迎进入\(next?.title(for: .zh) ?? toStageId)！"
                    : "\(stageMeta?.title(for: .zh) ?? stageId) 词汇已掌握，当前成长之路已全部通关！"
            ]
        )
        if let data = try? JSONEncoder().encode(notify),
           let json = String(data: data, encoding: .utf8) {
            profile.pendingNotifyJSON = json
        }

        dbManager.upsertLifePathProfile(profile)
        self.profile = profile
        reloadFromDB(language: language)
        pendingLevelUp = notify
        showLevelUp = true
        // Pause session if mid-round
        isPlaying = false
        sessionFinished = true
        onLog?("Life Path stage cleared: \(stageId) → \(toStageId)")
    }

    private func seedIfNeeded(language: LifePathLanguage, file: LifePathListFile) {
        let existing = dbManager.countLifePathList(language: language.rawValue)
        if existing == 0 {
            let now = Date()
            let firstStage = file.stages.sorted { $0.order < $1.order }.first?.id ?? "baby"
            for entry in file.entries {
                let status: LifePathWordStatus = entry.stageId == firstStage ? .available : .locked
                let row = LifePathListRow(
                    rowId: UUID().uuidString,
                    language: language.rawValue,
                    entryId: entry.id,
                    stageId: entry.stageId,
                    front: entry.front,
                    status: status,
                    correctCount: 0,
                    wrongCount: 0,
                    correctStreak: 0,
                    dueAt: nil,
                    lastReviewedAt: nil,
                    masteredAt: nil,
                    flashcardId: nil,
                    createdAt: now,
                    updatedAt: now
                )
                dbManager.insertLifePathListRow(row)
            }
            let profile = LifePathProfile(
                language: language.rawValue,
                currentStageId: firstStage,
                highestStageId: firstStage,
                xp: 0,
                coins: 0,
                lifetimeXp: 0,
                streakDays: 0,
                lastPlayDay: nil,
                totalReviews: 0,
                totalMastered: 0,
                stagesCleared: [],
                pendingNotifyJSON: nil,
                createdAt: now,
                updatedAt: now
            )
            dbManager.upsertLifePathProfile(profile)
            onLog?("Life Path seeded \(file.entries.count) words for \(language.rawValue)")
        } else {
            // Ensure profile exists
            if dbManager.fetchLifePathProfile(language: language.rawValue) == nil {
                let firstStage = file.stages.sorted { $0.order < $1.order }.first?.id ?? "baby"
                let now = Date()
                let profile = LifePathProfile(
                    language: language.rawValue,
                    currentStageId: firstStage,
                    highestStageId: firstStage,
                    xp: 0,
                    coins: 0,
                    lifetimeXp: 0,
                    streakDays: 0,
                    lastPlayDay: nil,
                    totalReviews: 0,
                    totalMastered: 0,
                    stagesCleared: [],
                    pendingNotifyJSON: nil,
                    createdAt: now,
                    updatedAt: now
                )
                dbManager.upsertLifePathProfile(profile)
            }
            // Seed any new catalog entries missing from DB (content updates)
            let existingRows = dbManager.fetchLifePathList(language: language.rawValue)
            let existingIds = Set(existingRows.map(\.entryId))
            let currentStage = dbManager.fetchLifePathProfile(language: language.rawValue)?.currentStageId
                ?? file.stages.sorted { $0.order < $1.order }.first?.id
            let cleared = Set(dbManager.fetchLifePathProfile(language: language.rawValue)?.stagesCleared ?? [])
            let highest = dbManager.fetchLifePathProfile(language: language.rawValue)?.highestStageId
            let now = Date()
            for entry in file.entries where !existingIds.contains(entry.id) {
                let unlocked = entry.stageId == currentStage
                    || cleared.contains(entry.stageId)
                    || entry.stageId == highest
                let row = LifePathListRow(
                    rowId: UUID().uuidString,
                    language: language.rawValue,
                    entryId: entry.id,
                    stageId: entry.stageId,
                    front: entry.front,
                    status: unlocked ? .available : .locked,
                    correctCount: 0,
                    wrongCount: 0,
                    correctStreak: 0,
                    dueAt: nil,
                    lastReviewedAt: nil,
                    masteredAt: nil,
                    flashcardId: nil,
                    createdAt: now,
                    updatedAt: now
                )
                dbManager.insertLifePathListRow(row)
            }
        }
    }

    private func reloadFromDB(language: LifePathLanguage) {
        profile = dbManager.fetchLifePathProfile(language: language.rawValue)
        let rows = dbManager.fetchLifePathList(language: language.rawValue)
        listRowsByEntryId = Dictionary(uniqueKeysWithValues: rows.map { ($0.entryId, $0) })
    }

    private func restorePendingNotify() {
        guard let json = profile?.pendingNotifyJSON,
              let data = json.data(using: .utf8),
              let notify = try? JSONDecoder().decode(LifePathLevelUpNotify.self, from: data) else {
            return
        }
        pendingLevelUp = notify
        showLevelUp = true
    }

}
