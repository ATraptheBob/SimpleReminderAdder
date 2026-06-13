import Foundation
import Speech
import AVFoundation
import Accelerate
internal import Combine

protocol AudioEngineProtocol {
    var isRunning: Bool { get }
    func prepare()
    func start() throws
    func stop()
    func removeTap(onBus bus: AVAudioNodeBus)
    func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping AVAudioNodeTapBlock)
    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat
}

final class DefaultAudioEngine: AudioEngineProtocol {
    private let engine = AVAudioEngine()

    var isRunning: Bool { engine.isRunning }
    func prepare() { engine.prepare() }
    func start() throws { try engine.start() }
    func stop() { engine.stop() }

    func removeTap(onBus bus: AVAudioNodeBus) {
        engine.inputNode.removeTap(onBus: bus)
    }

    func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping AVAudioNodeTapBlock) {
        engine.inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: block)
    }

    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        return engine.inputNode.outputFormat(forBus: bus)
    }
}

/// Manages live on-device speech recognition for the quick-add input.
/// Exposes `isListening` and `transcript` for SwiftUI observation.
final class VoiceDictationManager: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript  = ""
    @Published var liveAmplitude: Float = 0.0
    
    private var manualPrefix = ""

    /// Fires when a final (or silence-timeout) transcript is committed.
    let onCommit = PassthroughSubject<String, Never>()

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    internal var audioEngine: AudioEngineProtocol = DefaultAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var currentSessionID = UUID()

    // MARK: - Public API

    func toggle(prefix: String = "") {
        isListening ? stopListening() : startListening(prefix: prefix)
    }

    func startListening(prefix: String = "") {
        guard !isListening else { return }

        // Check Speech Recognition authorization
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        
        // On macOS, we must also explicitly check and request microphone permissions via AVCaptureDevice
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        if speechStatus == .notDetermined || micStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                    DispatchQueue.main.async {
                        if status == .authorized && micGranted {
                            self?.beginSession(prefix: prefix)
                        } else {
                            print("Voice dictation requires both Speech Recognition and Microphone permissions.")
                        }
                    }
                }
            }
            return
        }

        if speechStatus == .authorized && micStatus == .authorized {
            beginSession(prefix: prefix)
        } else {
            print("Voice dictation requires both Speech Recognition and Microphone permissions.")
        }
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        liveAmplitude = 0.0

        // Commit whatever we have
        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty {
            onCommit.send(final)
        }
    }

    internal func _test_setIsListening(_ val: Bool) {
        isListening = val
    }

    func syncManualEdit(to newText: String) {
        guard isListening else { return }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        startRecognitionTask(prefix: newText, installTap: false)
    }

    func markTranscriptCommitted() {
        syncManualEdit(to: "")
    }

    // MARK: - Session

    private func beginSession(prefix: String) {
        isListening = true
        
        // Setup recognition request and tap (if needed) before starting the engine
        startRecognitionTask(prefix: prefix, installTap: !audioEngine.isRunning)
        
        if !audioEngine.isRunning {
            audioEngine.prepare()
            do {
                try audioEngine.start()
            } catch {
                cleanUp()
                return
            }
        }
    }
    
    private func startRecognitionTask(prefix: String, installTap: Bool) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        transcript = prefix
        manualPrefix = prefix

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device recognition when available (faster, private)
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }
        recognitionRequest = request
        
        if installTap {
            let recordingFormat = audioEngine.outputFormat(forBus: 0)
            
            guard recordingFormat.channelCount > 0, recordingFormat.sampleRate > 0 else {
                // Fail safely if hardware reports invalid format to avoid crashes or -10877 errors
                return
            }

            audioEngine.removeTap(onBus: 0) // Ensure no existing tap is conflicting
            audioEngine.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self else { return }
                self.recognitionRequest?.append(buffer)
            
            // Calculate Root Mean Square (RMS) of buffer for live visualization
            let frameCount = Int(buffer.frameLength)
            var rms: Float = 0.0

            if let channelData = buffer.floatChannelData?[0] {
                // ⚡ Bolt: Use Accelerate for vectorized RMS calculation
                // replacing manual looping which is slow on audio thread
                vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
            } else {
                var sum: Float = 0.0
                if let channelData = buffer.int16ChannelData?[0] {
                    for i in 0..<frameCount {
                        let sample = Float(channelData[i]) / 32768.0
                        sum += sample * sample
                    }
                } else if let channelData = buffer.int32ChannelData?[0] {
                    for i in 0..<frameCount {
                        let sample = Float(channelData[i]) / 2147483648.0
                        sum += sample * sample
                    }
                } else {
                    sum = Float.random(in: 0.01...0.05) * Float(frameCount)
                }
                rms = sqrt(sum / Float(max(1, frameCount)))
            }
            
            DispatchQueue.main.async {
                self.liveAmplitude = min(1.0, max(0.0, rms * 40.0))
            }
        }
        }

        let sessionID = UUID()
        self.currentSessionID = sessionID

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            guard self.currentSessionID == sessionID else { return }

            if let result {
                DispatchQueue.main.async {
                    let full = result.bestTranscription.formattedString
                    let trimmedNew = full.trimmingCharacters(in: .whitespaces)
                    
                    let combined: String
                    if self.manualPrefix.isEmpty {
                        combined = trimmedNew
                    } else {
                        combined = self.manualPrefix + (self.manualPrefix.hasSuffix(" ") || trimmedNew.isEmpty ? "" : " ") + trimmedNew
                    }
                    
                    self.transcript = combined
                }
            }

            if error != nil {
                DispatchQueue.main.async { self.stopListening() }
            }
        }
    }

    private func cleanUp() {
        audioEngine.stop()
        audioEngine.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        liveAmplitude = 0.0
    }
}
