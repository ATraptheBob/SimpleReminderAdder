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
    
    /// Set by the view when the user manually edits the text field (e.g. deletes text).
    /// While true, transcript updates are suppressed unless the new transcript is
    /// substantively longer, preventing stale partial results from overwriting user edits.
    var userDidEdit = false
    private var lastPublishedLength = 0
    
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
        lastPublishedLength = 0
        userDidEdit = false
    }

    // MARK: - Session

    private func beginSession() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        transcript = ""
        committedTranscript = ""
        currentFullTranscript = ""
        lastPublishedLength = 0
        userDidEdit = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device recognition when available (faster, private)
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.channelCount > 0 else {
            // Fail safely if hardware reports 0 channels to avoid crashes
            return
        }

        // On macOS, the input node must be connected to the main mixer node.
        // Otherwise, the audio graph may consider the input bus inactive or disconnected,
        // which causes a kAudioUnitErr_InvalidElement (-10877) when tapped.
        audioEngine.connect(inputNode, to: audioEngine.mainMixerNode, format: recordingFormat)
        audioEngine.mainMixerNode.outputVolume = 0.0

        inputNode.removeTap(onBus: 0) // Ensure no existing tap is conflicting
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
                    let trimmed = newText.trimmingCharacters(in: .whitespaces)
                    
                    // BUG FIX: If user manually edited (deleted text), only accept
                    // transcript updates that are genuinely new content (longer than
                    // what was last published). This prevents stale partial results
                    // from the recognizer from overwriting user deletions.
                    if self.userDidEdit {
                        if trimmed.count > self.lastPublishedLength {
                            self.userDidEdit = false
                            self.lastPublishedLength = trimmed.count
                            self.transcript = trimmed
                        }
                        // else: skip this stale update
                    } else {
                        self.lastPublishedLength = trimmed.count
                        self.transcript = trimmed
                    }
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
