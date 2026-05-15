import Foundation

struct NaturalDateParseResult: Equatable {
    var date: Date?
    var matchedSubstring: String?
    var hasDateComponent: Bool
    var hasTimeComponent: Bool
}

enum NaturalDateParser {
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

        let phrasePairs: [(String, NaturalDateParseResult)] = [
            (#"(?i)\bday after tomorrow\b"#, dayAfterTomorrowAt(hour: 9, minute: 0, reference: now, cal: cal)),
            (#"(?i)\btomorrow morning\b"#, tomorrowAt(hour: 9, minute: 0, reference: now, cal: cal)),
            (#"(?i)\btomorrow afternoon\b"#, tomorrowAt(hour: 14, minute: 0, reference: now, cal: cal)),
            (#"(?i)\btomorrow evening\b"#, tomorrowAt(hour: 19, minute: 0, reference: now, cal: cal)),
            (#"(?i)\btomorrow\b"#, tomorrowAt(hour: 9, minute: 0, reference: now, cal: cal)),
            (#"(?i)\bthis evening\b"#, thisEveningResult(reference: now, cal: cal)),
            (#"(?i)\btonight\b"#, tonightResult(reference: now, cal: cal)),
            (#"(?i)\bthis afternoon\b"#, dayPartResult(reference: now, cal: cal, hour: 14, minute: 0)),
            (#"(?i)\bthis morning\b"#, dayPartResult(reference: now, cal: cal, hour: 9, minute: 0)),
            (#"(?i)\bnext week\b"#, offsetDays(7, atHour: 9, minute: 0, reference: now, cal: cal)),
            (#"(?i)\bnext month\b"#, offsetMonths(1, atHour: 9, minute: 0, reference: now, cal: cal)),
            (#"(?i)\bend of day\b"#, todayAt(hour: 17, minute: 0, reference: now, cal: cal, rollForwardIfPast: true)),
            (#"(?i)\beod\b"#, todayAt(hour: 17, minute: 0, reference: now, cal: cal, rollForwardIfPast: true)),
            (#"(?i)\bclose of business\b"#, fridaySameWeekAt(hour: 17, minute: 0, reference: now, cal: cal)),
            (#"(?i)\bcob\b"#, fridaySameWeekAt(hour: 17, minute: 0, reference: now, cal: cal)),
            (#"(?i)\bmidday\b"#, todayAt(hour: 12, minute: 0, reference: now, cal: cal, rollForwardIfPast: true)),
            (#"(?i)\bnoon\b"#, todayAt(hour: 12, minute: 0, reference: now, cal: cal, rollForwardIfPast: true)),
            (#"(?i)\bmidnight\b"#, endOfToday(reference: now, cal: cal)),
        ]

        for (pattern, result) in phrasePairs {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: text, options: [], range: full),
                  let r = Range(m.range, in: text) else { continue }
            take(r, result)
        }

        if let re = try? NSRegularExpression(pattern: #"(?i)\bnext\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#),
           let m = re.firstMatch(in: text, options: [], range: full),
           let r = Range(m.range, in: text) {
            let w = ns.substring(with: m.range(at: 1)).lowercased()
            if let wd = weekdayIndex(from: w),
               let d = nextWeekdayAfterNextWeekStart(wd, reference: now, cal: cal) {
                take(r, NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: false))
            }
        }

        if let re = try? NSRegularExpression(pattern: #"(?i)(?<!next )\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#),
           let m = re.firstMatch(in: text, options: [], range: full),
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
        thisEveningResult(reference: now, cal: cal)
    }

    private static func thisEveningResult(reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        dayPartResult(reference: now, cal: cal, hour: 19, minute: 0)
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
        let d = cal.date(byAdding: dc, to: tomorrow)
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
        let d = cal.date(byAdding: dc, to: day)
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func offsetDays(_ days: Int, atHour hour: Int, minute: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        guard let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let d = cal.date(byAdding: dc, to: day)
        return NaturalDateParseResult(date: d, matchedSubstring: nil, hasDateComponent: true, hasTimeComponent: true)
    }

    private static func offsetMonths(_ months: Int, atHour hour: Int, minute: Int, reference now: Date, cal: Calendar) -> NaturalDateParseResult {
        guard let day = cal.date(byAdding: .month, value: months, to: cal.startOfDay(for: now)) else {
            return NaturalDateParseResult(date: nil, matchedSubstring: nil, hasDateComponent: false, hasTimeComponent: false)
        }
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        let d = cal.date(byAdding: dc, to: day)
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
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard let match = matches.first, let date = match.date, let baseRange = Range(match.range, in: text) else { return nil }

        var finalDateString = String(text[baseRange])
        let textBefore = text[text.startIndex..<baseRange.lowerBound]
        let wordsBefore = textBefore.components(separatedBy: .whitespaces)
        if let lastWord = wordsBefore.last(where: { !$0.isEmpty })?.lowercased(),
           ["at", "on", "by", "for", "due", "until", "before"].contains(lastWord) {
            let escaped = NSRegularExpression.escapedPattern(for: finalDateString)
            let searchPattern = "(?i)\\b\(lastWord)\\s+\(escaped)"
            if let fullRange = text.range(of: searchPattern, options: .regularExpression) {
                finalDateString = String(text[fullRange])
            }
        }

        let dc = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hasNonZeroClock = (dc.hour ?? 0) != 0 || (dc.minute ?? 0) != 0
        let hasTime = match.timeZone != nil
            || hasNonZeroClock
            || finalDateString.range(of: #"\d{1,2}\s*(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)"#, options: [.regularExpression, .caseInsensitive]) != nil
            || finalDateString.range(of: #"\b(at|@)\s*\d"#, options: [.regularExpression, .caseInsensitive]) != nil

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
        if t.range(of: #"mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"#, options: .regularExpression) != nil { return false }
        return t.range(of: #"^\d{1,2}\s*(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func hasExplicitCalendarDay(in s: String) -> Bool {
        let t = s.lowercased()
        if t.contains("today") || t.contains("next ") { return true }
        if t.contains("tonight") || t.contains("this evening") || t.contains("this morning") || t.contains("this afternoon") { return true }
        if t.contains("tomorrow") || t.contains("day after tomorrow") { return true }
        if t.contains("eod") || t.contains("end of day") || t.contains("cob") || t.contains("close of business") { return true }
        if t.contains("noon") || t.contains("midday") || t.contains("midnight") { return true }
        if t.range(of: #"mon(day)?|tue(sday)?|wed(nesday)?|thu(rsday)?|fri(day)?|sat(urday)?|sun(day)?"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"\d{1,2}[/\-]\d{1,2}([/\-]\d{2,4})?"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func parseRelative(text: String, reference now: Date) -> NaturalDateParseResult? {
        let cal = Calendar.current
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        let fuzzy: [(String, Date?)] = [
            (#"(?i)\bin\s+a\s+couple\s+of\s+hours?\b"#, cal.date(byAdding: .hour, value: 2, to: now)),
            (#"(?i)\bin\s+a\s+few\s+hours?\b"#, cal.date(byAdding: .hour, value: 3, to: now)),
            (#"(?i)\bin\s+half\s+an?\s+hour\b"#, cal.date(byAdding: .minute, value: 30, to: now)),
            (#"(?i)\bin\s+an?\s+hour\b"#, cal.date(byAdding: .hour, value: 1, to: now)),
        ]
        for (pat, date) in fuzzy {
            guard let re = try? NSRegularExpression(pattern: pat),
                  let m = re.firstMatch(in: text, options: [], range: full),
                  let r = Range(m.range, in: text),
                  let d = date else { continue }
            return NaturalDateParseResult(date: d, matchedSubstring: String(text[r]), hasDateComponent: false, hasTimeComponent: true)
        }

        let pattern = #"(?i)\bin\s+(\d+)\s*(hours?|hrs?|h\b|minutes?|mins?|m\b|days?|d\b)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: full),
              let r = Range(m.range, in: text) else { return nil }

        guard m.numberOfRanges >= 3,
              let n = Int(ns.substring(with: m.range(at: 1))),
              n > 0 else { return nil }

        let unitRaw = ns.substring(with: m.range(at: 2)).lowercased()
        let date: Date?
        if unitRaw.hasPrefix("hour") || unitRaw == "hr" || unitRaw == "hrs" || unitRaw == "h" {
            date = cal.date(byAdding: .hour, value: n, to: now)
        } else if unitRaw.hasPrefix("minute") || unitRaw == "min" || unitRaw == "mins" || unitRaw == "m" {
            date = cal.date(byAdding: .minute, value: n, to: now)
        } else if unitRaw.hasPrefix("day") || unitRaw == "d" {
            date = cal.date(byAdding: .day, value: n, to: now)
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
