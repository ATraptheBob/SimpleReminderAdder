import Foundation
import EventKit

struct NaturalDateParseResult: Equatable {
    var date: Date?
    var matchedSubstring: String?
    var hasDateComponent: Bool
    var hasTimeComponent: Bool
}

enum NaturalDateParser {

    // ────────────────────────────────────────────────────────────
    // MARK: - Configurable time-of-day defaults
    // ────────────────────────────────────────────────────────────
    //
    // Reads user preferences from UserDefaults (set via SettingsView).
    // Falls back to the original hardcoded defaults if no custom value is stored.

    static func timeForDayPart(_ name: String) -> (hour: Int, minute: Int) {
        let defaults = UserDefaults.standard
        switch name.lowercased() {
        case "morning":
            let h = defaults.object(forKey: "timeMorningHour")   as? Int ?? 9
            let m = defaults.object(forKey: "timeMorningMinute") as? Int ?? 0
            return (h, m)
        case "afternoon":
            let h = defaults.object(forKey: "timeAfternoonHour")   as? Int ?? 14
            let m = defaults.object(forKey: "timeAfternoonMinute") as? Int ?? 0
            return (h, m)
        case "evening":
            let h = defaults.object(forKey: "timeEveningHour")   as? Int ?? 19
            let m = defaults.object(forKey: "timeEveningMinute") as? Int ?? 0
            return (h, m)
        case "night":
            let h = defaults.object(forKey: "timeNightHour")   as? Int ?? 21
            let m = defaults.object(forKey: "timeNightMinute") as? Int ?? 0
            return (h, m)
        default:
            return (9, 0)
        }
    }

    // ────────────────────────────────────────────────────────────
    // MARK: - Pre-compiled regexes (created once, reused on every keystroke)
    // ────────────────────────────────────────────────────────────

    private struct LexicalPattern {
        let regex: NSRegularExpression
        let builder: (Date, Calendar) -> NaturalDateParseResult
    }

    // NOTE: Patterns that reference morning/afternoon/evening/night now call
    // timeForDayPart() at parse-time so they pick up user-customized values.
    private static let lexicalPatterns: [LexicalPattern] = {
        func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

        return [
            LexicalPattern(regex: re(#"(?i)\bday after tomorrow\b"#))       { now, cal in
                let m = timeForDayPart("morning")
                return dayAfterTomorrowAt(hour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\btomorrow morning\b"#))         { now, cal in
                let m = timeForDayPart("morning")
                return tomorrowAt(hour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\btomorrow afternoon\b"#))       { now, cal in
                let a = timeForDayPart("afternoon")
                return tomorrowAt(hour: a.hour, minute: a.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\btomorrow evening\b"#))         { now, cal in
                let e = timeForDayPart("evening")
                return tomorrowAt(hour: e.hour, minute: e.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\btomorrow\b"#))                 { now, cal in
                let m = timeForDayPart("morning")
                return tomorrowAt(hour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\bthis evening\b"#))             { now, cal in thisEveningResult(reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\btonight\b"#))                  { now, cal in tonightResult(reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\bthis afternoon\b"#))           { now, cal in
                let a = timeForDayPart("afternoon")
                return dayPartResult(reference: now, cal: cal, hour: a.hour, minute: a.minute)
            },
            LexicalPattern(regex: re(#"(?i)\bthis morning\b"#))             { now, cal in
                let m = timeForDayPart("morning")
                return dayPartResult(reference: now, cal: cal, hour: m.hour, minute: m.minute)
            },
            LexicalPattern(regex: re(#"(?i)\bthis weekend\b"#))             { now, cal in weekendResult(offsetWeeks: 0, reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\bnext weekend\b"#))             { now, cal in weekendResult(offsetWeeks: 1, reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\bnext week\b"#))                { now, cal in
                let m = timeForDayPart("morning")
                return offsetDays(7, atHour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\bnext month\b"#))               { now, cal in
                let m = timeForDayPart("morning")
                return offsetMonths(1, atHour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\bnext year\b"#))                { now, cal in
                let m = timeForDayPart("morning")
                return offsetYears(1, atHour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\bend of day\b"#))               { now, cal in todayAt(hour: 17, minute: 0, reference: now, cal: cal, rollForwardIfPast: true) },
            LexicalPattern(regex: re(#"(?i)\beod\b"#))                      { now, cal in todayAt(hour: 17, minute: 0, reference: now, cal: cal, rollForwardIfPast: true) },
            LexicalPattern(regex: re(#"(?i)\bclose of business\b"#))        { now, cal in fridaySameWeekAt(hour: 17, minute: 0, reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\bcob\b"#))                      { now, cal in fridaySameWeekAt(hour: 17, minute: 0, reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\bend of week\b"#))              { now, cal in fridaySameWeekAt(hour: 17, minute: 0, reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\bend of month\b"#))             { now, cal in endOfMonthResult(reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\bmidday\b"#))                   { now, cal in todayAt(hour: 12, minute: 0, reference: now, cal: cal, rollForwardIfPast: true) },
            LexicalPattern(regex: re(#"(?i)\bnoon\b"#))                     { now, cal in todayAt(hour: 12, minute: 0, reference: now, cal: cal, rollForwardIfPast: true) },
            LexicalPattern(regex: re(#"(?i)\bmidnight\b"#))                 { now, cal in endOfToday(reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\blater today\b"#))              { now, cal in offsetHours(4, reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\blater\b"#))                    { now, cal in offsetHours(4, reference: now, cal: cal) },
            LexicalPattern(regex: re(#"(?i)\bin a week\b"#))                { now, cal in
                let m = timeForDayPart("morning")
                return offsetDays(7, atHour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\bin a month\b"#))               { now, cal in
                let m = timeForDayPart("morning")
                return offsetMonths(1, atHour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
            LexicalPattern(regex: re(#"(?i)\bin a year\b"#))                { now, cal in
                let m = timeForDayPart("morning")
                return offsetYears(1, atHour: m.hour, minute: m.minute, reference: now, cal: cal)
            },
        ]
    }()

    private static let nextWeekdayRegex = try! NSRegularExpression(
        pattern: #"(?i)\bnext\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
    )
    private static let bareWeekdayRegex = try! NSRegularExpression(
        pattern: #"(?i)(?<!next )\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
    )

    // Recurrence & Location Regexes
    private static let recurrenceRegex = try! NSRegularExpression(
        pattern: #"(?i)\bevery\s+(day|week|month|year|weekday|weekend|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#
    )
    
    private static let locationRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(?:when i |upon |on )?(arrive|arriving|leave|leaving)(?:\s+at|\s+from)?\s+(home|work|school|here|office)\b"#
    )

    // ⚡ Bolt: Cache NSDataDetector since its initialization is very expensive
    // and this parser is called repeatedly on every keystroke.
    private static let sharedDateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    // ⚡ Bolt: Pre-compile regexes for parseDetector and looksLikeBareClockTime
    // because constructing NSRegularExpression repeatedly is slow.
    private static let bareClockTimeRegex = try! NSRegularExpression(
        pattern: #"^\d{1,2}\s*(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)?$"#,
        options: [.caseInsensitive]
    )
    private static let timeWithPeriodRegex = try! NSRegularExpression(
        pattern: #"\d{1,2}\s*(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)"#,
        options: [.caseInsensitive]
    )
    private static let atSymbolTimeRegex = try! NSRegularExpression(
        pattern: #"\b(at|@)\s*\d"#,
        options: [.caseInsensitive]
    )
    private static let monthsAndDaysShortRegex = try! NSRegularExpression(
        pattern: #"mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"#,
        options: []
    )

    // Regexes for hasExplicitCalendarDay
    private static let weekdaysRegex = try! NSRegularExpression(
        pattern: #"mon(day)?|tue(sday)?|wed(nesday)?|thu(rsday)?|fri(day)?|sat(urday)?|sun(day)?"#,
        options: []
    )
    private static let dateNumericRegex = try! NSRegularExpression(
        pattern: #"\d{1,2}[/\-]\d{1,2}([/\-]\d{2,4})?"#,
        options: []
    )
    private static let monthsShortRegex = try! NSRegularExpression(
        pattern: #"jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"#,
        options: []
    )

    // Relative-time patterns — pre-compiled
    private struct FuzzyPattern {
        let regex: NSRegularExpression
        let offset: (Date, Calendar) -> Date?
    }
    private static let fuzzyPatterns: [FuzzyPattern] = {
        func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
        return [
            FuzzyPattern(regex: re(#"(?i)\bin\s+a\s+couple\s+of\s+hours?\b"#)) { now, cal in cal.date(byAdding: .hour, value: 2, to: now) },
            FuzzyPattern(regex: re(#"(?i)\bin\s+a\s+few\s+hours?\b"#))         { now, cal in cal.date(byAdding: .hour, value: 3, to: now) },
            FuzzyPattern(regex: re(#"(?i)\bin\s+half\s+an?\s+hour\b"#))        { now, cal in cal.date(byAdding: .minute, value: 30, to: now) },
            FuzzyPattern(regex: re(#"(?i)\bin\s+an?\s+hour\b"#))               { now, cal in cal.date(byAdding: .hour, value: 1, to: now) },
        ]
    }()
    private static let numericRelativeRegex = try! NSRegularExpression(
        pattern: #"(?i)\bin\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*(hours?|hrs?|h\b|minutes?|mins?|m\b|days?|d\b|weeks?|w\b|months?|years?|y\b)\b"#
    )

    // ────────────────────────────────────────────────────────────
    // MARK: - Public
    // ────────────────────────────────────────────────────────────

    static func parse(text: String, reference now: Date = Date()) -> NaturalDateParseResult {
        var best: NaturalDateParseResult?

        if let r = parseLexicalPhrases(text: text, reference: now) {
            best = r
        }

        if let r = parseRelative(text: text, reference: now) {
            if best == nil || (r.matchedSubstring?.count ?? 0) > (best?.matchedSubstring?.count ?? 0) {
                best = r
            }
        }

        if let r = parseDetector(text: text) {
            if best == nil || (r.matchedSubstring?.count ?? 0) > (best?.matchedSubstring?.count ?? 0) {
                best = r
            }
        }

        return best ?? NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
    }

    static func parseRecurrence(text: String) -> (rule: EKRecurrenceRule, matchedSubstring: String)? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = recurrenceRegex.firstMatch(in: text, options: [], range: full),
              let r = Range(m.range, in: text) else { return nil }
        
        let matchStr = String(text[r])
        let unitRaw = ns.substring(with: m.range(at: 1)).lowercased()
        
        var freq: EKRecurrenceFrequency = .daily
        var daysOfTheWeek: [EKRecurrenceDayOfWeek]? = nil
        
        switch unitRaw {
        case "day": freq = .daily
        case "week": freq = .weekly
        case "month": freq = .monthly
        case "year": freq = .yearly
        case "weekday":
            freq = .weekly
            daysOfTheWeek = [
                EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.tuesday),
                EKRecurrenceDayOfWeek(.wednesday), EKRecurrenceDayOfWeek(.thursday),
                EKRecurrenceDayOfWeek(.friday)
            ]
        case "weekend":
            freq = .weekly
            daysOfTheWeek = [EKRecurrenceDayOfWeek(.saturday), EKRecurrenceDayOfWeek(.sunday)]
        case "monday":
            freq = .weekly; daysOfTheWeek = [EKRecurrenceDayOfWeek(.monday)]
        case "tuesday":
            freq = .weekly; daysOfTheWeek = [EKRecurrenceDayOfWeek(.tuesday)]
        case "wednesday":
            freq = .weekly; daysOfTheWeek = [EKRecurrenceDayOfWeek(.wednesday)]
        case "thursday":
            freq = .weekly; daysOfTheWeek = [EKRecurrenceDayOfWeek(.thursday)]
        case "friday":
            freq = .weekly; daysOfTheWeek = [EKRecurrenceDayOfWeek(.friday)]
        case "saturday":
            freq = .weekly; daysOfTheWeek = [EKRecurrenceDayOfWeek(.saturday)]
        case "sunday":
            freq = .weekly; daysOfTheWeek = [EKRecurrenceDayOfWeek(.sunday)]
        default:
            freq = .daily
        }
        
        let rule = EKRecurrenceRule(
            recurrenceWith: freq,
            interval: 1,
            daysOfTheWeek: daysOfTheWeek,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
        
        return (rule, matchStr)
    }

    static func parseLocation(text: String) -> (title: String, isArriving: Bool, matchedSubstring: String)? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = locationRegex.firstMatch(in: text, options: [], range: full),
              let r = Range(m.range, in: text) else { return nil }
        
        let matchStr = String(text[r])
        let actionRaw = ns.substring(with: m.range(at: 1)).lowercased()
        let placeRaw = ns.substring(with: m.range(at: 2))
        
        let isArriving = actionRaw.contains("arrive") || actionRaw.contains("arriving")
        return (placeRaw.capitalized, isArriving, matchStr)
    }

    // MARK: - Lexical phrases (tonight, eod, weekdays, …)

    private static func parseLexicalPhrases(text: String, reference now: Date) -> NaturalDateParseResult? {
        let cal = Calendar.current
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var best: NaturalDateParseResult?

        func take(_ range: Range<String.Index>, _ template: NaturalDateParseResult) {
            guard let d = template.date else { return }
            let sub = String(text[range])
            let cand = NaturalDateParseResult(
                date: d,
                matchedSubstring: sub,
                hasDateComponent: template.hasDateComponent,
                hasTimeComponent: template.hasTimeComponent
            )
            let len = sub.count
            if best == nil || len > (best?.matchedSubstring?.count ?? 0) {
                best = cand
            }
        }

        // Iterate pre-compiled patterns (no regex compilation per call)
        for entry in lexicalPatterns {
            guard let m = entry.regex.firstMatch(in: text, options: [], range: full),
                  let r = Range(m.range, in: text) else { continue }
            take(r, entry.builder(now, cal))
        }

        if let m = nextWeekdayRegex.firstMatch(in: text, options: [], range: full),
           let r = Range(m.range, in: text) {
            let w = ns.substring(with: m.range(at: 1)).lowercased()
            if let wd = weekdayIndex(from: w),
               let d = nextWeekdayAfterNextWeekStart(wd, reference: now, cal: cal) {
                take(r, NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: false))
            }
        }

        if let m = bareWeekdayRegex.firstMatch(in: text, options: [], range: full),
           let r = Range(m.range, in: text) {
            let w = ns.substring(with: m.range(at: 1)).lowercased()
            if let wd = weekdayIndex(from: w),
               let d = nextWeekdayInclusive(wd, after: now, cal: cal) {
                take(r, NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: false))
            }
        }

        return best
    }

    private static func weekdayIndex(from word: String) -> Int? {
        switch word.lowercased() {
        case "sunday": return 1
        case "monday": return 2
        case "tuesday": return 3
        case "wednesday": return 4
        case "thursday": return 5
        case "friday": return 6
        case "saturday": return 7
        default: return nil
        }
    }

    private static func nextWeekdayInclusive(_ weekday: Int, after now: Date, cal: Calendar) -> Date? {
        var c = DateComponents()
        c.weekday = weekday
        return cal.nextDate(after: now, matching: c, matchingPolicy: .nextTime, direction: .forward)
    }

    /// "Next Monday" → first occurrence of that weekday after the current `weekOfYear` interval ends.
    private static func nextWeekdayAfterNextWeekStart(_ weekday: Int, reference now: Date, cal: Calendar) -> Date? {
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return nil }
        var c = DateComponents()
        c.weekday = weekday
        return cal.nextDate(after: week.end, matching: c, matchingPolicy: .nextTime, direction: .forward)
    }

    private static func tonightResult(reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        let n = timeForDayPart("night")
        return dayPartResult(reference: now, cal: cal, hour: n.hour, minute: n.minute)
    }

    private static func thisEveningResult(reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        let e = timeForDayPart("evening")
        return dayPartResult(reference: now, cal: cal, hour: e.hour, minute: e.minute)
    }

    private static func dayPartResult(reference now: Date, cal: Calendar, hour: Int, minute: Int) -> NaturalDateParseResult {
        todayAt(hour: hour, minute: minute, reference: now, cal: cal, rollForwardIfPast: true)
    }

    private static func todayAt(hour: Int, minute: Int, reference now: Date, cal: Calendar, rollForwardIfPast: Bool) -> NaturalDateParseResult {
        let base = cal.startOfDay(for: now)
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        guard var d = cal.date(byAdding: dc, to: base) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        if rollForwardIfPast && d <= now, let tomorrow = cal.date(byAdding: .day, value: 1, to: base) {
            d = cal.date(byAdding: dc, to: tomorrow) ?? d
        }
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func tomorrowAt(hour: Int, minute: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        let start = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: start) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let d = cal.date(byAdding: dc, to: cal.startOfDay(for: tomorrow))
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func dayAfterTomorrowAt(hour: Int, minute: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        let start = cal.startOfDay(for: now)
        guard let day = cal.date(byAdding: .day, value: 2, to: start) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let d = cal.date(byAdding: dc, to: cal.startOfDay(for: day))
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func offsetDays(_ days: Int, atHour hour: Int, minute: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        guard let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let d = cal.date(byAdding: dc, to: cal.startOfDay(for: day))
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func offsetMonths(_ months: Int, atHour hour: Int, minute: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        guard let day = cal.date(byAdding: .month, value: months, to: cal.startOfDay(for: now)) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let d = cal.date(byAdding: dc, to: cal.startOfDay(for: day))
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func offsetYears(_ years: Int, atHour hour: Int, minute: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        guard let day = cal.date(byAdding: .year, value: years, to: cal.startOfDay(for: now)) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let d = cal.date(byAdding: dc, to: cal.startOfDay(for: day))
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func offsetHours(_ hours: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        guard let d = cal.date(byAdding: .hour, value: hours, to: now) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: true)
    }

    private static func weekendResult(offsetWeeks: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        comps.weekday = 7 // Saturday
        guard var target = cal.date(from: comps) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        if target < now {
            target = cal.date(byAdding: .weekOfYear, value: 1, to: target) ?? target
        }
        if offsetWeeks > 0 {
            target = cal.date(byAdding: .weekOfYear, value: offsetWeeks, to: target) ?? target
        }
        var dc = DateComponents()
        dc.hour = 9
        dc.minute = 0
        // BUG FIX: normalize to startOfDay before adding hours, preventing double-hour stacking
        let d = cal.date(byAdding: dc, to: cal.startOfDay(for: target))
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func endOfMonthResult(reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        guard let monthInterval = cal.dateInterval(of: .month, for: now),
              let lastDay = cal.date(byAdding: .day, value: -1, to: monthInterval.end) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        var dc = DateComponents()
        dc.hour = 17
        dc.minute = 0
        let d = cal.date(byAdding: dc, to: cal.startOfDay(for: lastDay))
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func fridaySameWeekAt(hour: Int, minute: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        comps.weekday = 6
        guard var target = cal.date(from: comps) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        if target < now, let nextF = cal.date(byAdding: .weekOfYear, value: 1, to: target) {
            var c2 = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextF)
            c2.weekday = 6
            target = cal.date(from: c2) ?? target
        }
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let d = cal.date(byAdding: dc, to: cal.startOfDay(for: target))
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func endOfToday(reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        let start = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: start),
              let d = cal.date(byAdding: .second, value: -1, to: tomorrow) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func parseDetector(text: String) -> NaturalDateParseResult? {
        guard let detector = sharedDateDetector else { return nil }
        let ns = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard let match = matches.first, let date = match.date, let baseRange = Range(match.range, in: text) else { return nil }

        var finalDateString = String(text[baseRange])
        let textBefore = text[text.startIndex..<baseRange.lowerBound]
        let wordsBefore = textBefore.components(separatedBy: .whitespaces)
        if let lastWord = wordsBefore.last(where: { !$0.isEmpty })?.lowercased(),
           ["at", "on", "by", "for", "due", "until", "before"].contains(lastWord) {
            let escapedDate = NSRegularExpression.escapedPattern(for: finalDateString)
            let escapedLastWord = NSRegularExpression.escapedPattern(for: lastWord)
            let searchPattern = "(?i)\\b\(escapedLastWord)\\s+\(escapedDate)"
            if let fullRange = text.range(of: searchPattern, options: .regularExpression) {
                finalDateString = String(text[fullRange])
            }
        }

        let dc = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hasNonZeroClock = (dc.hour ?? 0) != 0 || (dc.minute ?? 0) != 0
        let finalNs = finalDateString as NSString
        let fullFinal = NSRange(location: 0, length: finalNs.length)
        let hasTime = match.timeZone != nil
            || hasNonZeroClock
            || timeWithPeriodRegex.firstMatch(in: finalDateString, range: fullFinal) != nil
            || atSymbolTimeRegex.firstMatch(in: finalDateString, range: fullFinal) != nil

        let explicitCal = hasExplicitCalendarDay(in: finalDateString)
        let hasDateComponent = explicitCal || !looksLikeBareClockTime(finalDateString)
        let hasTimeComponent = hasTime || finalDateString.lowercased().contains(" at ")

        return NaturalDateParseResult(
            date: date,
            matchedSubstring: finalDateString,
            hasDateComponent: hasDateComponent,
            hasTimeComponent: hasTimeComponent
        )
    }

    private static func looksLikeBareClockTime(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.contains("tomorrow") || t.contains("today") || t.contains("next ") { return false }
        if t.contains("tonight") || t.contains("this evening") || t.contains("this morning") || t.contains("this afternoon") { return false }
        if t.contains("eod") || t.contains("noon") || t.contains("midnight") || t.contains("midday") { return false }

        let ns = t as NSString
        let full = NSRange(location: 0, length: ns.length)
        if monthsAndDaysShortRegex.firstMatch(in: t, range: full) != nil { return false }
        return bareClockTimeRegex.firstMatch(in: t, range: full) != nil
    }

    private static func hasExplicitCalendarDay(in s: String) -> Bool {
        let t = s.lowercased()
        if t.contains("today") || t.contains("next ") { return true }
        if t.contains("tonight") || t.contains("this evening") || t.contains("this morning") || t.contains("this afternoon") { return true }
        if t.contains("tomorrow") || t.contains("day after tomorrow") { return true }
        if t.contains("eod") || t.contains("end of day") || t.contains("cob") || t.contains("close of business") { return true }
        if t.contains("noon") || t.contains("midday") || t.contains("midnight") { return true }

        let ns = t as NSString
        let full = NSRange(location: 0, length: ns.length)
        if weekdaysRegex.firstMatch(in: t, range: full) != nil { return true }
        if dateNumericRegex.firstMatch(in: t, range: full) != nil { return true }
        if monthsShortRegex.firstMatch(in: t, range: full) != nil { return true }
        return false
    }

    private static func parseRelative(text: String, reference now: Date) -> NaturalDateParseResult? {
        let cal = Calendar.current
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Pre-compiled fuzzy patterns
        for entry in fuzzyPatterns {
            guard let m = entry.regex.firstMatch(in: text, options: [], range: full),
                  let r = Range(m.range, in: text),
                  let d = entry.offset(now, cal) else { continue }
            return NaturalDateParseResult(date: d, matchedSubstring: String(text[r]), hasDateComponent: false, hasTimeComponent: true)
        }

        // Pre-compiled numeric relative regex
        guard let m = numericRelativeRegex.firstMatch(in: text, range: full),
              let r = Range(m.range, in: text) else { return nil }

        guard m.numberOfRanges >= 3 else { return nil }
        let numRaw = ns.substring(with: m.range(at: 1)).lowercased()
        let n: Int
        if let val = Int(numRaw) {
            n = val
        } else {
            switch numRaw {
            case "one": n = 1
            case "two": n = 2
            case "three": n = 3
            case "four": n = 4
            case "five": n = 5
            case "six": n = 6
            case "seven": n = 7
            case "eight": n = 8
            case "nine": n = 9
            case "ten": n = 10
            case "eleven": n = 11
            case "twelve": n = 12
            default: return nil
            }
        }
        guard n > 0 else { return nil }

        let unitRaw = ns.substring(with: m.range(at: 2)).lowercased()
        let date: Date?
        if unitRaw.hasPrefix("hour") || unitRaw == "hr" || unitRaw == "hrs" || unitRaw == "h" {
            date = cal.date(byAdding: .hour, value: n, to: now)
        } else if unitRaw.hasPrefix("minute") || unitRaw == "min" || unitRaw == "mins" || unitRaw == "m" {
            date = cal.date(byAdding: .minute, value: n, to: now)
        } else if unitRaw.hasPrefix("day") || unitRaw == "d" {
            date = cal.date(byAdding: .day, value: n, to: now)
        } else if unitRaw.hasPrefix("week") || unitRaw == "w" {
            date = cal.date(byAdding: .day, value: n * 7, to: now)
        } else if unitRaw.hasPrefix("month") {
            date = cal.date(byAdding: .month, value: n, to: now)
        } else if unitRaw.hasPrefix("year") || unitRaw == "y" {
            date = cal.date(byAdding: .year, value: n, to: now)
        } else {
            date = nil
        }
        guard let d = date else { return nil }

        return NaturalDateParseResult(
            date: d,
            matchedSubstring: String(text[r]),
            hasDateComponent: false,
            hasTimeComponent: true
        )
    }
}
