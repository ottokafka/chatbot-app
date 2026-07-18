import Foundation
import AVFoundation
import SwiftUI

// MARK: - Music API Models

struct MusicGenerateRequest: Codable {
    let lyrics: String?
    let prompt: String?
    let duration: Double
    let steps: Int
    let genre: String?
}

// MARK: - Song History

struct SongHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let topic: String
    let lyrics: String
    let duration: Double
    let steps: Int
    let genre: String
    let audioFilename: String   // relative filename inside songs/ dir

    var displayTitle: String {
        let t = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 40 { return t }
        return String(t.prefix(40)) + "..."
    }

    var displayGenre: String {
        genre.isEmpty ? "auto" : genre
    }
}

// MARK: - Song Generation ViewModel

@MainActor
final class SongGenViewModel: ObservableObject {

    // MARK: Published state

    /// User's description of the song they want
    @Published var songTopic: String = "" {
        didSet { UserDefaults.standard.set(songTopic, forKey: Self.topicKey) }
    }

    /// Generated or manually entered LRC-formatted lyrics
    @Published var lyrics: String = ""

    /// Audio data of the generated song
    @Published var generatedAudioData: Data?

    /// Status flags
    @Published var isGeneratingLyrics = false
    @Published var isGeneratingMusic = false
    @Published var isPlaying = false
    @Published var errorMessage: String?

    /// Music generation settings
    @Published var duration: Double = 10.0
    @Published var steps: Int = 32
    @Published var genre: String = ""  // empty = auto-detect

    /// Generation history
    @Published var history: [SongHistoryItem] = []

    /// Music generation API endpoint
    @Published var musicAPIURL: String {
        didSet { UserDefaults.standard.set(musicAPIURL, forKey: Self.musicURLKey) }
    }

    /// LLM endpoint (injected from ChatViewModel, not persisted here)
    var llmURL: String = ""
    var llmModel: String = ""

    /// Log callback
    var onLog: ((String) -> Void)?

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var playerDelegate: SongAudioPlayerDelegate?
    private static let topicKey = "songGen.topic.v1"
    private static let musicURLKey = "songGen.musicURL.v1"

    /// Available genres for the picker
    static let genres: [String] = [
        "rock", "rnb", "jazz", "blues", "pop",
        "hip hop", "country", "folk", "electronic", "metal",
        "reggae", "funk", "latin", "soul", "disco",
        "lofi", "classical", "ambient", "cinematic"
    ]

    init() {
        self.musicAPIURL = UserDefaults.standard.string(forKey: Self.musicURLKey)
            ?? "https://song.npro.ai"
        self.songTopic = UserDefaults.standard.string(forKey: Self.topicKey) ?? ""
        loadHistory()
    }

    // MARK: - History Persistence

    private var songsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DeveloperChatbot/songs")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private var historyJSONURL: URL {
        songsDir.appendingPathComponent("history.json")
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyJSONURL),
              let items = try? JSONDecoder().decode([SongHistoryItem].self, from: data)
        else { return }
        history = items
        onLog?("[SongGen] Loaded \(items.count) history items")
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyJSONURL)
    }

    private func wavURL(for item: SongHistoryItem) -> URL {
        songsDir.appendingPathComponent(item.audioFilename)
    }

    /// Load WAV data for a history item from disk
    func audioData(for item: SongHistoryItem) -> Data? {
        try? Data(contentsOf: wavURL(for: item))
    }

    /// Restore state from a history item (lyrics, settings, audio)
    func selectHistoryItem(_ item: SongHistoryItem) {
        stopAudio()
        songTopic = item.topic
        lyrics = item.lyrics
        duration = item.duration
        steps = item.steps
        genre = item.genre
        generatedAudioData = audioData(for: item)
        errorMessage = nil
    }

    /// Delete a history item and its WAV file
    func deleteHistoryItem(_ item: SongHistoryItem) {
        // If currently viewing this item, clear loaded state
        if let current = generatedAudioData,
           let loaded = audioData(for: item),
           current == loaded {
            stopAudio()
            generatedAudioData = nil
        }
        try? FileManager.default.removeItem(at: wavURL(for: item))
        history.removeAll { $0.id == item.id }
        saveHistory()
    }

    /// Clear all history
    func clearAllHistory() {
        stopAudio()
        generatedAudioData = nil
        for item in history {
            try? FileManager.default.removeItem(at: wavURL(for: item))
        }
        history.removeAll()
        saveHistory()
    }

    // MARK: - Lyrics Generation

    func generateLyrics() async {
        guard !songTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a song description"
            return
        }
        guard !llmURL.isEmpty else {
            errorMessage = "No text generation endpoint configured"
            return
        }

        isGeneratingLyrics = true
        errorMessage = nil

        let prompt = buildLyricsPrompt(for: songTopic)

        let messages: [[String: Any]] = [
            ["role": "user", "content": prompt]
        ]

        let requestBody: [String: Any] = [
            "messages": messages,
            "stream": false
        ]

        do {
            guard let url = URL(string: llmURL) else {
                throw NSError(domain: "SongGen", code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid LLM URL"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            onLog?("[SongGen] Requesting lyrics from LLM: \(llmURL)")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "SongGen", code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "SongGen", code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])
            }

            // Parse OpenAI-compatible response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                lyrics = content.trimmingCharacters(in: .whitespacesAndNewlines)
                onLog?("[SongGen] Lyrics generated (\(lyrics.count) chars)")
            } else {
                throw NSError(domain: "SongGen", code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Could not parse LLM response"])
            }
        } catch {
            errorMessage = error.localizedDescription
            onLog?("[SongGen] Lyrics generation error: \(error.localizedDescription)")
        }

        isGeneratingLyrics = false
    }

    /// Build the prompt to instruct the LLM to produce LRC-formatted lyrics
    private func buildLyricsPrompt(for topic: String) -> String {
        let genreHint = genre.isEmpty ? "" : " in the \(genre) genre"

        return """
        You are a songwriter. Write song lyrics in LRC format based on the following description.
        Match the language of the description — if the user writes in Chinese, output Chinese lyrics; if English, output English lyrics.

        Description: \(topic)\(genreHint)

        IMPORTANT RULES:
        - Write 8-16 lines of lyrics in the same language as the description
        - Use LRC format: [mm:ss.xx]Lyric text (Chinese characters are fully supported)
        - Start the first line at [00:02.00] or later (leave intro space)
        - Space timestamps evenly across \(Int(duration)) seconds
        - Do NOT output anything besides the LRC lyrics — no explanations, no markdown, no commentary
        - Make the lyrics creative, natural, and appropriate for a song
        - Each lyric line should be one short phrase or sentence

        English example:
        [00:02.00]I woke up this morning with fire in my soul
        [00:07.00]Got my guitar ready, ready to roll
        [00:12.00]The stage is calling, I hear the crowd
        [00:16.00]Gonna turn it up, gonna make it loud

        Chinese example (中文歌词示例):
        [00:02.00]清晨的阳光洒满了窗台
        [00:06.00]微风轻轻吹过你的发梢
        [00:11.00]我们一起走过的每条街道
        [00:16.00]留下了属于我们的美好回忆

        Now write the LRC lyrics:
        """
    }

    // MARK: - Music Generation

    func generateMusic() async {
        guard !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please generate or enter lyrics first"
            return
        }

        isGeneratingMusic = true
        errorMessage = nil
        generatedAudioData = nil

        let request = MusicGenerateRequest(
            lyrics: lyrics,
            prompt: songTopic,
            duration: duration,
            steps: steps,
            genre: genre.isEmpty ? nil : genre
        )

        do {
            guard let url = URL(string: "\(musicAPIURL)/music/generate") else {
                throw NSError(domain: "SongGen", code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid Music API URL"])
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(request)
            urlRequest.timeoutInterval = 120

            onLog?("[SongGen] Requesting music: \(musicAPIURL)/music/generate " +
                   "(duration: \(duration)s, steps: \(steps))")

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "SongGen", code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "SongGen", code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"])
            }

            // Validate WAV header
            guard data.count > 44, isWAVData(data) else {
                throw NSError(domain: "SongGen", code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Response is not valid WAV audio"])
            }

            generatedAudioData = data
            let genTime = httpResponse.value(forHTTPHeaderField: "X-Generation-Time") ?? "?"
            onLog?("[SongGen] Music generated: \(data.count) bytes, gen time: \(genTime)s")

            // Save to history
            let item = SongHistoryItem(
                id: UUID(),
                timestamp: Date(),
                topic: songTopic,
                lyrics: lyrics,
                duration: duration,
                steps: steps,
                genre: genre,
                audioFilename: "song_\(Int(Date().timeIntervalSince1970)).wav"
            )
            try? data.write(to: wavURL(for: item))
            history.insert(item, at: 0)
            saveHistory()
            onLog?("[SongGen] Saved to history (\(history.count) items)")

        } catch {
            errorMessage = error.localizedDescription
            onLog?("[SongGen] Music generation error: \(error.localizedDescription)")
        }

        isGeneratingMusic = false
    }

    /// Quick check for RIFF WAV header
    private func isWAVData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46])  // "RIFF"
    }

    // MARK: - Playback

    func playAudio() {
        guard let data = generatedAudioData else { return }
        stopAudio()

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            #endif

            playerDelegate = SongAudioPlayerDelegate(
                onFinish: { [weak self] in
                    Task { @MainActor in
                        self?.isPlaying = false
                        self?.audioPlayer = nil
                        self?.playerDelegate = nil
                        self?.onLog?("[SongGen] Playback finished")
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.isPlaying = false
                        self?.audioPlayer = nil
                        self?.playerDelegate = nil
                        self?.onLog?("[SongGen] Decode error: \(error?.localizedDescription ?? "unknown")")
                    }
                }
            )

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = playerDelegate
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
            onLog?("[SongGen] Playback started")
        } catch {
            onLog?("[SongGen] Playback failed: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        playerDelegate = nil
        isPlaying = false
    }

    // MARK: - Save

    #if os(macOS)
    func saveSong() {
        guard let data = generatedAudioData else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "song_\(Int(Date().timeIntervalSince1970)).wav"

        panel.begin { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                    self.onLog?("[SongGen] Saved to \(url.path)")
                } catch {
                    self.onLog?("[SongGen] Save failed: \(error.localizedDescription)")
                }
            }
        }
    }
    #else
    func saveSong() {
        // On iOS, song data is available via generatedAudioData;
        // sharing/saving would be wired through a share sheet in production.
        onLog?("[SongGen] Save not available on this platform")
    }
    #endif
}

// MARK: - AVAudioPlayer Delegate Helper

/// Helper that acts as AVAudioPlayerDelegate (requires NSObject conformance).
private final class SongAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    let onError: (Error?) -> Void

    init(onFinish: @escaping () -> Void, onError: @escaping (Error?) -> Void) {
        self.onFinish = onFinish
        self.onError = onError
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onError(error)
    }
}
