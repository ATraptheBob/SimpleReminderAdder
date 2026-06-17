import XCTest
@testable import Simple_Reminder_Adder

final class NaturalDateParserTests: XCTestCase {

    func testLooksLikeBareClockTime() {
        // True cases: Pure clock times
        XCTAssertTrue(NaturalDateParser.looksLikeBareClockTime("3pm"))
        XCTAssertTrue(NaturalDateParser.looksLikeBareClockTime("12:30"))
        XCTAssertTrue(NaturalDateParser.looksLikeBareClockTime("5 am"))
        XCTAssertTrue(NaturalDateParser.looksLikeBareClockTime("15"))
        XCTAssertTrue(NaturalDateParser.looksLikeBareClockTime("12:00 p.m."))
        XCTAssertTrue(NaturalDateParser.looksLikeBareClockTime(" 8:45 AM "))

        // False cases: Mixed with dates or specific days
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("3pm tomorrow"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("tomorrow 3pm"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("jan 5"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("3pm today"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("monday 3pm"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("next tuesday"))

        // False cases: Descriptive words and times of day
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("noon"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("midnight"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("midday"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("12:30 tonight"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("eod"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("this morning"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("this evening"))
        XCTAssertFalse(NaturalDateParser.looksLikeBareClockTime("this afternoon"))
    }
}
