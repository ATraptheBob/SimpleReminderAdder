import Foundation
import EventKit

class MockReminder: EKReminder {
    var mockTitle: String?
    var mockDueDateComponents: DateComponents?
    var mockIsCompleted: Bool = false
    var mockCalendarItemIdentifier: String = UUID().uuidString

    override var title: String! {
        get { return mockTitle ?? "" }
        set { mockTitle = newValue }
    }

    override var dueDateComponents: DateComponents? {
        get { return mockDueDateComponents }
        set { mockDueDateComponents = newValue }
    }

    override var isCompleted: Bool {
        get { return mockIsCompleted }
        set { mockIsCompleted = newValue }
    }

    override var calendarItemIdentifier: String {
        return mockCalendarItemIdentifier
    }
}

class PerfTest {
    func dueDate(for reminder: EKReminder) -> Date? {
        guard let due = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: due)
    }

    func run() {
        let eventStore = EKEventStore()

        var reminders: [EKReminder] = []
        for i in 0..<10000 {
            let r = MockReminder(eventStore: eventStore)
            r.mockTitle = "Task \(i)"
            if i % 2 == 0 {
                var dc = DateComponents()
                dc.year = 2023
                dc.month = 1
                dc.day = i % 28 + 1
                r.mockDueDateComponents = dc
            }
            r.mockIsCompleted = false
            reminders.append(r)
        }

        let start = Date()

        let rows = reminders
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                let ld = self.dueDate(for: lhs)
                let rd = self.dueDate(for: rhs)
                switch (ld, rd) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "") == .orderedAscending
                }
            }

        let duration = Date().timeIntervalSince(start)
        print("Original Baseline: \(duration) seconds")

        let start2 = Date()

        let remindersWithDates: [(reminder: EKReminder, dueDate: Date?)] = reminders.filter { !$0.isCompleted }.map {
            ($0, self.dueDate(for: $0))
        }
        let rows2 = remindersWithDates.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (lhs.reminder.title ?? "").localizedCaseInsensitiveCompare(rhs.reminder.title ?? "") == .orderedAscending
            }
        }

        let duration2 = Date().timeIntervalSince(start2)
        print("Optimized: \(duration2) seconds")
    }
}

PerfTest().run()
