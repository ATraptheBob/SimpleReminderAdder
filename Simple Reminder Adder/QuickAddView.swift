import SwiftUI
import EventKit

struct QuickAddView: View {
    @State private var taskText: String = ""
    @State private var lists: [EKCalendar] = []
    
    // 🚨 NEW: Focus State to auto-jump the cursor
    @FocusState private var isInputFocused: Bool
    
    // Intelligence State
    @State private var parsedDate: Date? = nil
    @State private var parsedDateString: String? = nil
    @State private var parsedList: EKCalendar? = nil
    @State private var parsedListString: String? = nil
    
    // Priority State
    @State private var parsedPriority: Int = 0 // 0=None, 1=High, 5=Medium, 9=Low
    @State private var parsedPriorityString: String? = nil
    
    let eventStore = EKEventStore()

    // 🚨 NEW: The fluid "Liquid Glass" animation transition
    let glassTransition = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.8, anchor: .trailing)
            .combined(with: .move(edge: .trailing))
            .combined(with: .opacity),
        removal: .scale(scale: 0.8).combined(with: .opacity)
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // 1. THE SMART TEXT FIELD
            ZStack(alignment: .leading) {
                if taskText.isEmpty {
                    Text("Task (e.g., '!!! Gym tomorrow in Personal')")
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .foregroundColor(.gray.opacity(0.4))
                        .allowsHitTesting(false)
                }
                
                Text(styledText(from: taskText))
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .allowsHitTesting(false)
                    // Fluid animation for the text overlay changing
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: taskText)
                
                TextField("", text: $taskText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundColor(.clear)
                    .tint(.blue)
                    .focused($isInputFocused) // Auto-focus binding
                    .onSubmit { saveTask() }
            }
            .onChange(of: taskText) { _ in
                // Trigger the parsing engine with a bouncy physics animation
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.5)) {
                    parseText()
                }
            }
            
            // 2. THE FLUID POP-UP UI (Chips)
            if parsedDate != nil || parsedList != nil || parsedPriority > 0 {
                HStack(spacing: 12) {
                    
                    // Priority Chip (Red/Yellow/Blue)
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
                    
                    // Date Chip (Orange)
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
                    
                    // List Chip (Purple)
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
            }
        }
        .padding(20)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            requestPermissionsAndFetchLists()
            isInputFocused = true // Focus on first launch
        }
        // 🚨 NEW: Listen for the AppDelegate telling us the panel opened
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PanelDidOpen"))) { _ in
            isInputFocused = true
        }
    }
    
    // Helper for Priority Colors
    private func priorityColor() -> Color {
        if parsedPriority == 1 { return .red }
        if parsedPriority == 5 { return .yellow }
        return .blue
    }
    
    // --- ENGINE: SYNTAX HIGHLIGHTER ---
    private func styledText(from text: String) -> AttributedString {
        var attrString = AttributedString(text)
        attrString.foregroundColor = .primary
        
        // Fade Priority Marks
        if let pStr = parsedPriorityString, let range = attrString.range(of: pStr) {
            attrString[range].foregroundColor = priorityColor().opacity(0.6)
        }
        if let dateStr = parsedDateString, let range = attrString.range(of: dateStr) {
            attrString[range].foregroundColor = .orange.opacity(0.4)
        }
        if let listStr = parsedListString, let range = attrString.range(of: listStr, options: .caseInsensitive) {
            attrString[range].foregroundColor = .purple.opacity(0.4)
        }
        return attrString
    }
    
    // --- ENGINE: NATURAL LANGUAGE PARSER ---
    private func parseText() {
        parsedDate = nil; parsedDateString = nil
        parsedList = nil; parsedListString = nil
        parsedPriority = 0; parsedPriorityString = nil
        
        guard !taskText.isEmpty else { return }
        
        // 1. Scan for Priority (Must be at the very beginning)
        if taskText.hasPrefix("!!!") {
            parsedPriority = 1 // High
            parsedPriorityString = "!!!"
        } else if taskText.hasPrefix("!!") {
            parsedPriority = 5 // Medium
            parsedPriorityString = "!!"
        } else if taskText.hasPrefix("!") {
            parsedPriority = 9 // Low
            parsedPriorityString = "!"
        }
        
        // 2. Scan for List Names
        for list in lists {
            let pattern = "\\b\\Q\(list.title)\\E\\b"
            if let range = taskText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                parsedList = list
                parsedListString = String(taskText[range])
                break
            }
        }
        
        // 3. Scan for Dates & Times
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: taskText, options: [], range: NSRange(location: 0, length: taskText.utf16.count))
            if let match = matches.first, let date = match.date {
                if let range = Range(match.range, in: taskText) {
                    parsedDateString = String(taskText[range])
                    parsedDate = date
                }
            }
        }
    }
    
    // --- ENGINE: SAVE & CLEANUP ---
    private func saveTask() {
        guard !taskText.isEmpty else { return }
        var cleanTitle = taskText
        
        if let pStr = parsedPriorityString { cleanTitle = cleanTitle.replacingOccurrences(of: pStr, with: "") }
        if let dStr = parsedDateString { cleanTitle = cleanTitle.replacingOccurrences(of: dStr, with: "", options: .caseInsensitive) }
        if let lStr = parsedListString {
            cleanTitle = cleanTitle.replacingOccurrences(of: lStr, with: "", options: .caseInsensitive)
            cleanTitle = cleanTitle.replacingOccurrences(of: " in ", with: " ")
            cleanTitle = cleanTitle.replacingOccurrences(of: " to ", with: " ")
        }
        
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty { cleanTitle = "New Task" }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = cleanTitle
        reminder.calendar = parsedList ?? eventStore.defaultCalendarForNewReminders()
        reminder.priority = parsedPriority // Set the priority in EventKit!
        
        if let targetDate = parsedDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
            reminder.addAlarm(EKAlarm(absoluteDate: targetDate))
        }
        
        try? eventStore.save(reminder, commit: true)
        
        taskText = ""
        parseText()
        
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.hidePanel()
        }
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
