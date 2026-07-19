import Foundation
import AVFoundation
import Combine

// MARK: - Artifact / History

struct LifePathSongArtifact: Identifiable, Equatable {
    let id: UUID
    let lyrics: String
    let lines: [LRCLine]
    /// Under-lyric translations built from the vocab bank (aligned by line index).
    let glossLines: [LyricsGlossBuilder.GlossLine]
    let audioData: Data
    let duration: Double
    let usedFallbackLyrics: Bool
    let stageId: String
    let decade: Int
    let createdAt: Date
}

struct LifePathSongHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let stageId: String
    let language: String
    let lyrics: String
    let duration: Double
    let usedFallbackLyrics: Bool
    let audioFilename: String
    let contentFronts: [String]
}

// MARK: - Service

@MainActor
final class LifePathSongService: ObservableObject {

    enum Phase: Equatable {
        case idle
        case generatingLyrics
        case generatingMusic
        case ready(LifePathSongArtifact)
        case playing
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.generatingLyrics, .generatingLyrics),
                 (.generatingMusic, .generatingMusic),
                 (.playing, .playing):
                return true
            case (.ready(let a), .ready(let b)):
                return a.id == b.id
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    enum CancelReason: String {
        case endSession, levelUp, breakDismissed, newSession, supersededPrefetch, userEndedSession
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var activeLineIndex: Int = -1
    @Published private(set) var playbackProgress: Double = 0
    @Published private(set) var history: [LifePathSongHistoryItem] = []

    var llmURL: String = ""
    var llmModel: String = ""
    var onLog: ((String) -> Void)?

    private let musicClient: MusicAPIClient
    private let karaoke = KaraokePlayer()
    private var generateTask: Task<LifePathSongArtifact?, Never>?
    private var activeGenerationId: UUID?
    private var cachedDecade: Int?
    private var cachedArtifact: LifePathSongArtifact?
    private var generationIdByDecade: [Int: UUID] = [:]
    private var lastBankForRetry: LifePathSongBank.Bank?
    private var lastStageIdForRetry: String?
    private var lastRetryDecade: Int?
    private var karaokeCancellable: AnyCancellable?
    private var linesForHighlight: [LRCLine] = []

    init(musicClient: MusicAPIClient = MusicAPIClient(timeout: LifePathSongConfig.musicTimeout)) {
        self.musicClient = musicClient
        loadHistory()
        karaoke.onLog = { [weak self] msg in self?.onLog?(msg) }
        karaoke.onFinished = { [weak self] in
            Task { @MainActor in
                self?.handleKaraokeFinished()
            }
        }
        // Mirror karaoke time → active line
        karaokeCancellable = karaoke.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.syncHighlightFromKaraoke()
            }
        }
    }

    // MARK: - Generation id / cache

    func generationIdForDecade(_ decade: Int) -> UUID {
        if let existing = generationIdByDecade[decade] {
            return existing
        }
        let id = UUID()
        generationIdByDecade[decade] = id
        return id
    }

    func cancelAll(reason: CancelReason) {
        onLog?("[SONG] cancelAll reason=\(reason.rawValue)")
        generateTask?.cancel()
        generateTask = nil
        activeGenerationId = nil
        karaoke.stop()
        if reason == .newSession || reason == .endSession || reason == .userEndedSession || reason == .levelUp {
            generationIdByDecade.removeAll()
        }
        if case .playing = phase {
            phase = .idle
        } else if case .generatingLyrics = phase {
            phase = .idle
        } else if case .generatingMusic = phase {
            phase = .idle
        }
        // Keep .ready/.failed only if superseded without clear — clearInMemoryCache handles full reset
        if reason == .supersededPrefetch {
            cachedArtifact = nil
            cachedDecade = nil
            phase = .idle
        }
    }

    func clearInMemoryCache(reason: CancelReason) {
        onLog?("[SONG] clearInMemoryCache reason=\(reason.rawValue)")
        generateTask?.cancel()
        generateTask = nil
        cachedArtifact = nil
        cachedDecade = nil
        activeGenerationId = nil
        linesForHighlight = []
        activeLineIndex = -1
        playbackProgress = 0
        karaoke.stop()
        if reason == .newSession || reason == .endSession || reason == .userEndedSession || reason == .levelUp {
            generationIdByDecade.removeAll()
            lastBankForRetry = nil
            lastStageIdForRetry = nil
            lastRetryDecade = nil
        }
        phase = .idle
    }

    // MARK: - Prefetch / ensureReady

    func prefetch(
        bank: LifePathSongBank.Bank,
        stageId: String,
        decade: Int,
        generationId: UUID
    ) {
        lastBankForRetry = bank
        lastStageIdForRetry = stageId
        lastRetryDecade = decade

        if activeGenerationId == generationId, generateTask != nil {
            onLog?("[SONG] prefetch join existing generationId decade=\(decade)")
            return
        }
        if cachedDecade == decade, case .ready = phase {
            onLog?("[SONG] prefetch already ready decade=\(decade)")
            return
        }
        if generateTask != nil {
            cancelAll(reason: .supersededPrefetch)
        }
        activeGenerationId = generationId
        cachedDecade = decade
        startGenerateTask(bank: bank, stageId: stageId, generationId: generationId, decade: decade)
    }

    @discardableResult
    func ensureReady(
        bank: LifePathSongBank.Bank,
        stageId: String,
        decade: Int,
        generationId: UUID
    ) async -> LifePathSongArtifact? {
        lastBankForRetry = bank
        lastStageIdForRetry = stageId
        lastRetryDecade = decade

        // 1. Reuse Ready for same decade
        if case .ready(let art) = phase,
           cachedDecade == decade,
           cachedArtifact?.id == art.id {
            onLog?("[SONG] ensureReady reuse ready decade=\(decade)")
            return art
        }
        if let cached = cachedArtifact, cachedDecade == decade, cached.id == cachedArtifact?.id {
            phase = .ready(cached)
            return cached
        }

        // 2. Join in-flight for same generationId
        if let task = generateTask,
           activeGenerationId == generationId,
           cachedDecade == decade || cachedDecade == nil {
            onLog?("[SONG] ensureReady await in-flight decade=\(decade)")
            let art = await task.value
            if activeGenerationId != generationId { return nil }
            return art
        }

        // 3. Stale other decade
        if let cd = cachedDecade, cd != decade {
            clearInMemoryCache(reason: .supersededPrefetch)
        }

        // 4. Fresh generate
        if generateTask != nil {
            cancelAll(reason: .supersededPrefetch)
        }
        activeGenerationId = generationId
        cachedDecade = decade
        return await startGenerateTaskAndWait(
            bank: bank,
            stageId: stageId,
            generationId: generationId,
            decade: decade
        )
    }

    @discardableResult
    func retryGenerate() async -> LifePathSongArtifact? {
        guard let bank = lastBankForRetry,
              let stageId = lastStageIdForRetry,
              let decade = lastRetryDecade
        else {
            onLog?("[SONG] retryGenerate missing bank snapshot")
            return nil
        }
        let newId = UUID()
        generationIdByDecade[decade] = newId
        if generateTask != nil {
            cancelAll(reason: .supersededPrefetch)
        }
        activeGenerationId = newId
        cachedDecade = decade
        phase = .generatingLyrics
        onLog?("[SONG] retryGenerate new generationId decade=\(decade)")
        return await startGenerateTaskAndWait(
            bank: bank,
            stageId: stageId,
            generationId: newId,
            decade: decade
        )
    }

    // MARK: - Playback

    /// Start (or restart from the beginning). Resets karaoke highlight — do not keep
    /// a monotonic high-water index from a previous play-through.
    func play() {
        guard case .ready(let art) = phase else {
            if case .playing = phase {
                // Resume from pause without seeking; highlight continues from current time.
                karaoke.play()
            }
            return
        }
        do {
            resetHighlightState()
            try karaoke.load(data: art.audioData)
            linesForHighlight = art.lines
            phase = .playing
            karaoke.play()
            onLog?("[SONG] lp_song_play_started id=\(art.id.uuidString.prefix(8))")
        } catch {
            phase = .failed(error.localizedDescription)
            onLog?("[SONG] play load failed: \(error.localizedDescription)")
        }
    }

    func pause() {
        karaoke.pause()
    }

    func stopPlayback() {
        karaoke.stop()
        if case .playing = phase, let art = cachedArtifact {
            phase = .ready(art)
        }
        resetHighlightState()
    }

    /// Explicit restart from t=0 (Replay control).
    func replay() {
        guard let art = cachedArtifact else { return }
        karaoke.stop()
        phase = .ready(art)
        // play() resets highlight and reloads from the start
        play()
    }

    private func resetHighlightState() {
        activeLineIndex = -1
        playbackProgress = 0
    }

    var currentLines: [LRCLine] {
        if let art = cachedArtifact { return art.lines }
        if case .ready(let art) = phase { return art.lines }
        return linesForHighlight
    }

    /// Karaoke lines with under-lyric translations (preferred for UI).
    var currentGlossLines: [LyricsGlossBuilder.GlossLine] {
        if let art = cachedArtifact { return art.glossLines }
        if case .ready(let art) = phase { return art.glossLines }
        // Fallback: bare lyrics, no gloss (still building)
        return linesForHighlight.map {
            LyricsGlossBuilder.GlossLine(
                index: $0.index,
                time: $0.time,
                text: $0.text,
                translation: ""
            )
        }
    }

    var isKaraokePlaying: Bool { karaoke.isPlaying }

    var karaokeCurrentTime: TimeInterval { karaoke.currentTime }

    var karaokeDuration: TimeInterval { karaoke.duration }

    func restoreAudioSessionAfterSong() {
        karaoke.restorePlayAndRecordSession()
    }

    // MARK: - Generate pipeline

    private func startGenerateTask(
        bank: LifePathSongBank.Bank,
        stageId: String,
        generationId: UUID,
        decade: Int
    ) {
        generateTask = Task { [weak self] in
            await self?.runGenerate(
                bank: bank,
                stageId: stageId,
                generationId: generationId,
                decade: decade
            )
        }
    }

    private func startGenerateTaskAndWait(
        bank: LifePathSongBank.Bank,
        stageId: String,
        generationId: UUID,
        decade: Int
    ) async -> LifePathSongArtifact? {
        let task = Task { [weak self] in
            await self?.runGenerate(
                bank: bank,
                stageId: stageId,
                generationId: generationId,
                decade: decade
            )
        }
        generateTask = task
        return await task.value
    }

    private func runGenerate(
        bank: LifePathSongBank.Bank,
        stageId: String,
        generationId: UUID,
        decade: Int
    ) async -> LifePathSongArtifact? {
        guard !Task.isCancelled else { return nil }
        phase = .generatingLyrics
        onLog?("[SONG] generate start decade=\(decade) content=\(bank.contentWords.count)")

        var usedFallback = false
        var lrc: String
        var lines: [LRCLine]
        var validation: LRCValidationResult

        do {
            lrc = try await generateLyricsLLM(bank: bank)
            validation = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank)
            if !validation.isAcceptable, LifePathSongConfig.lyricsMaxRetries > 0 {
                onLog?("[SONG] lyrics validation failed ratio=\(String(format: "%.2f", validation.unknownRatio)) — retry")
                lrc = try await generateLyricsLLM(
                    bank: bank,
                    repairUnknowns: validation.unknownTokens
                )
                validation = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank)
            }
            if !validation.isAcceptable {
                onLog?("[SONG] lyrics fallback template usedFallbackLyrics=true")
                lrc = LRCParser.templateLyrics(words: bank.contentFronts)
                validation = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank)
                usedFallback = true
                // Clamp timestamps if still OOR
                if !validation.timestampsInRange {
                    lrc = LRCParser.templateLyrics(words: bank.contentFronts)
                    validation = LyricsAllowlistValidator.validate(lrc: lrc, bank: bank)
                }
            }
            lines = validation.lines
            if lines.isEmpty {
                lrc = LRCParser.templateLyrics(words: bank.contentFronts)
                lines = LRCParser.parse(lrc)
                usedFallback = true
            }
        } catch {
            if Task.isCancelled || error is CancellationError {
                return nil
            }
            onLog?("[SONG] lyrics LLM error — template fallback: \(error.localizedDescription)")
            lrc = LRCParser.templateLyrics(words: bank.contentFronts)
            lines = LRCParser.parse(lrc)
            usedFallback = true
        }

        guard !Task.isCancelled, activeGenerationId == generationId else { return nil }

        phase = .generatingMusic
        let stylePrompt: String
        switch bank.language {
        case .en: stylePrompt = LifePathSongConfig.stylePromptEN
        case .zh: stylePrompt = LifePathSongConfig.stylePromptZH
        }

        do {
            let request = MusicGenerateRequest(
                lyrics: lrc,
                prompt: stylePrompt,
                duration: LifePathSongConfig.songDurationSeconds,
                steps: LifePathSongConfig.diffusionSteps,
                genre: LifePathSongConfig.defaultGenre
            )
            onLog?("[SONG] music generate duration=\(LifePathSongConfig.songDurationSeconds)s")
            let response = try await musicClient.generate(request)
            guard !Task.isCancelled, activeGenerationId == generationId else { return nil }

            let glossLines = LyricsGlossBuilder.glossLines(for: lines, bank: bank)
            let artifact = LifePathSongArtifact(
                id: UUID(),
                lyrics: lrc,
                lines: lines,
                glossLines: glossLines,
                audioData: response.audioData,
                duration: LifePathSongConfig.songDurationSeconds,
                usedFallbackLyrics: usedFallback,
                stageId: stageId,
                decade: decade,
                createdAt: Date()
            )
            onGenerateSuccess(artifact, generationId: generationId, decade: decade, bank: bank)
            return artifact
        } catch {
            guard !Task.isCancelled, activeGenerationId == generationId else { return nil }
            let msg = error.localizedDescription
            phase = .failed(msg)
            onLog?("[SONG] music generate failed: \(msg)")
            return nil
        }
    }

    private func onGenerateSuccess(
        _ art: LifePathSongArtifact,
        generationId: UUID,
        decade: Int,
        bank: LifePathSongBank.Bank
    ) {
        guard activeGenerationId == generationId else {
            onLog?("[SONG] ignore late success generationId mismatch")
            return
        }
        cachedArtifact = art
        cachedDecade = decade
        phase = .ready(art)
        persistHistory(artifact: art, bank: bank)
        onLog?("[SONG] ready artifact=\(art.id.uuidString.prefix(8)) fallback=\(art.usedFallbackLyrics)")
    }

    // MARK: - LLM lyrics

    private func generateLyricsLLM(
        bank: LifePathSongBank.Bank,
        repairUnknowns: [String]? = nil
    ) async throws -> String {
        guard !llmURL.isEmpty else {
            throw NSError(
                domain: "LifePathSong",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "No text generation endpoint configured"]
            )
        }
        let prompt = buildLyricsPrompt(bank: bank, repairUnknowns: repairUnknowns)
        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]
        var requestBody: [String: Any] = [
            "messages": messages,
            "stream": false
        ]
        if !llmModel.isEmpty {
            requestBody["model"] = llmModel
        }

        guard let url = URL(string: llmURL) else {
            throw NSError(
                domain: "LifePathSong",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid LLM URL"]
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "LifePathSong",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
            )
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "LifePathSong",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"]
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw NSError(
                domain: "LifePathSong",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Could not parse LLM response"]
            )
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildLyricsPrompt(
        bank: LifePathSongBank.Bank,
        repairUnknowns: [String]?
    ) -> String {
        let duration = Int(LifePathSongConfig.songDurationSeconds)
        let contentJSON = jsonArray(bank.contentFronts)
        let glueJSON = jsonArray(bank.glueWords)
        let session = Array(bank.sessionFronts.prefix(LifePathSongConfig.maxSessionHighlightWords))
        let sessionJSON = jsonArray(session)
        let langCode = bank.language.rawValue
        let lineHint = bank.contentWords.count <= 12 ? "6" : "8-10"

        var repair = ""
        if let unknowns = repairUnknowns, !unknowns.isEmpty {
            let u = unknowns.prefix(20).joined(separator: ", ")
            repair = """

            REPAIR: Your previous lyrics used unknown tokens: \(u)
            Rewrite using ONLY the allowed content and glue lists. No other words.
            """
        }

        return """
        You write children's song lyrics for a language learner.

        LANGUAGE: \(langCode) — lyrics MUST be entirely in this language.
        DURATION: \(duration)s — space LRC timestamps from [00:02.00] across this duration
          (last line timestamp < \(duration)).

        ALLOWED CONTENT WORDS / PHRASES (use these as whole items when multi-word):
        \(contentJSON)

        ALLOWED GLUE / FUNCTION WORDS (grammar only):
        \(glueJSON)

        WORDS JUST PRACTICED (feature several):
        \(sessionJSON)

        RULES:
        1. Output ONLY LRC lines: [mm:ss.xx]lyric text
        2. \(lineHint) lines; each line short (EN ≤ 8 words; ZH ≤ 12 characters preferred)
        3. Multi-word allowlist items (e.g. "good morning") may appear as whole phrases
        4. Every content token/phrase must be in ALLOWED CONTENT or GLUE
        5. Prefer simple nursery / chant style; repetition OK
        6. No English if LANGUAGE=zh; no Chinese if LANGUAGE=en
        7. No markdown, titles, or commentary
        8. First timestamp ≥ 00:02.00; no timestamp ≥ \(duration)
        9. Child-safe: no brand names, no adult themes, no violence
        \(repair)
        Example format:
        [00:02.00]mama mama
        [00:04.00]baby ball
        """
    }

    private func jsonArray(_ strings: [String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: strings, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    // MARK: - Highlight / finish

    private func syncHighlightFromKaraoke() {
        let t = karaoke.currentTime
        let d = max(karaoke.duration, 0.001)
        playbackProgress = min(1, max(0, t / d))
        let lines = linesForHighlight.isEmpty ? currentLines : linesForHighlight
        let idx = karaoke.activeLineIndex(in: lines, at: t)
        // Track time directly. Do **not** use a high-water max across play-throughs:
        // that stuck the highlight on the last line after replay / auto-restart.
        // Within a single play, LRC times are ordered so idx only advances with t.
        activeLineIndex = idx
    }

    private func handleKaraokeFinished() {
        onLog?("[SONG] lp_song_played_to_end")
        // Leave highlight on last sung line; progress at 100%.
        // Phase → ready so UI shows Play again — BreakView must NOT auto-play on this
        // transition (that re-triggered play without a clean highlight reset).
        playbackProgress = 1
        if let art = cachedArtifact {
            phase = .ready(art)
        }
    }

    // MARK: - History (life_path_songs/)

    private var songsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DeveloperChatbot/life_path_songs")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private var historyJSONURL: URL {
        songsDir.appendingPathComponent("history.json")
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyJSONURL),
              let items = try? JSONDecoder().decode([LifePathSongHistoryItem].self, from: data)
        else { return }
        history = items
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyJSONURL)
    }

    private func persistHistory(artifact: LifePathSongArtifact, bank: LifePathSongBank.Bank) {
        let filename = "lp_song_\(Int(artifact.createdAt.timeIntervalSince1970))_\(artifact.id.uuidString.prefix(8)).wav"
        let url = songsDir.appendingPathComponent(filename)
        try? artifact.audioData.write(to: url)

        let item = LifePathSongHistoryItem(
            id: artifact.id,
            timestamp: artifact.createdAt,
            stageId: artifact.stageId,
            language: bank.language.rawValue,
            lyrics: artifact.lyrics,
            duration: artifact.duration,
            usedFallbackLyrics: artifact.usedFallbackLyrics,
            audioFilename: filename,
            contentFronts: Array(bank.contentFronts.prefix(20))
        )
        history.insert(item, at: 0)
        // Cap
        while history.count > LifePathSongConfig.historyLimit {
            if let last = history.popLast() {
                try? FileManager.default.removeItem(at: songsDir.appendingPathComponent(last.audioFilename))
            }
        }
        saveHistory()
    }
}
