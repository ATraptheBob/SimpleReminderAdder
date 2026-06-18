import XCTest
import Speech
import AVFoundation
@testable import Simple_Reminder_Adder

class MockAudioEngine: AudioEngineProtocol {
    var isRunning: Bool = false
    var didStop = false
    var removedTapBus: AVAudioNodeBus?

    func prepare() {}
    func start() throws { isRunning = true }
    func stop() {
        isRunning = false
        didStop = true
    }
    func removeTap(onBus bus: AVAudioNodeBus) {
        removedTapBus = bus
    }
    func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block: @escaping AVAudioNodeTapBlock) {}
    func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        return AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1)!
    }
}

final class VoiceDictationManagerTests: XCTestCase {

    var manager: VoiceDictationManager!
    var mockAudioEngine: MockAudioEngine!

    override func setUp() {
        super.setUp()
        manager = VoiceDictationManager()
        mockAudioEngine = MockAudioEngine()
        manager.audioEngine = mockAudioEngine
    }

    func testStartListening_whenAuthorized_beginsSession() {
        manager.speechAuthorizationStatus = { .authorized }
        manager.micAuthorizationStatus = { .authorized }

        let expectation = self.expectation(description: "Session should begin")
        manager.testDidBeginSession = { prefix in
            XCTAssertEqual(prefix, "test")
            expectation.fulfill()
        }

        manager.startListening(prefix: "test")

        waitForExpectations(timeout: 1.0, handler: nil)
        XCTAssertTrue(manager.isListening)
    }

    func testStartListening_whenNotDetermined_requestsAccess_andBeginsSessionIfGranted() {
        manager.speechAuthorizationStatus = { .notDetermined }
        manager.micAuthorizationStatus = { .notDetermined }

        manager.requestSpeechAuthorization = { completion in
            completion(.authorized)
        }
        manager.requestMicAccess = { completion in
            completion(true)
        }

        let expectation = self.expectation(description: "Session should begin after access granted")
        manager.testDidBeginSession = { prefix in
            XCTAssertEqual(prefix, "test")
            expectation.fulfill()
        }

        manager.startListening(prefix: "test")

        waitForExpectations(timeout: 1.0, handler: nil)
        XCTAssertTrue(manager.isListening)
    }

    func testStartListening_whenNotDetermined_requestsAccess_andDoesNotBeginSessionIfDenied() {
        manager.speechAuthorizationStatus = { .notDetermined }
        manager.micAuthorizationStatus = { .notDetermined }

        manager.requestSpeechAuthorization = { completion in
            completion(.denied)
        }
        manager.requestMicAccess = { completion in
            completion(true)
        }

        manager.testDidBeginSession = { _ in
            XCTFail("Session should not begin if speech authorization is denied")
        }

        manager.startListening(prefix: "test")

        let expectation = self.expectation(description: "Wait for dispatch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertFalse(manager.isListening)
    }

    func testStartListening_whenNotDetermined_requestsAccess_andDoesNotBeginSessionIfMicDenied() {
        manager.speechAuthorizationStatus = { .notDetermined }
        manager.micAuthorizationStatus = { .notDetermined }

        manager.requestSpeechAuthorization = { completion in
            completion(.authorized)
        }
        manager.requestMicAccess = { completion in
            completion(false)
        }

        manager.testDidBeginSession = { _ in
            XCTFail("Session should not begin if mic authorization is denied")
        }

        manager.startListening(prefix: "test")

        let expectation = self.expectation(description: "Wait for dispatch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertFalse(manager.isListening)
    }

    func testStartListening_whenSpeechAuthorizedButMicDenied_doesNotBeginSession() {
        manager.speechAuthorizationStatus = { .authorized }
        manager.micAuthorizationStatus = { .denied }

        manager.testDidBeginSession = { _ in
            XCTFail("Session should not begin if mic is denied")
        }

        manager.startListening(prefix: "test")

        XCTAssertFalse(manager.isListening)
    }

    func testStartListening_whenAlreadyListening_returnsEarly() {
        manager.speechAuthorizationStatus = { .authorized }
        manager.micAuthorizationStatus = { .authorized }

        // Simulate already listening
        manager.testDidBeginSession = { _ in }
        manager.startListening(prefix: "first")

        XCTAssertTrue(manager.isListening)

        manager.testDidBeginSession = { _ in
            XCTFail("Session should not begin again if already listening")
        }

        manager.startListening(prefix: "second")
    }

    func testStartListening_whenDenied_doesNotBeginSession() {
        manager.speechAuthorizationStatus = { .denied }
        manager.micAuthorizationStatus = { .denied }

        manager.testDidBeginSession = { _ in
            XCTFail("Session should not begin if already denied")
        }

        manager.startListening(prefix: "test")

        XCTAssertFalse(manager.isListening)
    }

    func testCleanUp_stopsEngineAndResetsState() {
        // Arrange
        manager.liveAmplitude = 0.5
        mockAudioEngine.isRunning = true

        // Act
        manager.cleanUp()

        // Assert
        XCTAssertTrue(mockAudioEngine.didStop)
        XCTAssertEqual(mockAudioEngine.removedTapBus, 0)
        XCTAssertFalse(manager.isListening)
        XCTAssertEqual(manager.liveAmplitude, 0.0)
    }
}
