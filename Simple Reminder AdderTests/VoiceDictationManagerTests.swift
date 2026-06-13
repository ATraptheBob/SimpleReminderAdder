import XCTest
import Speech
import AVFoundation
@testable import Simple_Reminder_Adder

final class VoiceDictationManagerTests: XCTestCase {

    var manager: VoiceDictationManager!

    override func setUp() {
        super.setUp()
        manager = VoiceDictationManager()
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

    func testStartListening_whenDenied_doesNotBeginSession() {
        manager.speechAuthorizationStatus = { .denied }
        manager.micAuthorizationStatus = { .denied }

        manager.testDidBeginSession = { _ in
            XCTFail("Session should not begin if already denied")
        }

        manager.startListening(prefix: "test")

        XCTAssertFalse(manager.isListening)
    }
}
