import Foundation
import AVFoundation

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    
    var onPlaybackFinished: (() -> Void)?
    var onPlaybackStarted: (() -> Void)?
    var onLog: ((String) -> Void)?
    
    func play(data: Data) {
        stop()
        
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            onLog?("AudioPlayer: Failed to configure AVAudioSession for playback: \(error.localizedDescription)")
        }
        #endif
        
        onLog?("AudioPlayer: Initializing playback for audio data size \(data.count) bytes.")
        
        do {
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.prepareToPlay()
            
            onPlaybackStarted?()
            player?.play()
            onLog?("AudioPlayer: Playback started successfully.")
        } catch {
            onLog?("AudioPlayer: Failed to initialize AVAudioPlayer: \(error.localizedDescription)")
            onPlaybackFinished?()
        }
    }
    
    func stop() {
        if let p = player, p.isPlaying {
            onLog?("AudioPlayer: Stopping playback.")
            p.stop()
        }
        player = nil
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onLog?("AudioPlayer: Playback finished (success: \(flag)).")
        onPlaybackFinished?()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let errMsg = error?.localizedDescription ?? "Unknown error"
        onLog?("AudioPlayer: Decode error occurred during playback: \(errMsg)")
        onPlaybackFinished?()
    }
}
