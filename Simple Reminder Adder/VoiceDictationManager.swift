import Foundation
import Speech
import AVFoundation
internal import Combine

/// Manages live on-device speech recognition for the quick-add input.
/// Exposes `isListening` and `transcript` for SwiftUI observation.
final class VoiceDictationManager: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript  = ""

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

        // Commit whatever we have
        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty {
            onCommit.send(final)
        }
    }

    func restartListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionTask = nil
        recognitionRequest = nil
        
        beginSession()
    }

    // MARK: - Session

    private func beginSession() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        transcript = ""

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
            self?.recognitionRequest?.append(buffer)
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
                    self.transcript = result.bestTranscription.formattedString
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
    }
}
