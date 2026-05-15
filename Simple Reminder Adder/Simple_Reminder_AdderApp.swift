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

    private var listPickerIsOpen: Bool = false
    private let mainInputBarHeight: CGFloat = 58
    private let mainPanelCollapsedHeight: CGFloat = 58
    private let mainPanelListPickerExpandedHeight: CGFloat = 296

    // Current parsed state driving the chips panel
    private var chipsState: (
        priority: Int,
        date: Date?,
        listName: String?,
        showDatePill: Bool,
        showTimePill: Bool,
        glowDate: Bool,
        glowTime: Bool
    ) = (0, nil, nil, false, false, false, false)

    private let chipsOverlayState = ChipsOverlayState()

    private var searchModeIsOpen: Bool = false
    /// Main panel grew downward for the in-window search menu; undo with `origin` on hide.
    private var mainPanelUsesSearchExpansion: Bool = false

    private var isClosingPanel = false
    private var panelMotionToken: UInt64 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 58))
        panel.contentView = NSHostingView(rootView: QuickAddView())
        panel.hasShadow = false

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
            let showDatePill = info["showDatePill"] as? Bool ?? false
            let showTimePill = info["showTimePill"] as? Bool ?? false
            let glowDate = info["glowDate"] as? Bool ?? false
            let glowTime = info["glowTime"] as? Bool ?? false
            self.chipsState = (priority, date, listName, showDatePill, showTimePill, glowDate, glowTime)
            self.syncChipsPanel()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TaskSaved"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let info = notification.userInfo,
                  let title = info["title"] as? String,
                  let list  = info["list"]  as? String else { return }
            let keepOpen = (info["keepPanelOpen"] as? Bool) == true
            if !keepOpen {
                hidePanel()
            }
            let rawDate = info["date"] as? String
            showToast(title: title, list: list, date: rawDate?.isEmpty == false ? rawDate : nil)
        }

        NotificationCenter.default.addObserver(
            forName: .mainPanelListPickerLayout,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let open = (note.userInfo?["open"] as? Bool) == true
            self.listPickerIsOpen = open
            self.resizeMainPanelForListPicker(open: open)
        }

        NotificationCenter.default.addObserver(
            forName: .searchModePresence,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.searchModeIsOpen = (note.userInfo?["active"] as? Bool) == true
            self.syncChipsPanel()
        }

        NotificationCenter.default.addObserver(
            forName: .mainPanelSearchLayout,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let open = (note.userInfo?["open"] as? Bool) == true
            let h = note.userInfo?["height"] as? CGFloat ?? 0
            self.resizeMainPanelForSearchLayout(open: open, auxiliaryHeight: h)
        }

        NotificationCenter.default.addObserver(
            forName: .chipsLayoutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncChipsPanel()
        }

        showPanel()
    }

    // MARK: - Panel show/hide

    func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    func showPanel() {
        panelMotionToken += 1
        let openTok = panelMotionToken
        isClosingPanel = false

        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }

        if #available(macOS 14.0, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }

        chipsPanel?.alphaValue = 1

        panel.center()
        panel.makeKeyAndOrderFront(nil)

        panel.alphaValue = 0
        PanelMotionBlur.setRadius(12, on: panel.contentView)

        DispatchQueue.main.async { [weak self] in
            guard let self, openTok == self.panelMotionToken else { return }
            self.runPanelOpenMotion(token: openTok)
        }
    }

    private func runPanelOpenMotion(token: UInt64) {
        let main = panel.contentView
        let duration = 0.34
        let maxBlur: CGFloat = 12
        let start = CFAbsoluteTimeGetCurrent()

        func tick() {
            guard token == self.panelMotionToken else { return }
            let raw = min(1.0, (CFAbsoluteTimeGetCurrent() - start) / duration)
            let t = easeOutCubic(CGFloat(raw))
            self.panel.alphaValue = CGFloat(t)
            PanelMotionBlur.setRadius(maxBlur * (1 - t), on: main)
            if raw < 1 {
                DispatchQueue.main.async(execute: tick)
            } else {
                guard token == self.panelMotionToken else { return }
                self.panel.alphaValue = 1
                PanelMotionBlur.setRadius(0, on: main)
                self.installInputMonitors()
                NotificationCenter.default.post(name: NSNotification.Name("PanelDidOpen"), object: nil)
                DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }
            }
        }
        tick()
    }

    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let u = 1 - t
        return 1 - u * u * u
    }

    private func easeInCubic(_ t: CGFloat) -> CGFloat {
        return t * t * t
    }

    private func installInputMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 53 {
                if listPickerIsOpen {
                    NotificationCenter.default.post(name: .listPickerCancel, object: nil)
                    return nil
                }
                if searchModeIsOpen {
                    NotificationCenter.default.post(name: .forceExitSearchMode, object: nil)
                    return nil
                }
                hidePanel()
                return nil
            }

            if flags.contains(.command), event.keyCode == 3 {
                NotificationCenter.default.post(name: .searchHotkeyToggle, object: nil)
                return nil
            }

            if flags.contains(.command), event.keyCode == 43 {
                hidePanel()
                openSettingsWindow()
                return nil
            }

            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn {
                if listPickerIsOpen {
                    NotificationCenter.default.post(name: .listPickerConfirm, object: nil)
                    return nil
                }
                if searchModeIsOpen {
                    return nil
                }
                if flags.contains(.shift) {
                    NotificationCenter.default.post(name: .quickAddShiftReturnSave, object: nil)
                    return nil
                }
                return event
            }

            if listPickerIsOpen {
                if event.keyCode == 125 {
                    NotificationCenter.default.post(name: .listPickerNavigate, object: nil, userInfo: ["delta": 1])
                    return nil
                }
                if event.keyCode == 126 {
                    NotificationCenter.default.post(name: .listPickerNavigate, object: nil, userInfo: ["delta": -1])
                    return nil
                }
            }

            if event.keyCode == 48 {
                if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                    return event
                }
                if listPickerIsOpen {
                    let delta = flags.contains(.shift) ? -1 : 1
                    NotificationCenter.default.post(name: .listPickerNavigate, object: nil, userInfo: ["delta": delta])
                    return nil
                }
                NotificationCenter.default.post(name: .quickAddTabAcceptSuggestion, object: nil)
                return nil
            }

            return event
        }
    }

    func hidePanel() {
        if mainPanelUsesSearchExpansion {
            resizeMainPanelForSearchLayout(open: false, auxiliaryHeight: 0)
        }
        NotificationCenter.default.post(name: .forceExitSearchMode, object: nil)
        listPickerIsOpen = false
        searchModeIsOpen = false

        if !panel.isVisible {
            finalizePanelHide()
            return
        }

        panelMotionToken += 1
        let closeTok = panelMotionToken
        isClosingPanel = true
        panel.contentView?.wantsLayer = true

        runPanelCloseMotion(token: closeTok)
    }

    private func runPanelCloseMotion(token: UInt64) {
        let main = panel.contentView
        let duration = 0.32
        let maxBlur: CGFloat = 14
        let start = CFAbsoluteTimeGetCurrent()

        func tick() {
            guard token == self.panelMotionToken else {
                PanelMotionBlur.setRadius(0, on: main)
                return
            }
            let raw = min(1.0, (CFAbsoluteTimeGetCurrent() - start) / duration)
            let t = easeInCubic(CGFloat(raw))
            self.panel.alphaValue = 1 - CGFloat(t)
            self.chipsPanel?.alphaValue = 1 - CGFloat(t)
            PanelMotionBlur.setRadius(maxBlur * t, on: main)
            if raw < 1 {
                DispatchQueue.main.async(execute: tick)
            } else {
                guard token == self.panelMotionToken else {
                    PanelMotionBlur.setRadius(0, on: main)
                    return
                }
                if self.isClosingPanel {
                    self.isClosingPanel = false
                    PanelMotionBlur.setRadius(0, on: main)
                    self.finalizePanelHide()
                } else {
                    self.panel.alphaValue = 1
                    self.chipsPanel?.alphaValue = 1
                    PanelMotionBlur.setRadius(0, on: main)
                }
            }
        }
        tick()
    }

    private func finalizePanelHide() {
        chipsOverlayState.priorityExpanded = false
        PanelMotionBlur.setRadius(0, on: panel.contentView)
        if mainPanelUsesSearchExpansion {
            var f = panel.frame
            let dh = mainPanelCollapsedHeight - f.size.height
            f.size.height = mainPanelCollapsedHeight
            f.origin.y -= dh
            panel.setFrame(f, display: true, animate: false)
            mainPanelUsesSearchExpansion = false
        } else {
            resizeMainPanelForListPicker(open: false)
        }
        panel.orderOut(nil)
        panel.alphaValue = 1
        chipsPanel?.orderOut(nil)
        chipsPanel?.alphaValue = 1
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        chipsState = (0, nil, nil, false, false, false, false)
    }

    private func resizeMainPanelForListPicker(open: Bool) {
        mainPanelUsesSearchExpansion = false
        let newH = open ? mainPanelListPickerExpandedHeight : mainPanelCollapsedHeight
        var f = panel.frame
        guard abs(f.size.height - newH) > 0.5 else {
            DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }
            return
        }
        f.size.height = newH
        panel.setFrame(f, display: true, animate: false)
        DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }
    }

    private func resizeMainPanelForSearchLayout(open: Bool, auxiliaryHeight: CGFloat) {
        guard !listPickerIsOpen else { return }
        var f = panel.frame
        let oldH = f.size.height
        let targetH: CGFloat
        if open {
            targetH = mainInputBarHeight + max(auxiliaryHeight, 72)
            mainPanelUsesSearchExpansion = true
        } else {
            targetH = listPickerIsOpen ? mainPanelListPickerExpandedHeight : mainPanelCollapsedHeight
            mainPanelUsesSearchExpansion = false
        }
        guard abs(targetH - oldH) > 0.5 else {
            DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }
            return
        }
        let dh = targetH - oldH
        f.size.height = targetH
        f.origin.y -= dh
        panel.setFrame(f, display: true, animate: false)
        DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }
    }

    // MARK: - Chips panel

    private func syncChipsPanel() {
        if searchModeIsOpen {
            if let cp = chipsPanel, cp.isVisible {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    cp.animator().alphaValue = 0
                } completionHandler: {
                    cp.alphaValue = 1
                    cp.orderOut(nil)
                }
            }
            return
        }

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
                styleMask: [.borderless, .nonactivatingPanel],
                movableByBackground: false
            )
            chipsPanel?.ignoresMouseEvents = false
            chipsPanel?.level = .floating
            chipsPanel?.hasShadow = false
        }

        // Measure using a temp window so fittingSize is accurate
        let chipsRoot = ChipsView(
            priority: chipsState.priority,
            date: chipsState.date,
            showDatePill: chipsState.showDatePill,
            showTimePill: chipsState.showTimePill,
            highlightDate: chipsState.glowDate,
            highlightTime: chipsState.glowTime,
            listName: chipsState.listName
        )
        .environmentObject(chipsOverlayState)

        let host = NSHostingView(rootView: chipsRoot)
        host.frame = NSRect(x: 0, y: 0, width: 1600, height: 400)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        // Extra insets: NSHostingView often underreports capsule + material height with several chips in a row.
        let safeSize = NSSize(width: ceil(size.width) + 10, height: ceil(size.height) + 16)

        let panelFrame = panel.frame
        let anchorX = panelFrame.midX
        let anchorY = panelFrame.minY + mainInputBarHeight / 2
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
