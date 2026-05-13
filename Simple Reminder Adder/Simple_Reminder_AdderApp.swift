import SwiftUI
import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.n, modifiers: [.option]))
}

@main
struct Simple_Reminder_AdderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { SettingsView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel!
    var chipsPanel: FloatingPanel?
    var toastPanel: FloatingPanel?

    var globalClickMonitor: Any?
    var localKeyMonitor: Any?

    private var toastDismissWorkItem: DispatchWorkItem?
    private var toastShowGeneration: UInt64 = 0

    /// Bumped on every `syncChipsPanel` so stale animation completions cannot order out a newer chips state.
    private var chipsSyncGeneration: UInt64 = 0

    // Current parsed state driving the chips panel
    private var chipsState: (priority: Int, date: Date?, listName: String?) = (0, nil, nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 64))
        panel.contentView = NSHostingView(rootView: QuickAddView())

        NSApp.setActivationPolicy(.accessory)

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ParsedStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let info = notification.userInfo else { return }
            let priority  = info["priority"]    as? Int    ?? 0
            let date      = info["date"]        as? Date
            let listName  = info["list"]        as? String
            self.chipsState = (priority, date, listName)
            self.syncChipsPanel()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TaskSaved"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.hidePanel()
            guard let info = notification.userInfo,
                  let title = info["title"] as? String,
                  let list  = info["list"]  as? String else { return }
            let rawDate = info["date"] as? String
            self?.showToast(title: title, list: list, date: rawDate?.isEmpty == false ? rawDate : nil)
        }

        showPanel()
    }

    // MARK: - Panel show/hide

    func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    func showPanel() {
        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        syncChipsPanel()

        NotificationCenter.default.post(name: NSNotification.Name("PanelDidOpen"), object: nil)

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hidePanel(); return nil }
            // Prefer keyCode so Cmd+, opens Settings on non-US keyboard layouts.
            if event.modifierFlags.contains(.command), event.keyCode == 43 {
                self?.hidePanel(); self?.openSettingsWindow(); return nil
            }
            // Tab: accept ghost autocomplete (and avoid NSTextField selecting all text).
            if event.keyCode == 48 {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                    return event
                }
                NotificationCenter.default.post(name: .quickAddTabAcceptSuggestion, object: nil)
                return nil
            }
            return event
        }
    }

    func hidePanel() {
        panel.orderOut(nil)
        chipsPanel?.orderOut(nil)
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor    { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        // Reset chips state for next open
        chipsState = (0, nil, nil)
    }

    // MARK: - Chips panel

    private func syncChipsPanel() {
        chipsSyncGeneration += 1
        let gen = chipsSyncGeneration

        let hasChips = chipsState.priority > 0 || chipsState.date != nil || chipsState.listName != nil

        guard hasChips else {
            if let cp = chipsPanel, cp.isVisible {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    cp.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    guard let self, gen == self.chipsSyncGeneration else { return }
                    cp.alphaValue = 1
                    cp.orderOut(nil)
                }
            }
            return
        }

        if chipsPanel == nil {
            // Borderless avoids titled-bar clipping that can cut off capsule bottoms with multiple chips.
            chipsPanel = FloatingPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel]
            )
            chipsPanel?.ignoresMouseEvents = true
            chipsPanel?.level = .floating
        }

        // Measure using a temp window so fittingSize is accurate
        let chipsView = ChipsView(
            priority: chipsState.priority,
            date:     chipsState.date,
            listName: chipsState.listName
        )
        let host = NSHostingView(rootView: chipsView)
        host.frame = NSRect(x: 0, y: 0, width: 1600, height: 400)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        // Extra insets: NSHostingView often underreports capsule + material height with several chips in a row.
        let safeSize = NSSize(width: ceil(size.width) + 10, height: ceil(size.height) + 16)

        let panelFrame = panel.frame
        let anchorX = panelFrame.midX
        let anchorY = panelFrame.midY
        let gapBelowMain: CGFloat = 6

        let x = anchorX - safeSize.width / 2
        let y = panelFrame.minY - safeSize.height - gapBelowMain

        let targetFrame = NSRect(origin: NSPoint(x: x, y: y), size: safeSize)

        chipsPanel?.contentView = host
        chipsPanel?.contentView?.clipsToBounds = false

        if let cp = chipsPanel, cp.isVisible, cp.alphaValue < 0.999 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                cp.alphaValue = 1
            }
        }

        if chipsPanel?.isVisible == false {
            // Start centered on the quick-add bar (text field), then drop to final position below.
            let startFrame = NSRect(
                x: anchorX - safeSize.width / 2,
                y: anchorY - safeSize.height / 2,
                width: safeSize.width,
                height: safeSize.height
            )
            chipsPanel?.setFrame(startFrame, display: false)
            chipsPanel?.alphaValue = 0
            chipsPanel?.orderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.36
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                ctx.allowsImplicitAnimation = true
                chipsPanel?.animator().setFrame(targetFrame, display: true)
                chipsPanel?.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                chipsPanel?.animator().setFrame(targetFrame, display: true)
            }
        }
    }

    // MARK: - Settings

    func openSettingsWindow() {
        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - Toast

    func showToast(title: String, list: String, date: String?) {
        toastShowGeneration += 1
        let showGen = toastShowGeneration

        let toastView = ToastView(title: title, list: list, dateStr: date)
        let host = NSHostingView(rootView: toastView)
        host.layout()
        let size = host.fittingSize

        if toastPanel == nil {
            toastPanel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height))
            toastPanel?.ignoresMouseEvents = true
            toastPanel?.level = .screenSaver
            toastPanel?.styleMask.insert(.nonactivatingPanel)
        }

        toastDismissWorkItem?.cancel()

        toastPanel?.contentView = host

        guard let screen = panel.screen ?? NSScreen.main else { return }
        let sf = screen.visibleFrame
        let x  = sf.midX - size.width / 2
        let y  = sf.minY + sf.height * 0.18          // resting position

        let startFrame   = NSRect(x: x, y: y - 16, width: size.width, height: size.height)
        let restingFrame = NSRect(x: x, y: y,       width: size.width, height: size.height)

        toastPanel?.setFrame(startFrame, display: false)
        toastPanel?.alphaValue = 0
        toastPanel?.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            ctx.allowsImplicitAnimation = true
            toastPanel?.animator().setFrame(restingFrame, display: true)
            toastPanel?.animator().alphaValue = 1
        }

        let dismiss = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard showGen == self.toastShowGeneration else { return }
            let exitFrame = NSRect(x: x, y: y - 16, width: size.width, height: size.height)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                self.toastPanel?.animator().setFrame(exitFrame, display: true)
                self.toastPanel?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, showGen == self.toastShowGeneration else { return }
                self.toastPanel?.orderOut(nil)
            })
        }
        toastDismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: dismiss)
    }
}
