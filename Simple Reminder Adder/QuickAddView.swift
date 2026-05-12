import SwiftUI
import EventKit

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
    
    // For Hover Effect on the Settings Button
    @State private var isHoveringSettings = false
    
    let eventStore = EKEventStore()

    let glassTransition = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.8, anchor: .trailing).combined(with: .move(edge: .trailing)).combined(with: .opacity),
        removal: .scale(scale: 0.8).combined(with: .opacity)
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            HStack(spacing: 12) {
                // 1. THE SMART TEXT FIELD
                ZStack(alignment: .leading) {
                    if taskText.isEmpty {
                        Text("Task (e.g., '!!! Gym at 5pm in Personal')")
                            .font(.system(size: 24, weight: .light, design: .rounded))
                            .foregroundColor(.gray.opacity(0.4))
                            .allowsHitTesting(false)
                    }
                    
                    Text(styledText(from: taskText))
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .allowsHitTesting(false)
                    
                    TextField("", text: $taskText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .foregroundColor(.clear)
                        .tint(.blue)
                        .focused($isInputFocused)
                        .onSubmit { saveTask() }
                }
                .onChange(of: taskText) { oldValue, newValue in
                    withAnimation(.easeInOut(duration: 0.2)) { parseText() }
                }
                
                // 🚨 NEW: Modern SwiftUI SettingsLink
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundColor(isHoveringSettings ? .primary : .gray.opacity(0.5))
                            .padding(6)
                            .background(isHoveringSettings ? Color.gray.opacity(0.2) : Color.clear)
                            .clipShape(Circle())
                            .animation(.easeInOut(duration: 0.15), value: isHoveringSettings)
                    }
                    .buttonStyle(.plain) // Removes the default ugly button background
                    .onHover { hovering in
                        isHoveringSettings = hovering
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    // Binds the native Command + Comma shortcut directly to this button!
                    .keyboardShortcut(",", modifiers: .command)
                    .simultaneousGesture(TapGesture().onEnded {
                        // Tell AppDelegate to hide the text bar when Settings opens
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.hidePanel()
                        }
                    })
                }
            }
            
            // 2. THE FLUID POP-UP UI (Chips)
            if parsedDate != nil || parsedList != nil || parsedPriority > 0 {
                HStack(spacing: 12) {
                    if parsedPriority > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(parsedPriority == 1 ? "High" : (parsedPriority == 5 ? "Medium" : "Low"))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(priorityColor())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(priorityColor().opacity(0.15))
                        .clipShape(Capsule())
                        .transition(glassTransition)
                    }
                    if let date = parsedDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                            Text(date, format: .dateTime.hour().minute().weekday().day())
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                        .transition(glassTransition)
                    }
                    if let list = parsedList {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet")
                            Text(list.title)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(Capsule())
                        .transition(glassTransition)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: parsedDate)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: parsedList)
            }
        }
        .padding(20)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            requestPermissionsAndFetchLists()
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PanelDidOpen"))) { _ in
            isInputFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isInputFocused = true
            }
        }
    }
    
    private func priorityColor() -> Color {
        if parsedPriority == 1 { return .red }
        if parsedPriority == 5 { return .yellow }
        return .blue
    }
    
    private func styledText(from text: String) -> AttributedString {
        var attrString = AttributedString(text)
        attrString.foregroundColor = .primary
        
        if let pStr = parsedPriorityString, let range = attrString.range(of: pStr) {
            attrString[range].foregroundColor = priorityColor().opacity(0.5)
        }
        if let dateStr = parsedDateString, let range = attrString.range(of: dateStr, options: .caseInsensitive) {
            attrString[range].foregroundColor = .orange.opacity(0.4)
        }
        if let listStr = parsedListString, let range = attrString.range(of: listStr, options: .caseInsensitive) {
            attrString[range].foregroundColor = .purple.opacity(0.4)
        }
        return attrString
    }
    
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
            let matches = detector.matches(in: taskText, options: [], range: NSRange(location: 0, length: taskText.utf16.count))
            if let match = matches.first, let date = match.date {
                if let baseRange = Range(match.range, in: taskText) {
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
    }
    
    private func saveTask() {
        guard !taskText.isEmpty else { return }
        var cleanTitle = taskText
        
        if let pStr = parsedPriorityString { cleanTitle = cleanTitle.replacingOccurrences(of: pStr, with: "") }
        if let dStr = parsedDateString { cleanTitle = cleanTitle.replacingOccurrences(of: dStr, with: "", options: .caseInsensitive) }
        if let lStr = parsedListString { cleanTitle = cleanTitle.replacingOccurrences(of: lStr, with: "", options: .caseInsensitive) }
        
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty { cleanTitle = "New Task" }
        
        let destinationList = parsedList ?? eventStore.defaultCalendarForNewReminders()
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = cleanTitle
        if let dest = destinationList { reminder.calendar = dest }
        reminder.priority = parsedPriority
        
        if let targetDate = parsedDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
            reminder.addAlarm(EKAlarm(absoluteDate: targetDate))
        }
        
        try? eventStore.save(reminder, commit: true)
        
        let finalTitle = cleanTitle
        let finalListTitle = destinationList?.title ?? "Reminders"
        
        var finalDateFormatted: String? = nil
        if let d = parsedDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            finalDateFormatted = formatter.string(from: d)
        }
        
        taskText = ""
        parseText()
        
        NotificationCenter.default.post(
            name: NSNotification.Name("TaskSaved"),
            object: nil,
            userInfo: [
                "title": finalTitle,
                "list": finalListTitle,
                "date": finalDateFormatted ?? ""
            ]
        )
    }
    
    private func requestPermissionsAndFetchLists() {
        Task {
            do {
                if #available(macOS 14.0, *) { try await eventStore.requestFullAccessToReminders() }
                else { try await eventStore.requestAccess(to: .reminder) }
                DispatchQueue.main.async { self.lists = eventStore.calendars(for: .reminder) }
            } catch { print("Permission error") }
        }
    }
}

// macOS native blur material structure
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
