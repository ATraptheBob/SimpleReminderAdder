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

    func testParseLocation() {
        // Arriving cases
        if let home = NaturalDateParser.parseLocation(text: "buy milk when i arrive at home") {
            XCTAssertEqual(home.title, "Home")
            XCTAssertTrue(home.isArriving)
            XCTAssertEqual(home.matchedSubstring, "when i arrive at home")
        } else {
            XCTFail("Expected to parse 'when i arrive at home'")
        }

        if let here = NaturalDateParser.parseLocation(text: "on arriving here") {
            XCTAssertEqual(here.title, "Here")
            XCTAssertTrue(here.isArriving)
            XCTAssertEqual(here.matchedSubstring, "on arriving here")
        } else {
            XCTFail("Expected to parse 'on arriving here'")
        }

        // Leaving cases
        if let office = NaturalDateParser.parseLocation(text: "leave office") {
            XCTAssertEqual(office.title, "Office")
            XCTAssertFalse(office.isArriving)
            XCTAssertEqual(office.matchedSubstring, "leave office")
        } else {
            XCTFail("Expected to parse 'leave office'")
        }

        if let school = NaturalDateParser.parseLocation(text: "upon leaving school") {
            XCTAssertEqual(school.title, "School")
            XCTAssertFalse(school.isArriving)
            XCTAssertEqual(school.matchedSubstring, "upon leaving school")
        } else {
            XCTFail("Expected to parse 'upon leaving school'")
        }

        // Mixed capitalization
        if let mixed = NaturalDateParser.parseLocation(text: "LEAVE Work") {
            XCTAssertEqual(mixed.title, "Work")
            XCTAssertFalse(mixed.isArriving)
            XCTAssertEqual(mixed.matchedSubstring, "LEAVE Work")
        } else {
            XCTFail("Expected to parse 'LEAVE Work'")
        }

        // Negative cases
        XCTAssertNil(NaturalDateParser.parseLocation(text: "buy milk tomorrow"))
        XCTAssertNil(NaturalDateParser.parseLocation(text: "arrive at the supermarket"))
        XCTAssertNil(NaturalDateParser.parseLocation(text: "just normal text"))
    }
}
