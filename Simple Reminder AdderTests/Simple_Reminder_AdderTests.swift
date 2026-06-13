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

    func testParseRecurrence_Daily() throws {
        let text = "Remind me to exercise every day"
        let result = NaturalDateParser.parseRecurrence(text: text)
        XCTAssertNotNil(result, "Expected to parse 'every day'")
        XCTAssertEqual(result?.rule.frequency, .daily)
        XCTAssertEqual(result?.matchedSubstring.lowercased(), "every day")
    }

    func testParseRecurrence_Weekly() throws {
        let text = "Take out the trash every week"
        let result = NaturalDateParser.parseRecurrence(text: text)
        XCTAssertNotNil(result, "Expected to parse 'every week'")
        XCTAssertEqual(result?.rule.frequency, .weekly)
        XCTAssertEqual(result?.matchedSubstring.lowercased(), "every week")
    }

    func testParseRecurrence_Weekdays() throws {
        let text = "Standup meeting every weekday"
        let result = NaturalDateParser.parseRecurrence(text: text)
        XCTAssertNotNil(result, "Expected to parse 'every weekday'")
        XCTAssertEqual(result?.rule.frequency, .weekly)
        XCTAssertEqual(result?.rule.daysOfTheWeek?.count, 5)
        let days = result?.rule.daysOfTheWeek?.compactMap { $0.dayOfTheWeek }
        XCTAssertTrue(days?.contains(.monday) ?? false)
        XCTAssertTrue(days?.contains(.friday) ?? false)
        XCTAssertFalse(days?.contains(.saturday) ?? true)
    }

    func testParseRecurrence_Weekends() throws {
        let text = "Water the plants every weekend"
        let result = NaturalDateParser.parseRecurrence(text: text)
        XCTAssertNotNil(result, "Expected to parse 'every weekend'")
        XCTAssertEqual(result?.rule.frequency, .weekly)
        XCTAssertEqual(result?.rule.daysOfTheWeek?.count, 2)
        let days = result?.rule.daysOfTheWeek?.compactMap { $0.dayOfTheWeek }
        XCTAssertTrue(days?.contains(.saturday) ?? false)
        XCTAssertTrue(days?.contains(.sunday) ?? false)
    }

    func testParseRecurrence_SpecificDay() throws {
        let text = "Play tennis every Tuesday"
        let result = NaturalDateParser.parseRecurrence(text: text)
        XCTAssertNotNil(result, "Expected to parse 'every Tuesday'")
        XCTAssertEqual(result?.rule.frequency, .weekly)
        XCTAssertEqual(result?.rule.daysOfTheWeek?.count, 1)
        XCTAssertEqual(result?.rule.daysOfTheWeek?.first?.dayOfTheWeek, .tuesday)
    }

    func testParseRecurrence_CaseInsensitivity() throws {
        let text = "Buy groceries EVERY MONTH"
        let result = NaturalDateParser.parseRecurrence(text: text)
        XCTAssertNotNil(result, "Expected to parse 'EVERY MONTH'")
        XCTAssertEqual(result?.rule.frequency, .monthly)
        XCTAssertEqual(result?.matchedSubstring.lowercased(), "every month")
    }

    func testParseRecurrence_NoMatch() throws {
        let text = "Just a normal reminder without recurrence"
        let result = NaturalDateParser.parseRecurrence(text: text)
        XCTAssertNil(result, "Expected no recurrence to be found")
    }

}
