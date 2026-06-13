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

    func testNaturalDateParserBasicInputs() throws {
        // Use a fixed reference date: Oct 10, 2023 at 12:00:00 UTC (Tuesday)
        let formatter = ISO8601DateFormatter()
        guard let referenceDate = formatter.date(from: "2023-10-10T12:00:00Z") else {
            XCTFail("Failed to create reference date")
            return
        }

        // Test "tomorrow"
        let tomorrowResult = NaturalDateParser.parse(text: "buy milk tomorrow", reference: referenceDate)
        XCTAssertTrue(tomorrowResult.hasDateComponent)
        // Tomorrow without time usually defaults to either false hasTimeComponent, or 9:00 based on default settings.
        // We'll primarily verify date parsing.
        XCTAssertNotNil(tomorrowResult.date)
        if let d = tomorrowResult.date {
            let cal = Calendar.current
            let isTomorrow = cal.isDate(d, inSameDayAs: cal.date(byAdding: .day, value: 1, to: referenceDate)!)
            XCTAssertTrue(isTomorrow, "Expected tomorrow's date")
        }

        // Test "in 2 days"
        let in2DaysResult = NaturalDateParser.parse(text: "call mom in 2 days", reference: referenceDate)
        XCTAssertNotNil(in2DaysResult.date)
        if let d = in2DaysResult.date {
            let cal = Calendar.current
            let expectedDay = cal.date(byAdding: .day, value: 2, to: referenceDate)!
            let isExpected = cal.isDate(d, inSameDayAs: expectedDay)
            XCTAssertTrue(isExpected, "Expected date 2 days from reference")
        }

        // Test "next friday"
        // Reference is Oct 10, 2023 (Tuesday). Next Friday should be Oct 13.
        let nextFridayResult = NaturalDateParser.parse(text: "meeting next friday", reference: referenceDate)
        XCTAssertNotNil(nextFridayResult.date)
        if let d = nextFridayResult.date {
            let cal = Calendar.current
            let weekday = cal.component(.weekday, from: d)
            XCTAssertEqual(weekday, 6, "Expected Friday (weekday 6)")
        }

        // Test "today at 5pm"
        let today5pmResult = NaturalDateParser.parse(text: "workout today at 5pm", reference: referenceDate)
        XCTAssertTrue(today5pmResult.hasDateComponent)
        XCTAssertTrue(today5pmResult.hasTimeComponent)
        XCTAssertNotNil(today5pmResult.date)
        if let d = today5pmResult.date {
            let cal = Calendar.current
            XCTAssertTrue(cal.isDate(d, inSameDayAs: referenceDate))
            let hour = cal.component(.hour, from: d)
            XCTAssertEqual(hour, 17, "Expected 17:00 (5pm)")
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
