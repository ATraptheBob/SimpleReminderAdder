import SwiftUI
import EventKit

struct QuickAddView: View {
    @State private var taskText: String = ""
    @State private var lists: [EKCalendar] = []
    
    // Intelligence State
    @State private var parsedDate: Date? = nil
    @State private var parsedDateString: String? = nil
    @State private var parsedList: EKCalendar? = nil
    @State private var parsedListString: String? = nil
    
    let eventStore = EKEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // 1. THE SMART TEXT FIELD
            ZStack(alignment: .leading) {
                
                // A. Placeholder
                if taskText.isEmpty {
                    Text("Task (e.g., 'Gym tomorrow in Personal')")
                        .font(.system(size: 24, weight: .light, design: .rounded))
                        .foregroundColor(.gray.opacity(0.4))
                        .allowsHitTesting(false)
                }
                
                // B. The Syntax-Highlighted Text (Sits behind the real text field)
                Text(styledText(from: taskText))
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .allowsHitTesting(false) // Lets you click "through" it
                
                // C. The Actual Input (Text is invisible, but cursor works!)
                TextField("", text: $taskText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundColor(.clear) // Hides the boring text
                    .tint(.blue) // Keeps the blinking cursor visible
                    .onSubmit {
                        saveTask()
                    }
            }
            // Trigger the parsing engine on every keystroke
            .onChange(of: taskText) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    parseText()
                }
            }
            
            // 2. THE FLUID POP-UP UI
            // This only appears if the engine finds a Date or a List
            if parsedDate != nil || parsedList != nil {
                HStack(spacing: 12) {
                    
                    // Date Chip (Orange)
                    if let dateStr = parsedDateString, let date = parsedDate {
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
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale))
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
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale))
                    }
                }
            }
        }
        .padding(20)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            requestPermissionsAndFetchLists()
        }
    }
    
    // --- ENGINE: SYNTAX HIGHLIGHTER ---
    private func styledText(from text: String) -> AttributedString {
        var attrString = AttributedString(text)
        attrString.foregroundColor = .primary // Default text color
        
        // Find and fade/color the Date
        if let dateStr = parsedDateString, let range = attrString.range(of: dateStr) {
            attrString[range].foregroundColor = .orange.opacity(0.4) // Faded Orange
        }
        
        // Find and fade/color the List name
        if let listStr = parsedListString, let range = attrString.range(of: listStr, options: .caseInsensitive) {
            attrString[range].foregroundColor = .purple.opacity(0.4) // Faded Purple
        }
        
        return attrString
    }
    
    // --- ENGINE: NATURAL LANGUAGE PARSER ---
    private func parseText() {
        // Reset state
        parsedDate = nil
        parsedDateString = nil
        parsedList = nil
        parsedListString = nil
        
        guard !taskText.isEmpty else { return }
        
        // 1. Scan for List Names
        for list in lists {
            // Looks for the exact list name as a standalone word
            let pattern = "\\b\\Q\(list.title)\\E\\b"
            if let range = taskText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                parsedList = list
                parsedListString = String(taskText[range])
                break // Found it!
            }
        }
        
        // 2. Scan for Dates & Times
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
        
        // Strip out the recognized text so your final task is clean
        if let dStr = parsedDateString {
            cleanTitle = cleanTitle.replacingOccurrences(of: dStr, with: "", options: .caseInsensitive)
        }
        if let lStr = parsedListString {
            cleanTitle = cleanTitle.replacingOccurrences(of: lStr, with: "", options: .caseInsensitive)
            // Optional: clean up dangling words like "in" or "to"
            cleanTitle = cleanTitle.replacingOccurrences(of: " in ", with: " ")
            cleanTitle = cleanTitle.replacingOccurrences(of: " to ", with: " ")
        }
        
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty { cleanTitle = "New Task" }
        
        // Build the reminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = cleanTitle
        reminder.calendar = parsedList ?? eventStore.defaultCalendarForNewReminders()
        
        if let targetDate = parsedDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
            reminder.addAlarm(EKAlarm(absoluteDate: targetDate))
        }
        
        try? eventStore.save(reminder, commit: true)
        
        // Reset and dismiss
        taskText = ""
        parseText() // Clears the popups
        
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.hidePanel()
        }
    }
    
    // --- SETUP ---
    private func requestPermissionsAndFetchLists() {
        Task {
            do {
                if #available(macOS 14.0, *) {
                    try await eventStore.requestFullAccessToReminders()
                } else {
                    try await eventStore.requestAccess(to: .reminder)
                }
                DispatchQueue.main.async {
                    self.lists = eventStore.calendars(for: .reminder)
                }
            } catch {
                print("Permission error")
            }
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
