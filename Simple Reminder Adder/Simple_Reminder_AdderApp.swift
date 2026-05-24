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
    private var chipsSyncGeneration: UInt64 = 0
    private var lastSavedReminderID: String? = nil

    private var listPickerIsOpen: Bool = false
    private let mainInputBarHeight: CGFloat = 58
    private let mainPanelCollapsedHeight: CGFloat = 58
    private let mainPanelListPickerExpandedHeight: CGFloat = 296

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
    private var mainPanelUsesSearchExpansion: Bool = false

    private var isClosingPanel = false
    private var panelMotionToken: UInt64 = 0

    // BUG FIX: keep a single NSHostingView for the chips panel and update its rootView.
    // Previously a new NSHostingView was created at 1600×400 then assigned as contentView
    // without resizing it first, so the panel's clip rect could eat chips when fittingSize
    // was close to the oversized measurement frame.
    private var chipsHostingView: NSHostingView<AnyView>?

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
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let info = note.userInfo else { return }
            self.chipsState = (
                info["priority"]    as? Int    ?? 0,
                info["date"]        as? Date,
                info["list"]        as? String,
                info["showDatePill"] as? Bool  ?? false,
                info["showTimePill"] as? Bool  ?? false,
                info["glowDate"]     as? Bool  ?? false,
                info["glowTime"]     as? Bool  ?? false
            )
            self.syncChipsPanel()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TaskSaved"),
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let info  = note.userInfo,
                  let title = info["title"] as? String,
                  let list  = info["list"]  as? String else { return }
            let keepOpen = (info["keepPanelOpen"] as? Bool) == true
            self.lastSavedReminderID = info["reminderID"] as? String   // ← new
            if !keepOpen { hidePanel() }
            let rawDate = info["date"] as? String
            showToast(title: title, list: list, date: rawDate?.isEmpty == false ? rawDate : nil)
        }

        NotificationCenter.default.addObserver(
            forName: .mainPanelListPickerLayout,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let open = (note.userInfo?["open"] as? Bool) == true
            self.listPickerIsOpen = open
            self.resizeMainPanelForListPicker(open: open)
        }

        NotificationCenter.default.addObserver(
            forName: .searchModePresence,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.searchModeIsOpen = (note.userInfo?["active"] as? Bool) == true
            self.syncChipsPanel()
        }

        NotificationCenter.default.addObserver(
            forName: .mainPanelSearchLayout,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let open = (note.userInfo?["open"] as? Bool) == true
            let h    = note.userInfo?["height"] as? CGFloat ?? 0
            self.resizeMainPanelForSearchLayout(open: open, auxiliaryHeight: h)
        }

        NotificationCenter.default.addObserver(
            forName: .chipsLayoutChanged,
            object: nil, queue: .main
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
        if let m = localKeyMonitor    { NSEvent.removeMonitor(m); localKeyMonitor    = nil }

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
        let main     = panel.contentView
        let duration = 0.15
        let maxBlur: CGFloat = 12
        let start    = CFAbsoluteTimeGetCurrent()

        func tick() {
            guard token == self.panelMotionToken else { return }
            let raw = min(1.0, (CFAbsoluteTimeGetCurrent() - start) / duration)
            let t   = easeOutCubic(CGFloat(raw))
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

    private func easeOutCubic(_ t: CGFloat) -> CGFloat { let u = 1 - t; return 1 - u*u*u }
    private func easeInCubic(_ t: CGFloat) -> CGFloat  { return t*t*t }

    private func installInputMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Esc
            if event.keyCode == 53 {
                if listPickerIsOpen {
                    NotificationCenter.default.post(name: .listPickerCancel, object: nil)
                    return nil
                }
                if searchModeIsOpen {
                    NotificationCenter.default.post(name: .forceExitSearchMode, object: nil)
                    return nil
                }
                hidePanel(); return nil
            }

            // ⌘F — search toggle
            if flags.contains(.command), event.keyCode == 3 {
                NotificationCenter.default.post(name: .searchHotkeyToggle, object: nil); return nil
            }

            // ⌘, — settings
            if flags.contains(.command), event.keyCode == 43 {
                hidePanel(); openSettingsWindow(); return nil
            }
            
            // ⌘Z — undo last saved task
            if flags.contains(.command), event.keyCode == 6 {
                guard let rid = self.lastSavedReminderID else { return event }
                NotificationCenter.default.post(
                    name: NSNotification.Name("UndoLastTask"),
                    object: nil,
                    userInfo: ["reminderID": rid]
                )
                self.lastSavedReminderID = nil
                return nil
            }

            // Return / Enter
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn {
                if listPickerIsOpen { NotificationCenter.default.post(name: .listPickerConfirm, object: nil); return nil }
                if searchModeIsOpen { return nil }
                if flags.contains(.shift) { NotificationCenter.default.post(name: .quickAddShiftReturnSave, object: nil); return nil }
                return event
            }

            // Arrow keys in list picker
            if listPickerIsOpen {
                if event.keyCode == 125 { NotificationCenter.default.post(name: .listPickerNavigate, object: nil, userInfo: ["delta":  1]); return nil }
                if event.keyCode == 126 { NotificationCenter.default.post(name: .listPickerNavigate, object: nil, userInfo: ["delta": -1]); return nil }
            }

            // Tab
            if event.keyCode == 48 {
                if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) { return event }
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
        if mainPanelUsesSearchExpansion { resizeMainPanelForSearchLayout(open: false, auxiliaryHeight: 0) }
        NotificationCenter.default.post(name: .forceExitSearchMode, object: nil)
        listPickerIsOpen  = false
        searchModeIsOpen  = false

        if !panel.isVisible { finalizePanelHide(); return }

        panelMotionToken += 1
        let closeTok = panelMotionToken
        isClosingPanel = true
        panel.contentView?.wantsLayer = true
        runPanelCloseMotion(token: closeTok)
    }

    private func runPanelCloseMotion(token: UInt64) {
        let main     = panel.contentView
        let duration = 0.15
        let maxBlur: CGFloat = 14
        let start    = CFAbsoluteTimeGetCurrent()

        func tick() {
            guard token == self.panelMotionToken else { PanelMotionBlur.setRadius(0, on: main); return }
            let raw = min(1.0, (CFAbsoluteTimeGetCurrent() - start) / duration)
            let t   = easeInCubic(CGFloat(raw))
            self.panel.alphaValue       = 1 - CGFloat(t)
            self.chipsPanel?.alphaValue = 1 - CGFloat(t)
            PanelMotionBlur.setRadius(maxBlur * t, on: main)
            if raw < 1 {
                DispatchQueue.main.async(execute: tick)
            } else {
                guard token == self.panelMotionToken else { PanelMotionBlur.setRadius(0, on: main); return }
                if self.isClosingPanel {
                    self.isClosingPanel = false
                    PanelMotionBlur.setRadius(0, on: main)
                    self.finalizePanelHide()
                } else {
                    self.panel.alphaValue       = 1
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
            f.origin.y   -= dh
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
        if let m = localKeyMonitor    { NSEvent.removeMonitor(m); localKeyMonitor    = nil }
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(f, display: true)
        } completionHandler: { [weak self] in
            self?.syncChipsPanel()
        }
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
        f.size.height  = targetH
        f.origin.y    -= dh
        panel.setFrame(f, display: true, animate: false)
        DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }
    }

    // MARK: - Chips panel

    private func syncChipsPanel() {
        if searchModeIsOpen {
            if let cp = chipsPanel, cp.isVisible {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.08
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
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
                    ctx.duration = 0.10
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
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

        // Build panel lazily
        if chipsPanel == nil {
            chipsPanel = FloatingPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                movableByBackground: false
            )
            chipsPanel?.ignoresMouseEvents = false
            chipsPanel?.level = .floating
            chipsPanel?.hasShadow = false
        }

        // Build the SwiftUI root (AnyView so we can store the hosting view typed)
        let chipsRoot = AnyView(
            ChipsView(
                priority:     chipsState.priority,
                date:         chipsState.date,
                showDatePill: chipsState.showDatePill,
                showTimePill: chipsState.showTimePill,
                highlightDate: chipsState.glowDate,
                highlightTime: chipsState.glowTime,
                listName:     chipsState.listName
            )
            .environmentObject(chipsOverlayState)
        )

        // BUG FIX: reuse the hosting view and update rootView so SwiftUI can animate
        // chip content changes in-place. Previously we created a 1600×400 view, measured
        // fittingSize, then set it as contentView without resizing — the panel clip could
        // swallow chips whose natural size was close to the over-allocated measurement frame.
        if chipsHostingView == nil {
            let hv = NSHostingView(rootView: chipsRoot)
            chipsHostingView = hv
            chipsPanel?.contentView = hv
        } else {
            chipsHostingView?.rootView = chipsRoot
        }

        // Measure intrinsic size with a correctly-sized temp host so layout is accurate.
        let probe = NSHostingView(rootView: chipsRoot)
        probe.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        probe.layoutSubtreeIfNeeded()
        let fit = probe.fittingSize
        // Small padding so capsule shadows aren't clipped.
        let safeSize = NSSize(width: ceil(fit.width) + 8, height: ceil(fit.height) + 14)

        // Position: centred below main panel
        let panelFrame  = panel.frame
        let gapBelow: CGFloat = 6
        let x = panelFrame.midX - safeSize.width  / 2
        let y = panelFrame.minY - safeSize.height - gapBelow
        let targetFrame = NSRect(origin: NSPoint(x: x, y: y), size: safeSize)

        if chipsPanel?.isVisible == false {
            // Animate in: start at the panel midY, drop to resting position below.
            let anchorY   = panelFrame.minY + mainInputBarHeight / 2
            let startFrame = NSRect(
                x: panelFrame.midX - safeSize.width / 2,
                y: anchorY - safeSize.height / 2,
                width: safeSize.width,
                height: safeSize.height
            )
            chipsPanel?.setFrame(startFrame, display: false)
            chipsPanel?.alphaValue = 0
            chipsPanel?.orderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                // Spring-like cubic: fast exit, gentle settle
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 1.0, 0.34, 1.0)
                ctx.allowsImplicitAnimation = true
                chipsPanel?.animator().setFrame(targetFrame, display: true)
                chipsPanel?.animator().alphaValue = 1
            }
        } else {
            // Already visible — animate frame update (content changed, position may shift).
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
                ctx.allowsImplicitAnimation = true
                chipsPanel?.animator().setFrame(targetFrame, display: true)
            }
        }

        // Resize the actual hosting view to match the panel.
        chipsHostingView?.frame = NSRect(origin: .zero, size: safeSize)
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
        let y  = sf.maxY - size.height - 80

        let startFrame   = NSRect(x: x, y: y + 18, width: size.width, height: size.height)
        let restingFrame = NSRect(x: x, y: y,       width: size.width, height: size.height)
        let exitFrame    = NSRect(x: x, y: y + 18,  width: size.width, height: size.height)

        toastPanel?.setFrame(startFrame, display: false)
        toastPanel?.alphaValue = 0
        toastPanel?.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            ctx.allowsImplicitAnimation = true
            toastPanel?.animator().setFrame(restingFrame, display: true)
            toastPanel?.animator().alphaValue = 1
        }

        let dismiss = DispatchWorkItem { [weak self] in
            guard let self, showGen == self.toastShowGeneration else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
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
