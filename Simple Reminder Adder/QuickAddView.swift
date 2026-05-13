import SwiftUI
import AppKit
import EventKit

extension Notification.Name {
    /// Posted when the user presses Tab in the quick-add panel; the view applies autocomplete if available.
    static let quickAddTabAcceptSuggestion = Notification.Name("QuickAddTabAcceptSuggestion")
}

private struct ChipSet: Equatable {
    var priority: Int
    var hasDate: Bool
    var listName: String?
}

struct QuickAddView: View {
    @State private var taskText: String = ""
    @State private var lists: [EKCalendar] = []
    @FocusState private var isInputFocused: Bool

    @State private var parsedDate: Date? = nil
    @State private var parsedDateString: String? = nil
    @State private var parsedList: EKCalendar? = nil
    @State private var parsedListString: String? = nil
    @State private var parsedPriority: Int = 0
    @State private var parsedPriorityString: String? = nil

    @State private var suggestion: String = ""
    @State private var lastPostedChipSet = ChipSet(priority: 0, hasDate: false, listName: nil)

    let eventStore = EKEventStore()

    var body: some View {
        ZStack(alignment: .leading) {
            // Placeholder
            if taskText.isEmpty {
                Text("Task… e.g. '!!! Gym at 5pm in Personal'")
                    .font(.system(size: 20, weight: .light, design: .rounded))
                    .foregroundColor(.primary.opacity(0.22))
                    .allowsHitTesting(false)
                    .padding(.horizontal, 22)
            }

            // Ghost suggestion text (shown after typed text)
            if !suggestion.isEmpty && !taskText.isEmpty {
                Text(taskText + suggestion)
                    .font(.system(size: 20, weight: .light, design: .rounded))
                    .foregroundColor(.clear)
                    .overlay(
                        GeometryReader { _ in
                            Text(taskText)
                                .font(.system(size: 20, weight: .light, design: .rounded))
                                .foregroundColor(.clear)
                            +
                            Text(suggestion)
                                .font(.system(size: 20, weight: .light, design: .rounded))
                                .foregroundColor(.primary.opacity(0.25))
                        }
                    )
                    .allowsHitTesting(false)
                    .padding(.horizontal, 22)
            }

            // Styled real text
            Text(styledText(from: taskText))
                .font(.system(size: 20, weight: .light, design: .rounded))
                .allowsHitTesting(false)
                .padding(.horizontal, 22)

            // Actual invisible text field
            TextField("", text: $taskText)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .light, design: .rounded))
                .foregroundColor(.clear)
                .tint(.primary.opacity(0.6))
                .focused($isInputFocused)
                .onSubmit { saveTask() }
                .padding(.horizontal, 22)
        }
        .frame(height: 58)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .onChange(of: taskText) { _, _ in
            parseText()
            updateSuggestion()
            postIfChipsChanged()
        }
        .onAppear {
            requestPermissionsAndFetchLists()
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PanelDidOpen"))) { _ in
            isInputFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isInputFocused = true
                // Force re-post so chips reappear on reopen
                forcePostChipState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickAddTabAcceptSuggestion)) { _ in
            acceptSuggestion()
        }
    }

    // MARK: - Ghost text / suggestion

    private func updateSuggestion() {
        suggestion = ""
        guard !taskText.isEmpty else { return }
        let lower = taskText.lowercased()

        // Suggest time patterns
        let timePatterns: [(trigger: String, completion: String)] = [
            ("at ", "5:00 PM"),
            ("tod", "ay at 5:00 PM"),
            ("tom", "orrow at 9:00 AM"),
            ("thi", "s evening at 7:00 PM"),
            ("nex", "t Monday at 9:00 AM"),
            ("on ", "Monday at 9:00 AM"),
        ]
        for (trigger, completion) in timePatterns {
            if lower.hasSuffix(trigger) {
                suggestion = completion
                return
            }
        }

        // Suggest list names
        let listTriggers = ["in ", "to "]
        for trigger in listTriggers {
            if lower.hasSuffix(trigger) {
                if let firstName = lists.first?.title {
                    suggestion = firstName
                }
                return
            }
            // Partial list match
            for list in lists {
                let listLower = list.title.lowercased()
                for t in listTriggers {
                    if lower.hasSuffix(t) { break }
                    // Check if text ends with "in Gr" and list is "Groceries"
                    let possibleSuffix = lower.components(separatedBy: t).last ?? ""
                    if !possibleSuffix.isEmpty && listLower.hasPrefix(possibleSuffix) && possibleSuffix != listLower {
                        suggestion = String(list.title.dropFirst(possibleSuffix.count))
                        return
                    }
                }
            }
        }

        // Suggest priority prefix
        if taskText == "!" {
            suggestion = "! task name  (!! medium, !!! high)"
            return
        }
    }

    // MARK: - Tab → autocomplete (see `Notification.Name.quickAddTabAcceptSuggestion`)

    func acceptSuggestion() {
        guard !suggestion.isEmpty else { return }
        taskText += suggestion
        suggestion = ""
        parseText()
        postIfChipsChanged()
    }

    // MARK: - Chip notification

    private func postIfChipsChanged() {
        let current = ChipSet(priority: parsedPriority, hasDate: parsedDate != nil, listName: parsedList?.title)
        guard current != lastPostedChipSet else { return }
        lastPostedChipSet = current
        postChipState()
    }

    private func forcePostChipState() {
        postChipState()
    }

    private func postChipState() {
        NotificationCenter.default.post(
            name: NSNotification.Name("ParsedStateChanged"),
            object: nil,
            userInfo: [
                "date":     parsedDate as Any,
                "list":     parsedList?.title as Any,
                "priority": parsedPriority,
            ]
        )
    }

    // MARK: - Styling

    private func priorityColor() -> Color {
        switch parsedPriority {
        case 1:  return Color(hue: 0.0,  saturation: 0.6, brightness: 0.95)
        case 5:  return Color(hue: 0.11, saturation: 0.6, brightness: 0.95)
        default: return Color(hue: 0.60, saturation: 0.5, brightness: 0.90)
        }
    }

    private func styledText(from text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = .primary
        if let s = parsedPriorityString, let r = attr.range(of: s) {
            attr[r].foregroundColor = priorityColor().opacity(0.5)
        }
        if let s = parsedDateString, let r = attr.range(of: s, options: .caseInsensitive) {
            attr[r].foregroundColor = Color(hue: 0.08, saturation: 0.6, brightness: 0.95).opacity(0.5)
        }
        if let s = parsedListString, let r = attr.range(of: s, options: .caseInsensitive) {
            attr[r].foregroundColor = Color(hue: 0.75, saturation: 0.4, brightness: 0.90).opacity(0.5)
        }
        return attr
    }

    // MARK: - Parse

    private func parseText() {
        parsedDate = nil; parsedDateString = nil
        parsedList = nil; parsedListString = nil
        parsedPriority = 0; parsedPriorityString = nil
        guard !taskText.isEmpty else { return }

        if taskText.hasPrefix("!!!") { parsedPriority = 1; parsedPriorityString = "!!!" }
        else if taskText.hasPrefix("!!") { parsedPriority = 5; parsedPriorityString = "!!" }
        else if taskText.hasPrefix("!") { parsedPriority = 9; parsedPriorityString = "!" }

        for list in lists {
            let pattern = "(?i)\\b(?:in|to)\\s+\\Q\(list.title)\\E\\b"
            if let range = taskText.range(of: pattern, options: .regularExpression) {
                parsedList = list
                parsedListString = String(taskText[range])
                break
            }
        }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: taskText, options: [], range: NSRange(taskText.startIndex..., in: taskText))
            if let match = matches.first, let date = match.date, let baseRange = Range(match.range, in: taskText) {
                var finalDateString = String(taskText[baseRange])
                let textBefore = taskText[taskText.startIndex..<baseRange.lowerBound]
                let wordsBefore = textBefore.components(separatedBy: .whitespaces)
                if let lastWord = wordsBefore.last(where: { !$0.isEmpty })?.lowercased(),
                   ["at", "on", "by", "for", "due"].contains(lastWord) {
                    let searchPattern = "(?i)\\b\(lastWord)\\s+\\Q\(finalDateString)\\E"
                    if let fullRange = taskText.range(of: searchPattern, options: .regularExpression) {
                        finalDateString = String(taskText[fullRange])
                    }
                }
                parsedDateString = finalDateString
                parsedDate = date
            }
        }
    }

    // MARK: - Save

    private func saveTask() {
        guard !taskText.isEmpty else { return }
        var cleanTitle = taskText
        if let s = parsedPriorityString { cleanTitle = cleanTitle.replacingOccurrences(of: s, with: "") }
        if let s = parsedDateString     { cleanTitle = cleanTitle.replacingOccurrences(of: s, with: "", options: .caseInsensitive) }
        if let s = parsedListString     { cleanTitle = cleanTitle.replacingOccurrences(of: s, with: "", options: .caseInsensitive) }
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty { cleanTitle = "New Task" }

        let dest = parsedList ?? eventStore.defaultCalendarForNewReminders()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = cleanTitle
        if let dest { reminder.calendar = dest }
        reminder.priority = parsedPriority
        if let d = parsedDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            reminder.addAlarm(EKAlarm(absoluteDate: d))
        }
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            NSSound.beep()
            return
        }

        let finalTitle = cleanTitle
        let finalListTitle = dest?.title ?? "Reminders"
        var finalDateFormatted: String? = nil
        if let d = parsedDate {
            let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
            finalDateFormatted = fmt.string(from: d)
        }

        taskText = ""
        suggestion = ""
        parseText()
        lastPostedChipSet = ChipSet(priority: 0, hasDate: false, listName: nil)
        postChipState()

        NotificationCenter.default.post(
            name: NSNotification.Name("TaskSaved"),
            object: nil,
            userInfo: ["title": finalTitle, "list": finalListTitle, "date": finalDateFormatted ?? ""]
        )
    }

    private func requestPermissionsAndFetchLists() {
        Task {
            do {
                if #available(macOS 14.0, *) { try await eventStore.requestFullAccessToReminders() }
                else { try await eventStore.requestAccess(to: .reminder) }
                await MainActor.run { self.lists = eventStore.calendars(for: .reminder) }
            } catch { print("Permission error: \(error)") }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
