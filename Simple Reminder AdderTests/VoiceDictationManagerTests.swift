//
//  VoiceDictationManagerTests.swift
//  Simple Reminder AdderTests
//

import XCTest
import AVFoundation
@testable import Simple_Reminder_Adder

class MockAudioEngine: AudioEngineProtocol {
    var isRunning: Bool = false
    var stopCalled = false
    var removeTapCalled = false

    func prepare() {}
    func start() throws {
        isRunning = true
    }

    func stop() {
        stopCalled = true
        isRunning = false
    }

    func removeTap(onBus bus: AVAudioNodeBus) {
        if bus == 0 {
            removeTapCalled = true
        }
    }

    func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping AVAudioNodeTapBlock) {
        // No-op for testing stopListening
    }

    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        return AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    }
}

final class VoiceDictationManagerTests: XCTestCase {

    func testStopListening_cleansUpEngineAndState() {
        // Arrange
        let manager = VoiceDictationManager()
        let mockEngine = MockAudioEngine()
        manager.audioEngine = mockEngine

        // Simulate that the manager is currently listening
        manager._test_setIsListening(true)
        manager.liveAmplitude = 0.8

        // Act
        manager.stopListening()

        // Assert
        XCTAssertTrue(mockEngine.stopCalled, "stop() should be called on the audio engine")
        XCTAssertTrue(mockEngine.removeTapCalled, "removeTap(onBus: 0) should be called on the audio engine")
        XCTAssertFalse(manager.isListening, "isListening should be set to false after stopping")
        XCTAssertEqual(manager.liveAmplitude, 0.0, "liveAmplitude should be reset to 0.0")
    }

}
