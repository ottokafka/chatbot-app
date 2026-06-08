import Foundation
import AVFoundation

class AudioRecorder: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    private var isRecording = false
    private let targetFormat: AVAudioFormat
    
    var onAudioData: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onLog: ((String) -> Void)?
    
    init() {
        // Target is 16kHz, mono, Float32 PCM
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            fatalError("AudioRecorder: Failed to create target AVAudioFormat")
        }
        self.targetFormat = format
    }
    
    func checkPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    func start() {
        guard !isRecording else { return }
        
        checkPermission { [weak self] granted in
            guard let self = self else { return }
            if !granted {
                self.onError?("Microphone permission denied.")
                return
            }
            
            self.startRecording()
        }
    }
    
    private func startRecording() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        onLog?("AudioRecorder: Starting recording. Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels.")
        
        // Setup converter from inputFormat to targetFormat
        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        if audioConverter == nil {
            onLog?("AudioRecorder: Failed to create AVAudioConverter.")
            onError?("Failed to create audio converter.")
            return
        }
        
        // Use a buffer size that makes sense (e.g. 1024 or 4096 samples)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let converter = self.audioConverter else { return }
            
            // Calculate necessary output frame capacity
            let sampleRateRatio = inputFormat.sampleRate / self.targetFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) / sampleRateRatio) + 16
            
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) else {
                self.onLog?("AudioRecorder: Failed to allocate output buffer.")
                return
            }
            
            var error: NSError?
            var inputBufferWasUsed = false
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                if inputBufferWasUsed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                inputBufferWasUsed = true
                return buffer
            }
            
            if status == .error {
                if let err = error {
                    self.onLog?("AudioRecorder: Conversion error: \(err.localizedDescription)")
                }
                return
            }
            
            // Extract the Float32 samples from outputBuffer
            if let channelData = outputBuffer.floatChannelData?[0] {
                let frameLength = Int(outputBuffer.frameLength)
                let byteCount = frameLength * MemoryLayout<Float32>.size
                let data = Data(bytes: channelData, count: byteCount)
                if byteCount > 0 {
                    self.onAudioData?(data)
                }
            }
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            onLog?("AudioRecorder: Audio engine started, tap installed.")
        } catch {
            onLog?("AudioRecorder: Failed to start audioEngine: \(error.localizedDescription)")
            onError?("Failed to start audio engine: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        guard isRecording else { return }
        onLog?("AudioRecorder: Stopping recording.")
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
    }
}
