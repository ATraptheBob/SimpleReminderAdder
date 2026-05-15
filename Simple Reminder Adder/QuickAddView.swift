import SwiftUI
import AppKit
import EventKit

extension Notification.Name {
    static let quickAddTabAcceptSuggestion = Notification.Name("QuickAddTabAcceptSuggestion")
    static let mainPanelListPickerLayout   = Notification.Name("MainPanelListPickerLayout")
    static let mainPanelSearchLayout       = Notification.Name("MainPanelSearchLayout")
    static let listPickerNavigate          = Notification.Name("ListPickerNavigate")
    static let listPickerConfirm           = Notification.Name("ListPickerConfirm")
    static let listPickerCancel            = Notification.Name("ListPickerCancel")
    static let quickAddShiftReturnSave     = Notification.Name("QuickAddShiftReturnSave")
    static let searchHotkeyToggle          = Notification.Name("SearchHotkeyToggle")
    static let searchModePresence          = Notification.Name("SearchModePresence")
    static let searchResultActivate        = Notification.Name("SearchResultActivate")
    static let forceExitSearchMode         = Notification.Name("ForceExitSearchMode")
    static let chipPrioritySliderCommit    = Notification.Name("ChipPrioritySliderCommit")
    static let chipSwipeDelete             = Notification.Name("ChipSwipeDelete")
    static let chipSwipeDuplicate          = Notification.Name("ChipSwipeDuplicate")
    static let chipsLayoutChanged          = Notification.Name("ChipsLayoutChanged")
}

// MARK: - ChipSet
// BUG FIX: was `hasDate: Bool` — storing only a bool meant changing "at 5pm" → "at 6pm"
// left hasDate==true both times, so postIfChipsChanged() saw no diff and skipped the notification.
// Now stores the actual Date? so any time-value change triggers a re-render.
private struct ChipSet: Equatable {
    var priority: Int
    var date: Date?
    var showDatePill: Bool
    var showTimePill: Bool
    var listName: String?
}

private let inputBarHeight: CGFloat = 58
private let listPickerSpacing: CGFloat = 6
private let listPickerMaxScroll: CGFloat = 220

struct QuickAddView: View {
    private let eventStore = EKEventStore()

    @State private var taskText: String = ""
    @State private var lists: [EKCalendar] = []
    @FocusState private var isInputFocused: Bool

    @State private var parsedDate: Date?        = nil
    @State private var parsedDateString: String? = nil
    @State private var parsedList: EKCalendar?  = nil
    @State private var parsedListString: String? = nil
    @State private var parsedPriority: Int      = 0
    @State private var parsedPriorityString: String? = nil

    @State private var suggestion: String = ""
    @State private var lastPostedChipSet = ChipSet(priority: 0, date: nil, showDatePill: false, showTimePill: false, listName: nil)

    @State private var showDatePill: Bool = false
    @State private var showTimePill: Bool = false

    @State private var listPickerIndex: Int = 0
    @State private var dripSessionCount: Int = 0
    @State private var listPickerLayoutOpenState: Bool = false
    @State private var isSearchMode: Bool = false
    @State private var composeDraft: String = ""
    @State private var searchHitRows: [SearchHitRowModel] = []
    @State private var searchDebounceTask: Task<Void, Never>?

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

    private var searchPanelAuxiliaryHeight: CGFloat {
        guard isSearchMode else { return 0 }
        if searchHitRows.isEmpty { return 96 }
        return min(260, 12 + CGFloat(searchHitRows.count) * 42 + 20)
    }

    private func postMainPanelSearchLayout() {
        guard isSearchMode else {
            NotificationCenter.default.post(
                name: .mainPanelSearchLayout,
                object: nil,
                userInfo: ["open": false, "height": CGFloat(0)]
            )
            return
        }
        NotificationCenter.default.post(
            name: .mainPanelSearchLayout,
            object: nil,
            userInfo: ["open": true, "height": searchPanelAuxiliaryHeight]
        )
    }

    var body: some View {
        Group {
            Group {
                mainContent
                    .onChange(of: taskText) { _, new in
                        handleTaskTextChange(new)
                    }
                    .onChange(of: isSearchMode) { _, active in
                        handleSearchModeChange(active)
                    }
                    .onChange(of: searchHitRows.count) { _, _ in
                        if isSearchMode { postMainPanelSearchLayout() }
                    }
                    .onAppear {
                        requestPermissionsAndFetchLists()
                        isInputFocused = true
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PanelDidOpen"))) { _ in
                        handlePanelDidOpen()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .quickAddTabAcceptSuggestion)) { _ in
                        if slashQuery != nil { moveListSelection(delta: 1) }
                        else { acceptSuggestion() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .listPickerNavigate)) { note in
                        guard slashQuery != nil, let d = note.userInfo?["delta"] as? Int else { return }
                        moveListSelection(delta: d)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .listPickerConfirm)) { _ in
                        if slashQuery != nil { applyListPick(at: clampedListIndex) }
                    }
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
                    searchHitRows = []
                    postMainPanelSearchLayout()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchResultActivate)) { note in
                guard let id = note.userInfo?["id"] as? String else { return }
                openReminderInRemindersApp(id: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chipPrioritySliderCommit)) { note in
            guard let v = note.userInfo?["value"] as? Int else { return }
            parsedPriority = v
            applyPriorityPrefixToTaskText()
            parseText()
            postChipState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chipSwipeDelete)) { note in
            guard let k = note.userInfo?["kind"] as? String else { return }
            applyChipSwipeDelete(kind: k)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chipSwipeDuplicate)) { note in
            guard let k = note.userInfo?["kind"] as? String else { return }
            applyChipSwipeDuplicate(kind: k)
        }
    }

    // MARK: - Body

    private var mainContent: some View {
        VStack(spacing: listPickerSpacing) {
            if slashQuery != nil {
                ListPickerView(
                    calendars: filteredListsForPicker,
                    selectedIndex: clampedListIndex,
                    onSelectIndex: { applyListPick(at: $0) }
                )
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal:   .opacity.combined(with: .move(edge: .top))
                    )
                )
            }

            inputBarContent

            if isSearchMode {
                SearchResultsMenuView(hits: searchHitRows)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal:   .opacity.combined(with: .move(edge: .bottom))
                        )
                    )
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9),  value: slashQuery != nil)
        .animation(.spring(response: 0.28, dampingFraction: 0.9),  value: isSearchMode)
        .animation(.spring(response: 0.26, dampingFraction: 0.92), value: searchHitRows.count)
        .padding(.bottom, slashQuery != nil ? 4 : 0)
        .background(
            VisualEffectView()
                .clipShape(RoundedRectangle(cornerRadius: PanelChrome.outerCorner, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelChrome.outerCorner, style: .continuous)
                .stroke(PanelChrome.strokeSubtle, lineWidth: 1)
        )
    }

    // MARK: - Handlers

    private func handleTaskTextChange(_ new: String) {
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
        if isSearchMode { scheduleSearchRefresh() }
    }

    private func handleSearchModeChange(_ active: Bool) {
        notifySearchModePresence(active: active)
        if active {
            searchHitRows = []
            scheduleSearchRefresh()
        } else {
            searchDebounceTask?.cancel()
            searchHitRows = []
        }
        postMainPanelSearchLayout()
    }

    private func handlePanelDidOpen() {
        dripSessionCount = 0
        isSearchMode = false
        composeDraft = ""
        searchHitRows = []
        searchDebounceTask?.cancel()
        notifySearchModePresence(active: false)
        postMainPanelSearchLayout()
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

    private var clampedListIndex: Int {
        let n = filteredListsForPicker.count
        guard n > 0 else { return 0 }
        return min(max(0, listPickerIndex), n - 1)
    }

    // MARK: - Input bar

    private var inputBarContent: some View {
        ZStack(alignment: .leading) {
            if taskText.isEmpty && slashQuery == nil {
                Text(
                    isSearchMode
                        ? "Search reminders…  ·  ⌘F to close"
                        : "Task…  ·  ⌘F search  ·  ⇧⏎ save & keep  ·  space + / for lists"
                )
                .font(.system(size: 18, weight: .light, design: .rounded))
                .foregroundColor(.primary.opacity(0.22))
                .allowsHitTesting(false)
                .padding(.horizontal, 22)
            }

            if !suggestion.isEmpty && !taskText.isEmpty && slashQuery == nil && !isSearchMode {
                HStack(spacing: 0) {
                    Text(taskText)
                        .foregroundColor(.clear)
                    Text(suggestion)
                        .foregroundColor(.primary.opacity(0.22))
                }
                .font(.system(size: 20, weight: .light, design: .rounded))
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
                    if !isSearchMode { saveTask(keepPanelOpen: false) }
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
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    if dripSessionCount > 6 {
                        Text("+\(dripSessionCount - 6)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.55))
                    }
                }
                .padding(.trailing, 14)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dripSessionCount)
            }
        }
    }

    // MARK: - `/` list picker

    private func listSlashQuery(from text: String) -> (base: String, filter: String)? {
        guard let slashIdx = text.lastIndex(of: "/") else { return nil }
        if slashIdx > text.startIndex {
            let prev = text[text.index(before: slashIdx)]
            if !prev.isWhitespace { return nil }
        }
        let base   = String(text[..<slashIdx]).trimmingCharacters(in: .whitespaces)
        let after  = text.index(after: slashIdx)
        let filter = after < text.endIndex ? String(text[after...]) : ""
        return (base, filter.lowercased())
    }

    private func syncListPickerAfterTextChange(_ newText: String) {
        if isSearchMode { listPickerIndex = 0; return }
        guard listSlashQuery(from: newText) != nil else { listPickerIndex = 0; return }
        let f  = listSlashQuery(from: newText)?.filter ?? ""
        let n  = lists.filter { f.isEmpty || $0.title.lowercased().contains(f) }.count
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
        let title  = rows[index].title
        let spacer = q.base.isEmpty ? "" : (q.base.hasSuffix(" ") ? "" : " ")
        taskText   = q.base + spacer + "in \(title) "
        listPickerIndex = 0
    }

    private func cancelListPicker() {
        guard let q = slashQuery else { return }
        taskText = q.base
        listPickerIndex = 0
    }

    // MARK: - Ghost suggestion

    private func updateSuggestion() {
        suggestion = ""
        if isSearchMode { return }
        if slashQuery != nil { return }
        guard !taskText.isEmpty else { return }
        let lower = taskText.lowercased()

        let timePatterns: [(trigger: String, completion: String)] = [
            ("at ",  "5:00 PM"),
            ("tod",  "ay at 5:00 PM"),
            ("tom",  "orrow at 9:00 AM"),
            ("thi",  "s evening at 7:00 PM"),
            ("nex",  "t Monday at 9:00 AM"),
            ("on ",  "Monday at 9:00 AM"),
        ]
        for (trigger, completion) in timePatterns {
            if lower.hasSuffix(trigger) { suggestion = completion; return }
        }

        let listTriggers = ["in ", "to "]
        for trigger in listTriggers {
            if lower.hasSuffix(trigger) {
                if let firstName = lists.first?.title { suggestion = firstName }
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

        if taskText == "!" { suggestion = "! task name  (!! medium, !!! high)"; return }
    }

    func acceptSuggestion() {
        guard !isSearchMode, !suggestion.isEmpty else { return }
        taskText  += suggestion
        suggestion = ""
        parseText()
        postIfChipsChanged()
    }

    // MARK: - Chip notification

    private func postIfChipsChanged() {
        if isSearchMode {
            let cleared = ChipSet(priority: 0, date: nil, showDatePill: false, showTimePill: false, listName: nil)
            guard cleared != lastPostedChipSet else { return }
            lastPostedChipSet = cleared
            postChipState()
            return
        }
        // BUG FIX: use actual `date: Date?` so a time-only change (5pm→6pm)
        // still registers as a different ChipSet and triggers a re-render.
        let current = ChipSet(
            priority: parsedPriority,
            date: parsedDate,
            showDatePill: showDatePill,
            showTimePill: showTimePill,
            listName: parsedList?.title
        )
        guard current != lastPostedChipSet else { return }
        lastPostedChipSet = current
        postChipState()
    }

    private func forcePostChipState() {
        lastPostedChipSet = ChipSet(priority: -1, date: nil, showDatePill: false, showTimePill: false, listName: nil)
        postIfChipsChanged()
    }

    private func postChipState() {
        NotificationCenter.default.post(
            name: NSNotification.Name("ParsedStateChanged"),
            object: nil,
            userInfo: [
                "date":         parsedDate as Any,
                "list":         parsedList?.title as Any,
                "priority":     parsedPriority,
                "showDatePill": showDatePill,
                "showTimePill": showTimePill,
                "glowDate":     showDatePill && parsedDate != nil,
                "glowTime":     showTimePill && parsedDate != nil,
            ]
        )
    }

    // MARK: - Styling

    private func priorityColor() -> Color {
        switch parsedPriority {
        case 1:  return PanelChrome.priorityHigh
        case 5:  return PanelChrome.priorityMed
        default: return PanelChrome.priorityLow
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
            attr[r].foregroundColor = priorityColor().opacity(0.45)
        }
        if let s = parsedDateString, let r = attr.range(of: s, options: .caseInsensitive) {
            attr[r].foregroundColor = PanelChrome.dateTime.opacity(0.45)
        }
        if let s = parsedListString, let r = attr.range(of: s, options: .caseInsensitive) {
            attr[r].foregroundColor = PanelChrome.listAccent.opacity(0.45)
        }
        return attr
    }

    // MARK: - Parse

    private func parseText() {
        if isSearchMode {
            parsedDate = nil; parsedDateString = nil
            parsedList = nil; parsedListString = nil
            parsedPriority = 0; parsedPriorityString = nil
            showDatePill = false; showTimePill = false
            return
        }
        parsedDate = nil; parsedDateString = nil
        parsedList = nil; parsedListString = nil
        parsedPriority = 0; parsedPriorityString = nil
        showDatePill = false; showTimePill = false
        guard !taskText.isEmpty else { return }

        if      taskText.hasPrefix("!!!") { parsedPriority = 1; parsedPriorityString = "!!!" }
        else if taskText.hasPrefix("!!")  { parsedPriority = 5; parsedPriorityString = "!!" }
        else if taskText.hasPrefix("!")   { parsedPriority = 9; parsedPriorityString = "!" }

        for list in lists {
            let pattern = "(?i)\\b(?:in|to)\\s+\\Q\(list.title)\\E\\b"
            if let range = taskText.range(of: pattern, options: .regularExpression) {
                parsedList       = list
                parsedListString = String(taskText[range])
                break
            }
        }

        let nd = NaturalDateParser.parse(text: taskText)
        parsedDate       = nd.date
        parsedDateString = nd.matchedSubstring
        if nd.date != nil {
            showDatePill = nd.hasDateComponent
            showTimePill = nd.hasTimeComponent
            if !showDatePill && !showTimePill { showTimePill = true }
        }
    }

    private func applyPriorityPrefixToTaskText() {
        var t = taskText
        while t.first == "!" { t.removeFirst() }
        t = t.trimmingCharacters(in: .whitespaces)
        let prefix: String
        switch parsedPriority {
        case 1:  prefix = "!!!"
        case 5:  prefix = "!!"
        case 9:  prefix = "!"
        default: prefix = ""
        }
        taskText = prefix.isEmpty ? t : (t.isEmpty ? prefix : prefix + " " + t)
    }

    // MARK: - Chip swipe actions

    private func applyChipSwipeDelete(kind: String) {
        switch kind {
        case "priority":
            var t = taskText
            while t.first == "!" { t.removeFirst() }
            taskText = t.trimmingCharacters(in: .whitespaces)
        case "date", "time":
            if let s = parsedDateString {
                taskText = taskText
                    .replacingOccurrences(of: s, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "list":
            if let s = parsedListString {
                taskText = taskText
                    .replacingOccurrences(of: s, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        default: break
        }
        parseText()
        postIfChipsChanged()
    }

    private func applyChipSwipeDuplicate(kind: String) {
        switch kind {
        case "list":
            if let s = parsedListString,
               taskText.range(of: s, options: .caseInsensitive) == nil {
                taskText = taskText.trimmingCharacters(in: .whitespacesAndNewlines) + " " + s
            }
        case "date", "time":
            if let s = parsedDateString {
                taskText = taskText.trimmingCharacters(in: .whitespacesAndNewlines) + " " + s
            }
        case "priority":
            // BUG FIX: was `else { taskText = "!!!" }` so swipe-right on High did nothing.
            // Now cycles: Low(9)→Medium(5)→High(1)→Low(9)
            let body = String(taskText.drop(while: { $0 == "!" })).trimmingCharacters(in: .whitespaces)
            switch parsedPriority {
            case 9:  taskText = "!! " + body   // low  → medium
            case 5:  taskText = "!!! " + body  // medium → high
            default: taskText = "! " + body    // high  → low
            }
        default: break
        }
        parseText()
        postIfChipsChanged()
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

        let dest     = parsedList ?? eventStore.defaultCalendarForNewReminders()
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
            ReminderHaptics.successSnap()
        } catch {
            NSSound.beep()
            return
        }

        let finalTitle     = cleanTitle
        let finalListTitle = dest?.title ?? "Reminders"
        var finalDateFmt: String?
        if let d = parsedDate {
            let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
            finalDateFmt = fmt.string(from: d)
        }

        if keepPanelOpen {
            dripSessionCount += 1
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { taskText = "" }
        } else {
            taskText = ""
            dripSessionCount = 0
        }
        suggestion = ""
        parseText()
        lastPostedChipSet = ChipSet(priority: 0, date: nil, showDatePill: false, showTimePill: false, listName: nil)
        postChipState()

        NotificationCenter.default.post(
            name: NSNotification.Name("TaskSaved"),
            object: nil,
            userInfo: [
                "title":         finalTitle,
                "list":          finalListTitle,
                "date":          finalDateFmt ?? "",
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
            guard !Task.isCancelled, isSearchMode else { return }
            let hits = await fetchMatchingReminders(query: query)
            guard !Task.isCancelled, isSearchMode else { return }
            searchHitRows = hits.map {
                SearchHitRowModel(id: $0.calendarItemIdentifier, title: $0.title, subtitle: reminderSubtitle(for: $0))
            }
            postMainPanelSearchLayout()
        }
    }

    private func fetchMatchingReminders(query: String) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let cals    = eventStore.calendars(for: .reminder)
            guard !trimmed.isEmpty, !cals.isEmpty else {
                continuation.resume(returning: []); return
            }
            let now   = Date()
            guard let start = Calendar.current.date(byAdding: .year, value: -2, to: now),
                  let end   = Calendar.current.date(byAdding: .year, value: 2,  to: now) else {
                continuation.resume(returning: []); return
            }
            let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: cals)
            eventStore.fetchReminders(matching: predicate) { reminders in
                let parts   = trimmed.lowercased().split(separator: " ").map(String.init)
                let matched = (reminders ?? []).filter { r in
                    let hay = (r.title + " " + (r.notes ?? "")).lowercased()
                    return parts.allSatisfy { hay.contains($0) }
                }.prefix(35)
                DispatchQueue.main.async { continuation.resume(returning: Array(matched)) }
            }
        }
    }

    private func reminderSubtitle(for reminder: EKReminder) -> String {
        let list = reminder.calendar?.title ?? ""
        if let due = reminder.dueDateComponents, let date = Calendar.current.date(from: due) {
            let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
            return [list, fmt.string(from: date)].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return list
    }

    private func openReminderInRemindersApp(id: String) {
        guard (eventStore.calendarItem(withIdentifier: id) as? EKReminder) != nil else {
            NSSound.beep(); return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
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

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = .popover
        v.blendingMode = .behindWindow
        v.state        = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
