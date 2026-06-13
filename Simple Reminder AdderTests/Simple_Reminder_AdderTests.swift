//
//  Simple_Reminder_AdderTests.swift
//  Simple Reminder AdderTests
//
//  Created by Wilson Lee on 5/12/26.
//

import XCTest
@testable import Simple_Reminder_Adder

final class Simple_Reminder_AdderTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testParseLocation() {
        let tests: [(input: String, expectedTitle: String?, expectedIsArriving: Bool?, expectedMatch: String?)] = [
            ("remind me to buy milk when i arrive at home", "Home", true, "when i arrive at home"),
            ("upon arriving at work, call mom", "Work", true, "upon arriving at work"),
            ("on leaving school pickup kids", "School", false, "on leaving school"),
            ("leave from here", "Here", false, "leave from here"),
            ("arrive office", "Office", true, "arrive office"),
            ("leaving work", "Work", false, "leaving work"),
            ("just some normal text", nil, nil, nil)
        ]

        for test in tests {
            let result = NaturalDateParser.parseLocation(text: test.input)

            if let expectedTitle = test.expectedTitle {
                XCTAssertNotNil(result, "Expected match for '\\(test.input)'")
                XCTAssertEqual(result?.title, expectedTitle, "Title mismatch for '\\(test.input)'")
                XCTAssertEqual(result?.isArriving, test.expectedIsArriving, "isArriving mismatch for '\\(test.input)'")
                XCTAssertEqual(result?.matchedSubstring, test.expectedMatch, "matchedSubstring mismatch for '\\(test.input)'")
            } else {
                XCTAssertNil(result, "Expected no match for '\\(test.input)'")
            }
        }
    }

}
