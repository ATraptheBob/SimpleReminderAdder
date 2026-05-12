import SwiftUI
import EventKit

struct QuickAddView: View {
    @State private var taskText: String = ""
    @State private var lists: [EKCalendar] = []
    @State private var selectedList: EKCalendar?
    
    let eventStore = EKEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // 1. The Main Input Field
            TextField("Task (e.g. 'Gym tomorrow at 5pm')", text: $taskText)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .light, design: .rounded))
                .onSubmit {
                    saveTaskWithIntelligence(rawText: taskText)
                    taskText = ""
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.hidePanel()
                    }
                }
            
            // 2. Quick-Select List Buttons
            if !lists.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(lists, id: \.calendarIdentifier) { list in
                            Text(list.title)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedList == list ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(selectedList == list ? .white : .primary.opacity(0.8))
                                .clipShape(Capsule())
                                // Hover effect for a premium feel
                                .onHover { isHovering in
                                    if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                                .onTapGesture {
                                    selectedList = list // Route tasks to this list
                                }
                        }
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
    
    // --- INTELLIGENCE LOGIC ---
    
    private func saveTaskWithIntelligence(rawText: String) {
        guard !rawText.isEmpty else { return }
        
        var finalTitle = rawText
        var parsedDate: Date? = nil
        
        // 1. Natural Language Processing (Find dates/times in the text)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: rawText, options: [], range: NSRange(location: 0, length: rawText.utf16.count))
            
            // If we found a date (like "tomorrow at 5pm")
            if let match = matches.first, let date = match.date {
                parsedDate = date
                
                // Chop the date text out of the title so it's clean
                if let range = Range(match.range, in: rawText) {
                    finalTitle.removeSubrange(range)
                    finalTitle = finalTitle.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // 2. Create the Reminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = finalTitle.isEmpty ? "New Task" : finalTitle // Fallback if they ONLY typed a date
        
        // Route to the clicked list, or the default list if none was clicked
        reminder.calendar = selectedList ?? eventStore.defaultCalendarForNewReminders()
        
        // 3. Attach the Alarm/Date if NLP found one
        if let targetDate = parsedDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
            reminder.addAlarm(EKAlarm(absoluteDate: targetDate))
            print("📅 NLP detected date: \(targetDate)")
        }
        
        // 4. Save
        do {
            try eventStore.save(reminder, commit: true)
            print("✅ SAVED: '\(reminder.title)'")
        } catch {
            print("❌ FAILED: \(error.localizedDescription)")
        }
    }
    
    // --- SETUP LOGIC ---
    
    private func requestPermissionsAndFetchLists() {
        Task {
            do {
                if #available(macOS 14.0, *) {
                    try await eventStore.requestFullAccessToReminders()
                } else {
                    try await eventStore.requestAccess(to: .reminder)
                }
                
                // Once permission is granted, fetch their lists!
                DispatchQueue.main.async {
                    self.lists = eventStore.calendars(for: .reminder)
                    self.selectedList = eventStore.defaultCalendarForNewReminders()
                }
            } catch {
                print("❌ Permission error: \(error.localizedDescription)")
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
