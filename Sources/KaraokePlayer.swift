import Foundation
import AVFoundation
import Combine

/// Position-aware audio player for karaoke lyric highlighting.
/// Does not replace shared `AudioPlayer` (chat TTS / simple playback).
@MainActor
final class KaraokePlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    var onFinished: (() -> Void)?
    var onLog: ((String) -> Void)?

    private var player: AVAudioPlayer?
    private var playerDelegate: KaraokePlayerDelegate?
    private var tickTimer: Timer?

    func load(data: Data) throws {
        stop()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif

        let delegate = KaraokePlayerDelegate(
            onFinish: { [weak self] in
                Task { @MainActor in
                    self?.handleFinished()
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.onLog?("[SONG] Karaoke decode error: \(error?.localizedDescription ?? "unknown")")
                    self?.handleFinished()
                }
            }
        )
        let p = try AVAudioPlayer(data: data)
        p.delegate = delegate
        p.prepareToPlay()
        player = p
        playerDelegate = delegate
        duration = p.duration
        currentTime = 0
        isPlaying = false
    }

    func play() {
        guard let player else { return }
        // If we already reached the end, restart from 0 so highlight/time re-sync.
        if player.currentTime >= max(0, player.duration - 0.05) || player.currentTime < 0 {
            player.currentTime = 0
            currentTime = 0
        }
        player.play()
        isPlaying = true
        startTicker()
        onLog?("[SONG] Karaoke playback started t=\(String(format: "%.2f", player.currentTime))")
    }

    /// Seek to start without releasing the player (used by explicit replay paths).
    func seekToStart() {
        player?.currentTime = 0
        currentTime = 0
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
        currentTime = player?.currentTime ?? currentTime
    }

    func stop() {
        stopTicker()
        player?.stop()
        player = nil
        playerDelegate = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    /// Largest index with `lines[i].time <= currentTime + 0.05`; -1 before first line.
    func activeLineIndex(in lines: [LRCLine], at time: TimeInterval? = nil) -> Int {
        let t = (time ?? currentTime) + 0.05
        var active = -1
        for line in lines {
            if line.time <= t {
                active = line.index
            } else {
                break
            }
        }
        return active
    }

    /// Restore Life Path / recorder-friendly session after song (iOS).
    func restorePlayAndRecordSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true)
        } catch {
            onLog?("[SONG] Failed to restore playAndRecord session: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Private

    private func handleFinished() {
        stopTicker()
        isPlaying = false
        if let player {
            currentTime = player.duration
        }
        onFinished?()
        onLog?("[SONG] Karaoke playback finished")
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying && self.isPlaying {
                    self.handleFinished()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicker() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}

private final class KaraokePlayerDelegate: NSObject, AVAudioPlayerDelegate {
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
