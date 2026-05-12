import SwiftUI
import KeyboardShortcuts

// Define the global shortcut (Default: Option + Space)
extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
}

@main
struct Simple_Reminder_AdderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel!
    var clickMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Initialize the floating panel
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 70))
        let hostingView = NSHostingView(rootView: QuickAddView())
        panel.contentView = hostingView
        
        // 2. Hide the dock icon (runs in background)
        NSApp.setActivationPolicy(.accessory)
        
        // 3. Listen for the global shortcut
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        
        // 4. FORCE the panel to show up when you hit Play in Xcode
        showPanel()
    }
    
    // Toggles the window on and off
    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    // Shows the window and starts listening for outside clicks
    func showPanel() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) // Brings focus to the text box
        
        // Create a monitor to listen for clicks outside our app
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }
    
    // Hides the window and stops listening for clicks
    func hidePanel() {
        panel.orderOut(nil)
        
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
