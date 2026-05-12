import SwiftUI
import KeyboardShortcuts

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
    var globalClickMonitor: Any?
    var localKeyMonitor: Any? // Added to listen for the Esc key
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // INCREASED HEIGHT: Changed height to 120 to make room for the List buttons
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 120))
        let hostingView = NSHostingView(rootView: QuickAddView())
        panel.contentView = hostingView
        
        NSApp.setActivationPolicy(.accessory)
        
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        
        showPanel()
    }
    
    func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }
    
    func showPanel() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // 1. Listen for outside clicks
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
        
        // 2. Listen for the 'Esc' key (KeyCode 53)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hidePanel()
                return nil // Stops the "beep" sound
            }
            return event
        }
    }
    
    func hidePanel() {
        panel.orderOut(nil)
        
        // Clean up memory
        if let global = globalClickMonitor { NSEvent.removeMonitor(global); globalClickMonitor = nil }
        if let local = localKeyMonitor { NSEvent.removeMonitor(local); localKeyMonitor = nil }
    }
}
