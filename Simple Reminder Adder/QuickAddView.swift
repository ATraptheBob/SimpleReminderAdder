import SwiftUI
import AppKit
import EventKit

struct BubbleShape: Shape {
    var cornerRadius: CGFloat
    var tabProgress: CGFloat
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, tabProgress) }
        set { cornerRadius = newValue.first; tabProgress = newValue.second }
    }
    
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let tailH = 32 * tabProgress
        let h = rect.height - tailH
        let r = cornerRadius
        let tailW: CGFloat = 140
        let tailR: CGFloat = 16 * (tabProgress > 0 ? 1 : 0)
        let innerR: CGFloat = 12 * (tabProgress > 0 ? 1 : 0)
        
        let totalTailRadii = tailR + innerR
        let scale = totalTailRadii > 0 ? min(1.0, tailH / totalTailRadii) : 0.0
        
        let safeTailR = max(0, min(tailR * scale, tailW / 2))
        
        let maxInnerR = max(0, (w - tailW) / 2)
        let safeInnerR = max(0, min(innerR * scale, maxInnerR))
        
        // Prioritize top corners to prevent rectangular look when height collapses
        let rTop = max(0, min(r, h, w / 2))
        
        // Constrain bottom corners by remaining height and width outside the tail
        let maxBottomR = max(0, maxInnerR - safeInnerR)
        let rBottom = max(0, min(r, h - rTop, maxBottomR))
        
        if h <= 0.5 { // Only the tail is visible
            let tabRect = CGRect(x: (w - tailW) / 2, y: 0, width: tailW, height: tailH)
            p.addRoundedRect(in: tabRect, cornerSize: CGSize(width: safeTailR, height: safeTailR), style: .continuous)
            return p
        }
        
        if tabProgress == 0 {
            // Keep traditional rounding when the tail isn't drawn at all
            let uniformR = max(0, min(r, h / 2, w / 2))
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: uniformR, height: uniformR), style: .continuous)
            return p
        }
        
        p.move(to: CGPoint(x: rTop, y: 0))
        p.addLine(to: CGPoint(x: w - rTop, y: 0))
        p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: rTop), radius: rTop)
        
        p.addLine(to: CGPoint(x: w, y: h - rBottom))
        p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - rBottom, y: h), radius: rBottom)
        
        let tailMaxX = (w + tailW) / 2
        let tailMinX = (w - tailW) / 2
        
        p.addLine(to: CGPoint(x: tailMaxX + safeInnerR, y: h))
        p.addArc(tangent1End: CGPoint(x: tailMaxX, y: h), tangent2End: CGPoint(x: tailMaxX, y: h + safeInnerR), radius: safeInnerR)
        
        p.addLine(to: CGPoint(x: tailMaxX, y: h + tailH - safeTailR))
        p.addArc(tangent1End: CGPoint(x: tailMaxX, y: h + tailH), tangent2End: CGPoint(x: tailMaxX - safeTailR, y: h + tailH), radius: safeTailR)
        
        p.addLine(to: CGPoint(x: tailMinX + safeTailR, y: h + tailH))
        p.addArc(tangent1End: CGPoint(x: tailMinX, y: h + tailH), tangent2End: CGPoint(x: tailMinX, y: h + tailH - safeTailR), radius: safeTailR)
        
        p.addLine(to: CGPoint(x: tailMinX, y: h + safeInnerR))
        p.addArc(tangent1End: CGPoint(x: tailMinX, y: h), tangent2End: CGPoint(x: tailMinX - safeInnerR, y: h), radius: safeInnerR)
        
        p.addLine(to: CGPoint(x: rBottom, y: h))
        p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - rBottom), radius: rBottom)
        
        p.addLine(to: CGPoint(x: 0, y: rTop))
        p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: rTop, y: 0), radius: rTop)
        
        p.closeSubpath()
        return p
    }
}

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
    static let undoLastTask                = Notification.Name("UndoLastTask")
    static let toggleDictation             = Notification.Name("ToggleDictation")
    static let searchNavigate              = Notification.Name("SearchNavigate")
    static let searchConfirm               = Notification.Name("SearchConfirm")
    static let escapePressed               = Notification.Name("EscapePressed")
    static let hidePanelRequest            = Notification.Name("HidePanelRequest")
    static let panelDidClose               = Notification.Name("PanelDidClose")
    static let searchResultComplete        = Notification.Name("SearchResultComplete")
    static let searchCompleteSelected      = Notification.Name("SearchCompleteSelected")
    static let searchDeleteSelected        = Notification.Name("SearchDeleteSelected")
    static let searchResultDelete          = Notification.Name("SearchResultDelete")
    static let upArrowRecall               = Notification.Name("UpArrowRecall")
    static let textContentSizeChanged      = Notification.Name("TextContentSizeChanged")
    static let waveformTabVisibilityChanged = Notification.Name("WaveformTabVisibilityChanged")
    static let idleModeChanged             = Notification.Name("IdleModeChanged")
}

private struct ChipSet: Equatable {
    var priority: Int
    var date: Date?
    var showDatePill: Bool
    var showTimePill: Bool
    var listName: String?
    var recurrenceText: String?
    var locationTitle: String?
}
private struct SearchIndexRow: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let searchText: String
    let dueDate: Date?
    let isCompleted: Bool
}

private let inputBarHeight: CGFloat = 58
private let listPickerSpacing: CGFloat = 6
private let listPickerMaxScroll: CGFloat = 220

private let sharedDateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .short
    fmt.timeStyle = .short
    return fmt
}()

private let searchIndexMaxEntries = 500

struct QuickAddView: View {
    @Environment(\.openSettings) private var openSettings
    
    private let eventStore = EKEventStore()

    @State private var taskText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var previousTaskTextLength: Int = 0
    @State private var lists: [EKCalendar] = []
    @State private var listRegexCache: [(EKCalendar, NSRegularExpression)] = []

    @State private var parsedDate: Date?        = nil
    @State private var parsedDateString: String? = nil
    @State private var parsedList: EKCalendar?  = nil
    @State private var parsedListString: String? = nil
    @State private var parsedPriority: Int      = 0
    @State private var parsedPriorityString: String? = nil
    @State private var saveFlashActive = false
    @State private var parsedRecurrence: EKRecurrenceRule? = nil
    @State private var parsedRecurrenceString: String? = nil
    @State private var parsedLocationTitle: String? = nil
    @State private var parsedLocationString: String? = nil
    @State private var parsedLocationIsArriving: Bool = true

    @State private var suggestion: String = ""
    @State private var lastPostedChipSet = ChipSet(priority: 0, date: nil, showDatePill: false, showTimePill: false, listName: nil, recurrenceText: nil, locationTitle: nil)

    @State private var showDatePill: Bool = false
    @State private var showTimePill: Bool = false

    @State private var listPickerIndex: Int = 0
    @State private var dripSessionCount: Int = 0
    @State private var listPickerLayoutOpenState: Bool = false
    @State private var isSearchMode: Bool = false
    @State private var composeDraft: String = ""
    @State private var searchHitRows: [SearchHitRowModel] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var searchIndexRows: [SearchIndexRow] = []
    @State private var searchIndexTask: Task<Void, Never>?
    @State private var searchSelectedIndex: Int = 0

    @State private var showDraftRestoredBadge: Bool = false
    @AppStorage("draftInput") private var savedDraft: String = ""
    @AppStorage("lastAddedText") private var lastAddedText: String = ""
    @AppStorage("keepPanelOpen") private var keepPanelOpenSetting: Bool = false

    @StateObject private var dictation = VoiceDictationManager()

    // MARK: - Computed States

    private var isIdleMode: Bool {
        taskText.isEmpty && !isSearchMode && slashQuery == nil
    }

    private var effectiveCornerRadius: CGFloat {
        isIdleMode ? PanelChrome.pillCorner : PanelChrome.outerCorner
    }

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
        if searchHitRows.isEmpty {
            return 60 // Height for empty state "Type to filter reminders"
        }
        // Approximate row height (~54) + container padding (~36)
        let calculatedHeight = CGFloat(searchHitRows.count) * 54.0 + 36.0
        return min(260, calculatedHeight)
    }

    private var showDefaultPill: Bool {
        !isSearchMode && slashQuery == nil && parsedList == nil && !taskText.isEmpty
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
        let step1 = mainContent
            .onChange(of: taskText) { _, new in
                if dictation.isListening {
                    if new != dictation.transcript {
                        dictation.syncManualEdit(to: new)
                    }
                }
                previousTaskTextLength = new.count
                handleTaskTextChange(new)
                postTextContentSize(for: new)
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

        let step2 = step1
            .onReceive(NotificationCenter.default.publisher(for: .upArrowRecall)) { _ in
                handleUpArrowRecall()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenSettingsRequest"))) { _ in
                openSettings()
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
            .onReceive(NotificationCenter.default.publisher(for: .listPickerCancel)) { _ in
                cancelListPicker()
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickAddShiftReturnSave)) { _ in
                guard !isSearchMode else { return }
                saveTask(keepPanelOpen: true)
            }

        let step3 = step2
            .onReceive(NotificationCenter.default.publisher(for: .searchHotkeyToggle)) { _ in
                toggleSearchModeFromHotkey()
            }
            .onReceive(NotificationCenter.default.publisher(for: .forceExitSearchMode)) { _ in
                if isSearchMode {
                    isSearchMode = false
                    taskText = composeDraft
                    composeDraft = ""
                    searchHitRows = []
                    searchIndexRows = []
                    searchIndexTask?.cancel()
                    searchDebounceTask?.cancel()
                    postMainPanelSearchLayout()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchResultActivate)) { note in
                guard let id = note.userInfo?["id"] as? String else { return }
                openReminderInRemindersApp(id: id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleDictation)) { _ in
                handleDictationToggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchNavigate)) { note in
                guard let d = note.userInfo?["delta"] as? Int else { return }
                moveSearchSelection(delta: d)
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchConfirm)) { _ in
                activateSearchSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in
                if dictation.isListening {
                    dictation.stopListening()
                    return
                }
                if isSearchMode {
                    isInputFocused = false
                    isSearchMode = false
                    taskText = composeDraft
                    composeDraft = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.isInputFocused = true
                    }
                    return
                }
                if let currentSlash = slashQuery {
                    taskText = currentSlash.base
                    isInputFocused = true
                    return
                }
                NotificationCenter.default.post(name: .hidePanelRequest, object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .panelDidClose)) { _ in
                if dictation.isListening { dictation.stopListening() }
                if !taskText.isEmpty {
                    savedDraft = taskText
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchResultComplete)) { note in
                guard let id = note.userInfo?["id"] as? String else { return }
                self.completeReminder(id: id)
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchResultDelete)) { note in
                guard let id = note.userInfo?["id"] as? String else { return }
                self.deleteReminder(id: id)
            }

        let step4 = step3
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UndoLastTask"))) { note in
                guard let id = note.userInfo?["reminderID"] as? String,
                      let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
                do {
                    try eventStore.remove(reminder, commit: true)
                    ReminderHaptics.successSnap()
                    // Brief visual ack — reuse the flash in reverse tint
                    withAnimation(.easeOut(duration: 0.15)) { saveFlashActive = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.2)) { saveFlashActive = false }
                    }
                } catch {
                    NSSound.beep()
                }
            }
        
        let step5 = step4
            // Stream dictation transcript into the text field
            .onReceive(dictation.$transcript) { text in
                guard dictation.isListening, !text.isEmpty else { return }
                previousTaskTextLength = text.count
                taskText = text
            }
        
        return step5
    }

    // MARK: - Body

    // Use a derived state for the tab progress to smoothly animate its appearance
    private var isTabVisible: Bool {
        dictation.isListening || isIdleMode
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            
            if isSearchMode {
                SearchResultsMenuView(hits: searchHitRows, selectedIndex: searchSelectedIndex)
                    .padding(.horizontal, 6)
                    .padding(.bottom, listPickerSpacing)
                    .padding(.top, 6)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal:   .opacity.animation(.easeOut(duration: 0.08))
                        )
                    )
            }
            
            if slashQuery != nil {
                ListPickerView(
                    calendars: filteredListsForPicker,
                    selectedIndex: clampedListIndex,
                    onSelectIndex: { applyListPick(at: $0) }
                )
                .padding(.horizontal, 6)
                .padding(.bottom, listPickerSpacing)
                .padding(.top, 6)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal:   .opacity.animation(.easeOut(duration: 0.08))
                    )
                )
            }

            inputBarContent
            
            if isTabVisible {
                waveformTab
                    .frame(height: 32)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.08))))
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom) // Bottom alignment is important for upward expansion
        .background(VisualEffectView())
        .clipShape(BubbleShape(cornerRadius: effectiveCornerRadius, tabProgress: isTabVisible ? 1.0 : 0.0))
        .overlay(
            BubbleShape(cornerRadius: effectiveCornerRadius, tabProgress: isTabVisible ? 1.0 : 0.0)
                .stroke(PanelChrome.strokeSubtle, lineWidth: 1)
        )
        .animation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.28), value: effectiveCornerRadius)
        .animation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.28), value: isTabVisible)
        .animation(.timingCurve(0.16, 1.0, 0.3, 1.0, duration: 0.28), value: isIdleMode)
        .onChange(of: isTabVisible) { _, newValue in
            NotificationCenter.default.post(
                name: .waveformTabVisibilityChanged,
                object: nil,
                userInfo: ["visible": newValue]
            )
        }
        .onChange(of: isIdleMode) { _, newValue in
            NotificationCenter.default.post(
                name: .idleModeChanged,
                object: nil,
                userInfo: ["isIdle": newValue]
            )
        }
    }
    
    private var waveformTab: some View {
        HStack(spacing: 3) {
            Spacer()
            ForEach(0..<16, id: \.self) { i in
                let multiplier = CGFloat(sin(Double(i) * 0.5) * 0.35 + 0.65)
                let baseHeight: CGFloat = dictation.isListening
                    ? CGFloat(dictation.liveAmplitude) * 20 * multiplier
                    : 3.0 * multiplier
                let h = max(2.5, min(24, baseHeight))
                Capsule()
                    .fill(
                        dictation.isListening
                            ? LinearGradient(
                                colors: [Color.red.opacity(0.75), PanelChrome.accentColor.opacity(0.85)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                            : LinearGradient(
                                colors: [Color.primary.opacity(0.15), Color.primary.opacity(0.25)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                    )
                    .frame(width: 3, height: h)
                    .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.65), value: dictation.liveAmplitude)
            }
            Spacer()
        }
        .frame(width: 140)
        .allowsHitTesting(false)
    }

    // MARK: - Handlers

    private func handleTaskTextChange(_ new: String) {
        // SECURITY ENHANCEMENT: Enforce maximum input length to prevent CPU exhaustion/ReDoS
        let maxLength = 500
        if new.count > maxLength {
            let truncated = String(new.prefix(maxLength))
            DispatchQueue.main.async {
                self.taskText = truncated
            }
            return // Exit early to avoid parsing the oversized text. The update will trigger a new change event.
        }

        // BUG FIX: call listSlashQuery once and reuse the result
        let currentSlash = listSlashQuery(from: new)
        let open = !isSearchMode && (currentSlash != nil)
        if open != listPickerLayoutOpenState {
            if open { listPickerIndex = 0 }
            listPickerLayoutOpenState = open
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                NotificationCenter.default.post(
                    name: .mainPanelListPickerLayout,
                    object: nil,
                    userInfo: ["open": open]
                )
            }
        }
        syncListPickerAfterTextChange(slashResult: currentSlash)
        parseText()
        updateSuggestion()
        postIfChipsChanged()
        if isSearchMode { scheduleSearchRefresh() }
    }

    private func handleSearchModeChange(_ active: Bool) {
        notifySearchModePresence(active: active)
        if active {
            searchSelectedIndex = 0
            searchHitRows = []
            searchIndexRows = []
            refreshSearchIndex()
            scheduleSearchRefresh()
        } else {
            searchDebounceTask?.cancel()
            searchIndexTask?.cancel()
            searchHitRows = []
            searchIndexRows = []
            searchSelectedIndex = 0
        }
        postMainPanelSearchLayout()
    }

    private func handlePanelDidOpen() {
        dripSessionCount = 0
        isSearchMode = false
        composeDraft = ""
        searchHitRows = []
        searchDebounceTask?.cancel()
        searchIndexRows = []
        searchIndexTask?.cancel()
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
        // Stop dictation if panel re-opened
        if dictation.isListening { dictation.stopListening() }
        isInputFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isInputFocused = true
            forcePostChipState()
        }
    }

    // MARK: - Up-arrow recall

    private func handleUpArrowRecall() {
        guard !isSearchMode, taskText.isEmpty else { return }
        
        if !savedDraft.isEmpty {
            taskText = savedDraft
            savedDraft = ""
            showDraftRestoredBadge = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showDraftRestoredBadge = false
                }
            }
        } else if !lastAddedText.isEmpty {
            taskText = lastAddedText
        } else {
            return
        }
        
        parseText()
        updateSuggestion()
        postIfChipsChanged()
    }

    private var clampedListIndex: Int {
        let n = filteredListsForPicker.count
        guard n > 0 else { return 0 }
        return min(max(0, listPickerIndex), n - 1)
    }

    // MARK: - Voice dictation

    private func handleDictationToggle() {
        dictation.toggle(prefix: taskText)
    }

    // MARK: - Input bar

    private var inputBarContent: some View {
        ZStack(alignment: .leading) {
            // Placeholder
            if taskText.isEmpty && slashQuery == nil && !isIdleMode {
                Text(
                    isSearchMode
                        ? "Search reminders…  ·  ⌘F to close"
                        : "Task…  ·  ⌘F search  ·  ⇧⏎ keep open"
                )
                .font(.system(size: 18, weight: .light, design: .rounded))
                .foregroundColor(.primary.opacity(0.30))
                .lineLimit(1)
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
                .lineLimit(1)
                .allowsHitTesting(false)
                .padding(.horizontal, 22)
            }

            Text(styledText(from: taskText))
                .font(.system(size: 20, weight: .light, design: .rounded))
                .lineLimit(1)
                .allowsHitTesting(false)
                .padding(.horizontal, 22)

            TextField("", text: $taskText)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .light, design: .rounded))
                .foregroundColor(.clear)
                .tint(.primary.opacity(0.6))
                .lineLimit(1)
                .focused($isInputFocused)
                .id(isSearchMode ? "search" : "compose")
                .onSubmit {
                    if !isSearchMode { saveTask(keepPanelOpen: keepPanelOpenSetting) }
                }
                .padding(.horizontal, 22)
                .accessibilityLabel(isSearchMode ? "Search reminders" : "New reminder")
                .accessibilityHint(isSearchMode ? "Type to search" : "Type your reminder and press Return to save")

            // Save-success flash overlay
            if saveFlashActive {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hue: 0.36, saturation: 0.32, brightness: 0.72).opacity(0.75))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    Spacer()
                }
                .allowsHitTesting(false)
            }


        }
        .frame(height: isIdleMode ? 0 : inputBarHeight, alignment: .center)
        .opacity(isIdleMode ? 0 : 1)
        .clipped()
        .transaction { transaction in
            transaction.animation = nil
        }
        .overlay(alignment: .bottomLeading) {
            // Draft restored indicator
            if showDraftRestoredBadge {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 9))
                    Text("Draft restored")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.primary.opacity(0.05))
                )
                .padding(.leading, 22)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomLeading)))
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            // Hide trailing controls in idle mode
            if !isIdleMode {
                HStack(spacing: 6) {
                    Button {
                        handleDictationToggle()
                    } label: {
                        Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(dictation.isListening ? Color.red.opacity(0.8) : .secondary.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(dictation.isListening ? Color.red.opacity(0.1) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.isListening ? "Stop Voice Dictation" : "Start Voice Dictation")

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
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .animation(.spring(response: 0.15, dampingFraction: 0.8), value: dripSessionCount)
                    }
                }
                .padding(.trailing, 14)
                .transition(.opacity)
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

    // BUG FIX: accept pre-computed slashResult to avoid re-calling listSlashQuery
    private func syncListPickerAfterTextChange(slashResult: (base: String, filter: String)?) {
        if isSearchMode { listPickerIndex = 0; return }
        guard let slash = slashResult else { listPickerIndex = 0; return }
        let f = slash.filter
        let n = lists.filter { f.isEmpty || $0.title.lowercased().contains(f) }.count
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
            let cleared = ChipSet(priority: 0, date: nil, showDatePill: false, showTimePill: false, listName: nil, recurrenceText: nil, locationTitle: nil)
            guard cleared != lastPostedChipSet else { return }
            lastPostedChipSet = cleared
            postChipState()
            return
        }
        // BUG FIX: use actual `date: Date?` so a time-only change (5pm→6pm)
        let effectiveList = parsedList?.title ?? (showDefaultPill ? lists.first?.title : nil)
        let current = ChipSet(
            priority: parsedPriority,
            date: parsedDate,
            showDatePill: showDatePill,
            showTimePill: showTimePill,
            listName: effectiveList,
            recurrenceText: parsedRecurrenceString,
            locationTitle: parsedLocationTitle
        )
        guard current != lastPostedChipSet else { return }
        lastPostedChipSet = current
        postChipState()
    }

    private func forcePostChipState() {
        lastPostedChipSet = ChipSet(priority: -1, date: nil, showDatePill: false, showTimePill: false, listName: nil, recurrenceText: nil, locationTitle: nil)
        postIfChipsChanged()
    }

    private func postChipState() {
        let effectiveList = parsedList?.title ?? (showDefaultPill ? lists.first?.title : nil)
        NotificationCenter.default.post(
            name: NSNotification.Name("ParsedStateChanged"),
            object: nil,
            userInfo: [
                "date":         parsedDate as Any,
                "list":         effectiveList as Any,
                "priority":     parsedPriority,
                "showDatePill": showDatePill,
                "showTimePill": showTimePill,
                "glowDate":     showDatePill && parsedDate != nil,
                "glowTime":     showTimePill && parsedDate != nil,
                "recurrenceText": parsedRecurrenceString as Any,
                "locationTitle": parsedLocationTitle as Any
            ]
        )
    }

    // MARK: - Layout text width reporting
    private func postTextContentSize(for text: String) {
        let nsText = text as NSString
        let font = NSFont.systemFont(ofSize: 20, weight: .light)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let width = nsText.size(withAttributes: attrs).width
        NotificationCenter.default.post(
            name: .textContentSizeChanged,
            object: nil,
            userInfo: ["textWidth": width]
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
        if let s = parsedRecurrenceString, let r = attr.range(of: s, options: .caseInsensitive) {
            attr[r].foregroundColor = PanelChrome.dateTime.opacity(0.45)
        }
        if let s = parsedLocationString, let r = attr.range(of: s, options: .caseInsensitive) {
            attr[r].foregroundColor = PanelChrome.listAccent.opacity(0.45)
        }
        return attr
    }

    // MARK: - Parse

    private func parseText() {
        if isSearchMode {
            parsedRecurrence = nil; parsedRecurrenceString = nil
            parsedLocationTitle = nil; parsedLocationString = nil
            parsedDate = nil; parsedDateString = nil
            parsedList = nil; parsedListString = nil
            parsedPriority = 0; parsedPriorityString = nil
            showDatePill = false; showTimePill = false
            return
        }
        parsedRecurrence = nil; parsedRecurrenceString = nil
        parsedLocationTitle = nil; parsedLocationString = nil
        parsedDate = nil; parsedDateString = nil
        parsedList = nil; parsedListString = nil
        parsedPriority = 0; parsedPriorityString = nil
        showDatePill = false; showTimePill = false
        guard !taskText.isEmpty else { return }

        if      taskText.hasPrefix("!!!") { parsedPriority = 1; parsedPriorityString = "!!!" }
        else if taskText.hasPrefix("!!")  { parsedPriority = 5; parsedPriorityString = "!!" }
        else if taskText.hasPrefix("!")   { parsedPriority = 9; parsedPriorityString = "!" }

        let nsText = taskText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for (list, regex) in listRegexCache {
            if let match = regex.firstMatch(in: taskText, options: [], range: fullRange),
               let range = Range(match.range, in: taskText) {
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
        
        if let rec = NaturalDateParser.parseRecurrence(text: taskText) {
            parsedRecurrence       = rec.rule
            parsedRecurrenceString = rec.matchedSubstring
        }
        
        if let loc = NaturalDateParser.parseLocation(text: taskText) {
            parsedLocationTitle = loc.title
            parsedLocationIsArriving = loc.isArriving
            parsedLocationString = loc.matchedSubstring
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
        case "recurrence":
            if let s = parsedRecurrenceString {
                taskText = taskText
                    .replacingOccurrences(of: s, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case "location":
            if let s = parsedLocationString {
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

        // Stop dictation on save, or restart if keeping panel open
        if dictation.isListening {
            if keepPanelOpen {
                dictation.markTranscriptCommitted()
            } else {
                dictation.stopListening()
            }
        }

        var cleanTitle = taskText
        if let s = parsedPriorityString   { cleanTitle = cleanTitle.replacingOccurrences(of: s, with: "") }
        if let s = parsedDateString       { cleanTitle = cleanTitle.replacingOccurrences(of: s, with: "", options: .caseInsensitive) }
        if let s = parsedListString       { cleanTitle = cleanTitle.replacingOccurrences(of: s, with: "", options: .caseInsensitive) }
        if let s = parsedRecurrenceString { cleanTitle = cleanTitle.replacingOccurrences(of: s, with: "", options: .caseInsensitive) }
        if let s = parsedLocationString   { cleanTitle = cleanTitle.replacingOccurrences(of: s, with: "", options: .caseInsensitive) }
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // SECURITY ENHANCEMENT: Strip control/formatting characters to prevent UI spoofing
        cleanTitle = cleanTitle.replacingOccurrences(of: "\\p{Cc}", with: "", options: .regularExpression)
        if cleanTitle.isEmpty { cleanTitle = "New Task" }

        let dest     = parsedList ?? eventStore.defaultCalendarForNewReminders()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title    = cleanTitle
        if let dest { reminder.calendar = dest }
        reminder.priority = parsedPriority
        if let d = parsedDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            reminder.addAlarm(EKAlarm(absoluteDate: d))
        }
        if let rule = parsedRecurrence {
            reminder.recurrenceRules = [rule]
        }
        if let locationTitle = parsedLocationTitle {
            let alarm = EKAlarm()
            let loc = EKStructuredLocation(title: locationTitle)
            alarm.structuredLocation = loc
            alarm.proximity = parsedLocationIsArriving ? .enter : .leave
            reminder.addAlarm(alarm)
        }
        do {
            try eventStore.save(reminder, commit: true)
            ReminderHaptics.successSnap()
        } catch {
            NSSound.beep()
            return
        }

        let savedID        = reminder.calendarItemIdentifier
        let finalTitle     = cleanTitle
        let finalListTitle = dest?.title ?? "Reminders"
        // BUG FIX: use cached DateFormatter instead of creating one per save
        var finalDateFmt: String?
        if let d = parsedDate {
            finalDateFmt = sharedDateFormatter.string(from: d)
        }

        // Brief success flash
        withAnimation(.spring(response: 0.12, dampingFraction: 0.7)) { saveFlashActive = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.2)) { saveFlashActive = false }
        }

        // Store for up-arrow recall
        lastAddedText = taskText
        // Clear saved draft since we've successfully submitted
        savedDraft = ""

        if keepPanelOpen {
            dripSessionCount += 1
            withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) { taskText = "" }
        } else {
            taskText = ""
            dripSessionCount = 0
        }
        suggestion = ""
        parsedRecurrence = nil; parsedRecurrenceString = nil
        parsedLocationTitle = nil; parsedLocationString = nil
        parseText()
        lastPostedChipSet = ChipSet(priority: 0, date: nil, showDatePill: false, showTimePill: false, listName: nil, recurrenceText: nil, locationTitle: nil)
        postChipState()

        NotificationCenter.default.post(
            name: NSNotification.Name("TaskSaved"),
            object: nil,
            userInfo: [
                "title":         finalTitle,
                "list":          finalListTitle,
                "date":          finalDateFmt ?? "",
                "keepPanelOpen": keepPanelOpen,
                "reminderID":    savedID,           // ← used by ⌘Z undo
            ]
        )
    }

    // MARK: - Search (⌘F)

    private func toggleSearchModeFromHotkey() {
        isInputFocused = false
        if isSearchMode {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                isSearchMode = false
            }
            taskText = composeDraft
            composeDraft = ""
        } else {
            composeDraft = taskText
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                isSearchMode = true
            }
            taskText = ""
            suggestion = ""
        }
        parseText()
        updateSuggestion()
        postIfChipsChanged()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.isInputFocused = true
        }
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
            searchHitRows = filterSearchIndex(query: query, rows: searchIndexRows)
            searchSelectedIndex = 0
            postMainPanelSearchLayout()
        }
    }

    private func refreshSearchIndex() {
        guard isSearchMode else { return }
        searchIndexTask?.cancel()
        searchIndexTask = Task { @MainActor in
            let rows = await fetchSearchIndexRows()
            guard !Task.isCancelled, isSearchMode else { return }
            searchIndexRows = rows
            searchHitRows = filterSearchIndex(query: taskText, rows: rows)
            postMainPanelSearchLayout()
        }
    }

    private func fetchSearchIndexRows() async -> [SearchIndexRow] {
        await withCheckedContinuation { continuation in
            let cals    = eventStore.calendars(for: .reminder)
            guard !cals.isEmpty else {
                continuation.resume(returning: []); return
            }
            let predicate = eventStore.predicateForReminders(in: cals)
            eventStore.fetchReminders(matching: predicate) { reminders in
                let rows = (reminders ?? [])
                    .filter { !$0.isCompleted }
                    .sorted { lhs, rhs in
                        // Sort before limiting so we keep the most relevant entries
                        let ld = self.dueDate(for: lhs)
                        let rd = self.dueDate(for: rhs)
                        switch (ld, rd) {
                        case let (l?, r?): return l < r
                        case (_?, nil): return true
                        case (nil, _?): return false
                        // BUG FIX: guard against nil titles to prevent crash
                        case (nil, nil): return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "") == .orderedAscending
                        }
                    }
                    // PERF: limit to searchIndexMaxEntries to prevent unbounded memory
                    .prefix(searchIndexMaxEntries)
                    .map { reminder -> SearchIndexRow in
                        let title = reminder.title ?? ""
                        let subtitle = self.reminderSubtitle(for: reminder)
                        let dueDate = self.dueDate(for: reminder)
                        return SearchIndexRow(
                            id: reminder.calendarItemIdentifier,
                            title: title,
                            subtitle: subtitle,
                            searchText: self.normalizedSearchText([title, reminder.notes ?? "", subtitle].joined(separator: " ")),
                            dueDate: dueDate,
                            isCompleted: reminder.isCompleted
                        )
                    }
                // BUG FIX: resume directly instead of wrapping in DispatchQueue.main.async
                // The continuation is already on @MainActor; double-dispatch causes a frame drop.
                continuation.resume(returning: Array(rows))
            }
        }
    }

    private func filterSearchIndex(query: String, rows: [SearchIndexRow]) -> [SearchHitRowModel] {
        let parts = normalizedSearchParts(query)
        guard !parts.isEmpty else { return [] }
        return Array(
            rows.lazy
                .filter { row in parts.allSatisfy { row.searchText.contains($0) } }
                .prefix(35)
                .map { SearchHitRowModel(id: $0.id, title: $0.title, subtitle: $0.subtitle, isCompleted: $0.isCompleted, dueDate: $0.dueDate) }
        )
    }

    private func normalizedSearchParts(_ text: String) -> [String] {
        normalizedSearchText(text)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
    }

    private func normalizedSearchText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func dueDate(for reminder: EKReminder) -> Date? {
        guard let due = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: due)
    }

    // BUG FIX: use cached DateFormatter instead of creating one per row
    private func reminderSubtitle(for reminder: EKReminder) -> String {
        let list = reminder.calendar?.title ?? ""
        if let date = dueDate(for: reminder) {
            return [list, sharedDateFormatter.string(from: date)].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return list
    }

    private func openReminderInRemindersApp(id: String) {
        guard (eventStore.calendarItem(withIdentifier: id) as? EKReminder) != nil else {
            NSSound.beep(); return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
    }

    // MARK: - Search keyboard navigation

    func moveSearchSelection(delta: Int) {
        guard isSearchMode, !searchHitRows.isEmpty else { return }
        let n = searchHitRows.count
        searchSelectedIndex = ((searchSelectedIndex + delta) % n + n) % n
    }

    func activateSearchSelection() {
        guard isSearchMode, !searchHitRows.isEmpty else { return }
        let idx = min(max(0, searchSelectedIndex), searchHitRows.count - 1)
        openReminderInRemindersApp(id: searchHitRows[idx].id)
    }

    private func requestPermissionsAndFetchLists() {
        Task {
            do {
                if #available(macOS 14.0, *) { try await eventStore.requestFullAccessToReminders() }
                else { try await eventStore.requestAccess(to: .reminder) }
                await MainActor.run {
                    self.lists = eventStore.calendars(for: .reminder)
                    self.precompileListRegexes(for: self.lists)
                }
            } catch { print("Permission error: Failed to acquire reminders access.") }
        }
    }

    private func precompileListRegexes(for calendars: [EKCalendar]) {
        self.listRegexCache = calendars.compactMap { list in
            let escapedListTitle = NSRegularExpression.escapedPattern(for: list.title)
            let pattern = "(?i)\\b(?:in|to)\\s+\(escapedListTitle)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (list, regex)
        }
    }
    
    // MARK: - Pre-compiled recurrence patterns
    // ⚡ Bolt: Pre-compiling NSRegularExpression objects here rather than inside
    // `parseRecurrence` to avoid redundant allocations on every keystroke. This
    // speeds up parsing considerably since creating regexes is expensive.

    private static let freqPatterns: [(NSRegularExpression, EKRecurrenceFrequency)] = {
        let patterns: [(String, EKRecurrenceFrequency)] = [
            (#"(?i)\bevery\s+day\b"#,   .daily),
            (#"(?i)\bdaily\b"#,         .daily),
            (#"(?i)\bevery\s+week\b"#,  .weekly),
            (#"(?i)\bweekly\b"#,        .weekly),
            (#"(?i)\bevery\s+month\b"#, .monthly),
            (#"(?i)\bmonthly\b"#,       .monthly),
            (#"(?i)\bevery\s+year\b"#,  .yearly),
            (#"(?i)\bannually\b"#,      .yearly),
            (#"(?i)\byearly\b"#,        .yearly),
        ]
        return patterns.compactMap { (pattern, freq) in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, freq)
        }
    }()

    private static let weekdayPatterns: [(NSRegularExpression, EKWeekday)] = {
        let weekdayMap: [(String, EKWeekday)] = [
            ("monday", .monday), ("tuesday", .tuesday), ("wednesday", .wednesday),
            ("thursday", .thursday), ("friday", .friday),
            ("saturday", .saturday), ("sunday", .sunday),
        ]
        return weekdayMap.compactMap { (name, wd) in
            let pattern = "(?i)\\bevery\\s+\(name)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (regex, wd)
        }
    }()

    // MARK: - Recurrence parsing

    private func parseRecurrence(from text: String) -> (rule: EKRecurrenceRule?, matchedString: String?) {
        let ns   = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Simple frequency patterns
        for (re, freq) in Self.freqPatterns {
            if let m  = re.firstMatch(in: text, options: [], range: full),
               let r  = Range(m.range, in: text) {
                let rule = EKRecurrenceRule(recurrenceWith: freq, interval: 1, end: nil)
                return (rule, String(text[r]))
            }
        }

        // "Every <weekday>" → weekly on that day
        for (re, wd) in Self.weekdayPatterns {
            if let m  = re.firstMatch(in: text, options: [], range: full),
               let r  = Range(m.range, in: text) {
                let rule = EKRecurrenceRule(
                    recurrenceWith: .weekly,
                    interval: 1,
                    daysOfTheWeek: [EKRecurrenceDayOfWeek(wd)],
                    daysOfTheMonth: nil,
                    monthsOfTheYear: nil,
                    weeksOfTheYear: nil,
                    daysOfTheYear: nil,
                    setPositions: nil,
                    end: nil
                )
                return (rule, String(text[r]))
            }
        }
        return (nil, nil)
    }

    private func completeReminder(id: String) {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
        do {
            reminder.isCompleted = true
            try eventStore.save(reminder, commit: true)
            ReminderHaptics.successSnap()
            refreshSearchIndex()
        } catch {
            NSSound.beep()
        }
    }

    private func deleteReminder(id: String) {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
        do {
            try eventStore.remove(reminder, commit: true)
            ReminderHaptics.successSnap()
            refreshSearchIndex()
        } catch {
            NSSound.beep()
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
