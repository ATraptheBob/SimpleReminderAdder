import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // 🚨 SHORTCUT FIX: Changed from .space to .n (Option + N) to avoid fighting with Raycast
    static let togglePanel = Self("togglePanel", default: .init(.n, modifiers: [.option]))
}

@main
struct Simple_Reminder_AdderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel!
    var toastPanel: FloatingPanel?
    var globalClickMonitor: Any?
    var localKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 120))
        panel.contentView = NSHostingView(rootView: QuickAddView())
        
        NSApp.setActivationPolicy(.accessory)
        
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("TaskSaved"), object: nil, queue: .main) { [weak self] notification in
            self?.hidePanel()
            
            if let userInfo = notification.userInfo,
               let title = userInfo["title"] as? String,
               let list = userInfo["list"] as? String {
                
                let rawDate = userInfo["date"] as? String
                let date = (rawDate == nil || rawDate == "") ? nil : rawDate
                self?.showToast(title: title, list: list, date: date)
            }
        }
        showPanel()
    }
    
    func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }
    
    func showPanel() {
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        
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
    
    func showToast(title: String, list: String, date: String?) {
        let toastView = ToastView(title: title, list: list, dateStr: date)
        let hostingView = NSHostingView(rootView: toastView)
        hostingView.layout()
        
        let dynamicWidth = hostingView.fittingSize.width
        let dynamicHeight = hostingView.fittingSize.height
        
        if toastPanel == nil {
            toastPanel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: dynamicWidth, height: dynamicHeight))
            toastPanel?.ignoresMouseEvents = true
            toastPanel?.level = .screenSaver
        }
        
        toastPanel?.contentView = hostingView
        
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - (dynamicWidth / 2)
        
        // 🚨 POSITION FIX: Multiplies screen height by 0.20 to set it at exactly 20%
        let y = screenRect.minY + (screenRect.height * 0.20)
        
        toastPanel?.setFrame(NSRect(x: x, y: y, width: dynamicWidth, height: dynamicHeight), display: true)
        
        toastPanel?.alphaValue = 0
        toastPanel?.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toastPanel?.animator().alphaValue = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.toastPanel?.animator().alphaValue = 0.0
            }, completionHandler: {
                self.toastPanel?.orderOut(nil)
            })
        }
    }
}
