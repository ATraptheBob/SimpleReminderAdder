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
    var localKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        
        // 🚨 NEW: Tell the SwiftUI view to instantly grab the text cursor
        NotificationCenter.default.post(name: NSNotification.Name("PanelDidOpen"), object: nil)
        
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
        
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hidePanel()
                return nil
            }
            return event
        }
    }
    
    func hidePanel() {
        panel.orderOut(nil)
        if let global = globalClickMonitor { NSEvent.removeMonitor(global); globalClickMonitor = nil }
        if let local = localKeyMonitor { NSEvent.removeMonitor(local); localKeyMonitor = nil }
    }
}
