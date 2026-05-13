import SwiftUI
import AppKit
import EventKit

extension Notification.Name {
    static let quickAddTabAcceptSuggestion = Notification.Name("QuickAddTabAcceptSuggestion")
    /// `userInfo["open"]` as Bool — list `/` picker: key routing + main panel height.
    static let mainPanelListPickerLayout = Notification.Name("MainPanelListPickerLayout")
    /// `userInfo["delta"]` as Int (+1 down, -1 up) to move list picker selection.
    static let listPickerNavigate = Notification.Name("ListPickerNavigate")
    static let listPickerConfirm = Notification.Name("ListPickerConfirm")
    static let listPickerCancel = Notification.Name("ListPickerCancel")
    static let quickAddShiftReturnSave = Notification.Name("QuickAddShiftReturnSave")

    static let searchHotkeyToggle = Notification.Name("SearchHotkeyToggle")
    /// `userInfo["active"]` as Bool — search mode (Cmd+F); AppDelegate hides chips and shows result strip.
    static let searchModePresence = Notification.Name("SearchModePresence")
    /// `userInfo["hits"]` as `[[String: Any]]` with keys id, title, subtitle.
    static let searchResultsUpdated = Notification.Name("SearchResultsUpdated")
    static let searchResultActivate = Notification.Name("SearchResultActivate")
    static let forceExitSearchMode = Notification.Name("ForceExitSearchMode")
}

private struct ChipSet: Equatable {
    var priority: Int
    var hasDate: Bool
    var listName: String?
}

private let inputBarHeight: CGFloat = 58
private let listPickerSpacing: CGFloat = 6
private let listPickerMaxScroll: CGFloat = 220

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

    @State private var listPickerIndex: Int = 0
    @State private var dripSessionCount: Int = 0
    @State private var listPickerLayoutOpenState: Bool = false
    @State private var isSearchMode: Bool = false
    @State private var composeDraft: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    let eventStore = EKEventStore()

    private var slashQuery: (base: String, filter: String)? {
        if isSearchMode { return nil }
        return listSlashQuery(from: taskText)
    }

    private var filteredListsForPicker: [EKCalendar] {
        guard let q = slashQuery else { return [] }
        let f = q.filter
        if f.isEmpty { return lists }
        return lists.filter { $0.title.lowercased().contains(f) }
    }

    var body: some View {
        VStack(spacing: listPickerSpacing) {
            if slashQuery != nil {
                ListPickerView(
                    calendars: filteredListsForPicker,
                    selectedIndex: clampedListIndex,
                    onSelectIndex: { applyListPick(at: $0) }
                )
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            inputBarContent
        }
        .animation(.easeOut(duration: 0.18), value: slashQuery != nil)
        .padding(.bottom, slashQuery != nil ? 4 : 0)
        .background(
            VisualEffectView()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onChange(of: taskText) { _, new in
            let open = !isSearchMode && (listSlashQuery(from: new) != nil)
            if open != listPickerLayoutOpenState {
                if open { listPickerIndex = 0 }
                listPickerLayoutOpenState = open
                NotificationCenter.default.post(
                    name: .mainPanelListPickerLayout,
                    object: nil,
                    userInfo: ["open": open]
                )
            }
            syncListPickerAfterTextChange(new)
            parseText()
            updateSuggestion()
            postIfChipsChanged()
            if isSearchMode {
                scheduleSearchRefresh()
            }
        }
        .onChange(of: isSearchMode) { _, active in
            notifySearchModePresence(active: active)
            if active {
                scheduleSearchRefresh()
            } else {
                searchDebounceTask?.cancel()
                NotificationCenter.default.post(
                    name: .searchResultsUpdated,
                    object: nil,
                    userInfo: ["hits": []]
                )
            }
        }
        .onAppear {
            requestPermissionsAndFetchLists()
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PanelDidOpen"))) { _ in
            dripSessionCount = 0
            isSearchMode = false
            composeDraft = ""
            searchDebounceTask?.cancel()
            notifySearchModePresence(active: false)
            listPickerLayoutOpenState = listSlashQuery(from: taskText) != nil
            if listPickerLayoutOpenState {
                NotificationCenter.default.post(
                    name: .mainPanelListPickerLayout,
                    object: nil,
                    userInfo: ["open": true]
                )
            }
            isInputFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isInputFocused = true
                forcePostChipState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickAddTabAcceptSuggestion)) { _ in
            if slashQuery != nil {
                moveListSelection(delta: 1)
            } else {
                acceptSuggestion()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .listPickerNavigate)) { note in
            guard slashQuery != nil, let d = note.userInfo?["delta"] as? Int else { return }
            moveListSelection(delta: d)
        }
        .onReceive(NotificationCenter.default.publisher(for: .listPickerConfirm)) { _ in
            if slashQuery != nil { applyListPick(at: clampedListIndex) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .listPickerCancel)) { _ in
            cancelListPicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickAddShiftReturnSave)) { _ in
            guard !isSearchMode else { return }
            saveTask(keepPanelOpen: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchHotkeyToggle)) { _ in
            toggleSearchModeFromHotkey()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceExitSearchMode)) { _ in
            if isSearchMode {
                isSearchMode = false
                taskText = composeDraft
                composeDraft = ""
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchResultActivate)) { note in
            guard let id = note.userInfo?["id"] as? String else { return }
            openReminderInRemindersApp(id: id)
        }
    }

    private var clampedListIndex: Int {
        let n = filteredListsForPicker.count
        guard n > 0 else { return 0 }
        return min(max(0, listPickerIndex), n - 1)
    }

    private var inputBarContent: some View {
        ZStack(alignment: .leading) {
            if taskText.isEmpty && slashQuery == nil {
                Text(
                    isSearchMode
                        ? "Search reminders…  ·  ⌘F to close"
                        : "Task…  ·  ⌘F search  ·  ⇧⏎ save & keep adding  ·  space + / for lists"
                )
                    .font(.system(size: 18, weight: .light, design: .rounded))
                    .foregroundColor(.primary.opacity(0.22))
                    .allowsHitTesting(false)
                    .padding(.horizontal, 22)
            }

            if !suggestion.isEmpty && !taskText.isEmpty && slashQuery == nil && !isSearchMode {
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

            Text(styledText(from: taskText))
                .font(.system(size: 20, weight: .light, design: .rounded))
                .allowsHitTesting(false)
                .padding(.horizontal, 22)

            TextField("", text: $taskText)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .light, design: .rounded))
                .foregroundColor(.clear)
                .tint(.primary.opacity(0.6))
                .focused($isInputFocused)
                .onSubmit {
                    if !isSearchMode {
                        saveTask(keepPanelOpen: false)
                    }
                }
                .padding(.horizontal, 22)
        }
        .frame(height: inputBarHeight)
        .overlay(alignment: .trailing) {
            if dripSessionCount > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<min(dripSessionCount, 6), id: \.self) { _ in
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.55))
                    }
                    if dripSessionCount > 6 {
                        Text("+\(dripSessionCount - 6)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                }
                .padding(.trailing, 14)
            }
        }
    }

    // MARK: - `/` list picker

    /// Slash list mode: `/` at start or after whitespace; `http://` is ignored (no whitespace before last `/`).
    private func listSlashQuery(from text: String) -> (base: String, filter: String)? {
        guard let slashIdx = text.lastIndex(of: "/") else { return nil }
        if slashIdx > text.startIndex {
            let prev = text[text.index(before: slashIdx)]
            if !prev.isWhitespace { return nil }
        }
        let base = String(text[..<slashIdx]).trimmingCharacters(in: .whitespaces)
        let after = text.index(after: slashIdx)
        let filter = after < text.endIndex ? String(text[after...]) : ""
        return (base, filter.lowercased())
    }

    private func syncListPickerAfterTextChange(_ newText: String) {
        if isSearchMode {
            listPickerIndex = 0
            return
        }
        guard listSlashQuery(from: newText) != nil else {
            listPickerIndex = 0
            return
        }
        let n = lists.filter { cal in
            let f = listSlashQuery(from: newText)?.filter ?? ""
            return f.isEmpty || cal.title.lowercased().contains(f)
        }.count
        if listPickerIndex >= n { listPickerIndex = max(0, n - 1) }
    }

    private func moveListSelection(delta: Int) {
        let n = filteredListsForPicker.count
        guard n > 0 else { return }
        listPickerIndex = ((clampedListIndex + delta) % n + n) % n
    }

    private func applyListPick(at index: Int) {
        guard let q = slashQuery else { return }
        let rows = filteredListsForPicker
        guard index >= 0, index < rows.count else { return }
        let title = rows[index].title
        let spacer = q.base.isEmpty ? "" : (q.base.hasSuffix(" ") ? "" : " ")
        let prefix = q.base + spacer
        taskText = prefix + "in \(title) "
        listPickerIndex = 0
    }

    private func cancelListPicker() {
        guard let q = slashQuery else { return }
        taskText = q.base
        listPickerIndex = 0
    }

    // MARK: - Ghost text / suggestion

    private func updateSuggestion() {
        suggestion = ""
        if isSearchMode { return }
        if slashQuery != nil { return }
        guard !taskText.isEmpty else { return }
        let lower = taskText.lowercased()

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

        let listTriggers = ["in ", "to "]
        for trigger in listTriggers {
            if lower.hasSuffix(trigger) {
                if let firstName = lists.first?.title {
                    suggestion = firstName
                }
                return
            }
            for list in lists {
                let listLower = list.title.lowercased()
                for t in listTriggers {
                    if lower.hasSuffix(t) { break }
                    let possibleSuffix = lower.components(separatedBy: t).last ?? ""
                    if !possibleSuffix.isEmpty && listLower.hasPrefix(possibleSuffix) && possibleSuffix != listLower {
                        suggestion = String(list.title.dropFirst(possibleSuffix.count))
                        return
                    }
                }
            }
        }

        if taskText == "!" {
            suggestion = "! task name  (!! medium, !!! high)"
            return
        }
    }

    func acceptSuggestion() {
        guard !isSearchMode else { return }
        guard !suggestion.isEmpty else { return }
        taskText += suggestion
        suggestion = ""
        parseText()
        postIfChipsChanged()
    }

    // MARK: - Chip notification

    private func postIfChipsChanged() {
        if isSearchMode {
            let cleared = ChipSet(priority: 0, hasDate: false, listName: nil)
            guard cleared != lastPostedChipSet else { return }
            lastPostedChipSet = cleared
            postChipState()
            return
        }
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
        if isSearchMode {
            var plain = AttributedString(text)
            plain.foregroundColor = .primary
            return plain
        }
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
        if isSearchMode {
            parsedDate = nil
            parsedDateString = nil
            parsedList = nil
            parsedListString = nil
            parsedPriority = 0
            parsedPriorityString = nil
            return
        }
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

    private func saveTask(keepPanelOpen: Bool) {
        guard !isSearchMode else { return }
        guard slashQuery == nil else { return }
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

        if keepPanelOpen {
            dripSessionCount += 1
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                taskText = ""
            }
        } else {
            taskText = ""
            dripSessionCount = 0
        }
        suggestion = ""
        parseText()
        lastPostedChipSet = ChipSet(priority: 0, hasDate: false, listName: nil)
        postChipState()

        NotificationCenter.default.post(
            name: NSNotification.Name("TaskSaved"),
            object: nil,
            userInfo: [
                "title": finalTitle,
                "list": finalListTitle,
                "date": finalDateFormatted ?? "",
                "keepPanelOpen": keepPanelOpen,
            ]
        )
    }

    // MARK: - Search (⌘F)

    private func toggleSearchModeFromHotkey() {
        if isSearchMode {
            isSearchMode = false
            taskText = composeDraft
            composeDraft = ""
        } else {
            composeDraft = taskText
            isSearchMode = true
            taskText = ""
            suggestion = ""
        }
        parseText()
        updateSuggestion()
        postIfChipsChanged()
    }

    private func notifySearchModePresence(active: Bool) {
        NotificationCenter.default.post(
            name: .searchModePresence,
            object: nil,
            userInfo: ["active": active]
        )
    }

    private func scheduleSearchRefresh() {
        guard isSearchMode else { return }
        searchDebounceTask?.cancel()
        let query = taskText
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            guard isSearchMode else { return }
            let hits = await fetchMatchingReminders(query: query)
            guard !Task.isCancelled else { return }
            guard isSearchMode else { return }
            let rows: [[String: Any]] = hits.map { r in
                [
                    "id": r.calendarItemIdentifier,
                    "title": r.title,
                    "subtitle": reminderSubtitle(for: r),
                ] as [String: Any]
            }
            NotificationCenter.default.post(
                name: .searchResultsUpdated,
                object: nil,
                userInfo: ["hits": rows]
            )
        }
    }

    private func fetchMatchingReminders(query: String) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let cals = eventStore.calendars(for: .reminder)
            guard !trimmed.isEmpty, !cals.isEmpty else {
                continuation.resume(returning: [])
                return
            }
            let now = Date()
            guard let start = Calendar.current.date(byAdding: .year, value: -2, to: now),
                  let end = Calendar.current.date(byAdding: .year, value: 2, to: now) else {
                continuation.resume(returning: [])
                return
            }
            let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: cals)
            eventStore.fetchReminders(matching: predicate) { reminders in
                let parts = trimmed.lowercased().split(separator: " ").map(String.init)
                let matched = (reminders ?? []).filter { r in
                    let hay = (r.title + " " + (r.notes ?? "")).lowercased()
                    return parts.allSatisfy { hay.contains($0) }
                }
                .prefix(35)
                let result = Array(matched)
                DispatchQueue.main.async {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func reminderSubtitle(for reminder: EKReminder) -> String {
        let list = reminder.calendar?.title ?? ""
        if let due = reminder.dueDateComponents, let date = Calendar.current.date(from: due) {
            let fmt = DateFormatter()
            fmt.dateStyle = .short
            fmt.timeStyle = .short
            let when = fmt.string(from: date)
            return [list, when].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return list
    }

    private func openReminderInRemindersApp(id: String) {
        guard (eventStore.calendarItem(withIdentifier: id) as? EKReminder) != nil else {
            NSSound.beep()
            return
        }
        let url = URL(fileURLWithPath: "/System/Applications/Reminders.app")
        NSWorkspace.shared.open(url)
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
