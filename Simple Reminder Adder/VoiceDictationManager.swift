import Foundation
import Speech
import AVFoundation
internal import Combine

/// Manages live on-device speech recognition for the quick-add input.
/// Exposes `isListening` and `transcript` for SwiftUI observation.
final class VoiceDictationManager: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript  = ""
    @Published var liveAmplitude: Float = 0.0
    
    private var committedTranscript = ""
    private var currentFullTranscript = ""

    /// Fires when a final (or silence-timeout) transcript is committed.
    let onCommit = PassthroughSubject<String, Never>()

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine      = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    // MARK: - Public API

    func toggle() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        guard !isListening else { return }

        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        switch authStatus {
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    if status == .authorized { self?.beginSession() }
                }
            }
            return
        case .authorized:
            break
        default:
            // Denied / restricted — bail silently
            return
        }

        beginSession()
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
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

    func markTranscriptCommitted() {
        committedTranscript = currentFullTranscript
        transcript = ""
    }

    // MARK: - Session

    private func beginSession() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        transcript = ""
        committedTranscript = ""
        currentFullTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device recognition when available (faster, private)
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            
            // Calculate Root Mean Square (RMS) of buffer for live visualization
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0.0
            if let channelData = buffer.floatChannelData?[0] {
                for i in 0..<frameCount {
                    let sample = channelData[i]
                    sum += sample * sample
                }
            } else if let channelData = buffer.int16ChannelData?[0] {
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
            
            let rms = sqrt(sum / Float(max(1, frameCount)))
            DispatchQueue.main.async {
                self.liveAmplitude = min(1.0, max(0.0, rms * 40.0))
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cleanUp()
            return
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                DispatchQueue.main.async {
                    let full = result.bestTranscription.formattedString
                    self.currentFullTranscript = full
                    
                    var newText = full
                    if !self.committedTranscript.isEmpty {
                        if newText.lowercased().hasPrefix(self.committedTranscript.lowercased()) {
                            newText = String(newText.dropFirst(self.committedTranscript.count))
                        } else {
                            let committedWords = self.committedTranscript.split(separator: " ")
                            let fullWords = full.split(separator: " ")
                            if fullWords.count > committedWords.count {
                                newText = fullWords.dropFirst(committedWords.count).joined(separator: " ")
                            } else {
                                newText = ""
                            }
                        }
                    }
                    self.transcript = newText.trimmingCharacters(in: .whitespaces)
                }
            }

            if error != nil {
                DispatchQueue.main.async { self.stopListening() }
            }
        }
    }

    private func cleanUp() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        liveAmplitude = 0.0
    }
}
