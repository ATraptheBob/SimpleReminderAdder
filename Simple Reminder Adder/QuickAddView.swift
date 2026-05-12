import SwiftUI
import EventKit

struct QuickAddView: View {
    @State private var taskText: String = ""
    let eventStore = EKEventStore()

    var body: some View {
        TextField("Add to Reminders...", text: $taskText)
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .light, design: .rounded))
            .onSubmit {
                saveToReminders(text: taskText)
                taskText = ""
                
                // Tell the AppDelegate to hide the panel
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.hidePanel()
                }
            }
            .padding(20)
            .background(VisualEffectView())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onAppear {
                requestPermissions()
            }
    }
    
    private func requestPermissions() {
        Task {
            do {
                if #available(macOS 14.0, *) {
                    try await eventStore.requestFullAccessToReminders()
                } else {
                    try await eventStore.requestAccess(to: .reminder)
                }
            } catch {
                print("❌ Permission error: \(error.localizedDescription)")
            }
        }
    }

    private func saveToReminders(text: String) {
        guard !text.isEmpty else { return }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = text
        
        // Safely check if we can find a reminders list
        if let defaultList = eventStore.defaultCalendarForNewReminders() {
            reminder.calendar = defaultList
            do {
                try eventStore.save(reminder, commit: true)
                print("✅ SUCCESSFULLY SAVED: '\(text)' to Reminders!")
            } catch {
                print("❌ FAILED TO SAVE: \(error.localizedDescription)")
            }
        } else {
            print("❌ PERMISSION ERROR: Could not find the default Reminders list. Did you add the Info.plist key?")
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
