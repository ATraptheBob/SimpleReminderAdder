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
    var panel: FloatingPanel?
    var chipsPanel: FloatingPanel?
    var toastPanel: FloatingPanel?
    
    var globalClickMonitor: Any?
    var localKeyMonitor: Any?

    private var toastDismissWorkItem: DispatchWorkItem?
    private var toastShowGeneration: UInt64 = 0
    private var chipsSyncGeneration: UInt64 = 0
    private var lastSavedReminderID: String? = nil

    private var listPickerIsOpen: Bool = false
    private let mainPanelCollapsedHeight: CGFloat = 58
    private let mainPanelListPickerExpandedHeight: CGFloat = 260
    
    // Panel expansion constants and state
    private let maxPanelWidth: CGFloat = 580
    private let idleWidth: CGFloat = 140
    private let idleHeight: CGFloat = 0
    private let minExpandedWidth: CGFloat = 260
    private let tabHeight: CGFloat = 32
    private var isIdleMode: Bool = true
    private var isTabVisible: Bool = true
    private var currentTextWidth: CGFloat = 0

    private var chipsState: (
        priority: Int,
        date: Date?,
        listName: String?,
        showDatePill: Bool,
        showTimePill: Bool,
        glowDate: Bool,
        glowTime: Bool,
        recurrenceText: String?,
        locationTitle: String?
    ) = (0, nil, nil, false, false, false, false, nil, nil)

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

    // PERF: cached probe view for measuring chips intrinsic size (avoids alloc per sync).
    private var chipsProbeView: NSHostingView<AnyView>?

    // PERF: reuse toast hosting view instead of creating one per toast.
    private var toastHostingView: NSHostingView<AnyView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupKeyboardShortcuts()
        setupObservers()
        showPanel()
    }

    private func setupPanel() {
        // FIX: Use .borderless to cleanly eliminate the invisible title bar that
        // causes safe area insets (text clipping). Unlike .fullSizeContentView alone,
        // .borderless is a valid mask and prevents constraint loop crashes during resize.
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: idleWidth, height: idleHeight + tabHeight),
            styleMask: [.borderless]
        )
        panel?.contentView = NSHostingView(rootView: QuickAddView())
        panel?.hasShadow = false

        NSApp.setActivationPolicy(.accessory)
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
    }

    private func setupObservers() {
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
                info["glowTime"]     as? Bool  ?? false,
                info["recurrenceText"] as? String,
                info["locationTitle"]  as? String
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

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HidePanelRequest"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }

        NotificationCenter.default.addObserver(
            forName: .textContentSizeChanged,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let textWidth = note.userInfo?["textWidth"] as? CGFloat ?? 0
            self.currentTextWidth = textWidth
            self.resizePanelForText(textWidth: textWidth, oldIdleMode: self.isIdleMode, oldTabVisible: self.isTabVisible)
        }

        NotificationCenter.default.addObserver(
            forName: .idleModeChanged,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let isIdle = note.userInfo?["isIdle"] as? Bool ?? true
            let oldIdleMode = self.isIdleMode
            self.isIdleMode = isIdle
            self.resizePanelForText(textWidth: self.currentTextWidth, oldIdleMode: oldIdleMode, oldTabVisible: self.isTabVisible)
        }

        NotificationCenter.default.addObserver(
            forName: .waveformTabVisibilityChanged,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let visible = note.userInfo?["visible"] as? Bool ?? false
            let oldTabVisible = self.isTabVisible
            self.isTabVisible = visible
            self.resizePanelForText(textWidth: self.currentTextWidth, oldIdleMode: self.isIdleMode, oldTabVisible: oldTabVisible)
        }
    }

    // MARK: - Panel show/hide

    func togglePanel() {
        panel?.isVisible == true ? hidePanel() : showPanel()
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
        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            let newTabH: CGFloat = self.isTabVisible ? tabHeight : 0
            let newInputBarH: CGFloat = self.isIdleMode ? idleHeight : mainPanelCollapsedHeight
            let centerY_in_window = newTabH + newInputBarH / 2.0
            
            let x = sf.midX - (panel?.frame.width ?? 0) / 2
            let y = sf.midY - centerY_in_window
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel?.center()
        }
        panel?.makeKeyAndOrderFront(nil)
        panel?.alphaValue = 0
        PanelMotionBlur.setRadius(12, on: panel?.contentView)

        DispatchQueue.main.async { [weak self] in
            guard let self, openTok == self.panelMotionToken else { return }
            self.runPanelOpenMotion(token: openTok)
        }
    }

    private func runPanelOpenMotion(token: UInt64) {
        let main     = panel?.contentView
        let duration = 0.22
        let maxBlur: CGFloat = 14
        let start    = CFAbsoluteTimeGetCurrent()

        // Start slightly scaled down for a subtle zoom-in effect
        main?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        if let frame = main?.frame {
            main?.layer?.position = CGPoint(x: frame.midX, y: frame.midY)
        }
        main?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.97, y: 0.97))

        func tick() {
            guard token == self.panelMotionToken else { return }
            let raw = min(1.0, (CFAbsoluteTimeGetCurrent() - start) / duration)
            // Smooth ease-out quartic curve for premium feel
            let u = 1 - CGFloat(raw)
            let t = 1 - u * u * u * u
            self.panel?.alphaValue = CGFloat(t)
            PanelMotionBlur.setRadius(maxBlur * (1 - t), on: main)
            // Scale from 0.97 → 1.0
            let scale = 0.97 + 0.03 * t
            main?.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            if raw < 1 {
                DispatchQueue.main.async(execute: tick)
            } else {
                guard token == self.panelMotionToken else { return }
                self.panel?.alphaValue = 1
                PanelMotionBlur.setRadius(0, on: main)
                main?.layer?.setAffineTransform(.identity)
                self.installInputMonitors()
                NotificationCenter.default.post(name: NSNotification.Name("PanelDidOpen"), object: nil)
                DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }
                // Auto-activate voice dictation when panel opens
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .toggleDictation, object: nil)
                }
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
                NotificationCenter.default.post(name: NSNotification.Name("EscapePressed"), object: nil)
                return nil
            }

            // ⌘F — search toggle
            if flags.contains(.command), event.keyCode == 3 {
                NotificationCenter.default.post(name: .searchHotkeyToggle, object: nil); return nil
            }

            // ⌘, — settings
            if flags.contains(.command), event.keyCode == 43 {
                openSettingsWindow()
                return nil
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

            // ⌘+<dictation hotkey> — toggle voice dictation (configurable)
            let dictKey = UserDefaults.standard.string(forKey: "dictationHotkey") ?? "d"
            if flags.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               chars == dictKey {
                NotificationCenter.default.post(name: .toggleDictation, object: nil)
                return nil
            }

            // Return / Enter
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            if isReturn {
                if listPickerIsOpen { NotificationCenter.default.post(name: .listPickerConfirm, object: nil); return nil }
                if searchModeIsOpen {
                    if flags.contains(.option) || flags.contains(.control) {
                        NotificationCenter.default.post(name: .searchCompleteSelected, object: nil)
                        return nil
                    }
                    NotificationCenter.default.post(name: .searchConfirm, object: nil)
                    return nil
                }
                if flags.contains(.shift) { NotificationCenter.default.post(name: .quickAddShiftReturnSave, object: nil); return nil }
                return event
            }

            // Shift + Space in search mode — mark selected as complete
            if searchModeIsOpen, event.keyCode == 49, flags.contains(.shift) {
                NotificationCenter.default.post(name: .searchCompleteSelected, object: nil)
                return nil
            }

            // Shift + Delete / ⌘⌫ in search mode — delete selected reminder
            if searchModeIsOpen, event.keyCode == 51, flags.contains(.shift) {
                NotificationCenter.default.post(name: .searchDeleteSelected, object: nil)
                return nil
            }

            // Arrow keys in list picker or search mode
            if listPickerIsOpen {
                if event.keyCode == 125 { NotificationCenter.default.post(name: .listPickerNavigate, object: nil, userInfo: ["delta":  1]); return nil }
                if event.keyCode == 126 { NotificationCenter.default.post(name: .listPickerNavigate, object: nil, userInfo: ["delta": -1]); return nil }
            }
            if searchModeIsOpen {
                if event.keyCode == 125 { NotificationCenter.default.post(name: .searchNavigate, object: nil, userInfo: ["delta":  1]); return nil }
                if event.keyCode == 126 { NotificationCenter.default.post(name: .searchNavigate, object: nil, userInfo: ["delta": -1]); return nil }
            }

            // Up arrow recall (when not in list picker or search) — recall last reminder
            if event.keyCode == 126, !listPickerIsOpen, !searchModeIsOpen {
                NotificationCenter.default.post(name: .upArrowRecall, object: nil)
                return nil
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

    func applicationDidResignActive(_ notification: Notification) {
        hidePanel()
    }

    func hidePanel() {
        if mainPanelUsesSearchExpansion { resizeMainPanelForSearchLayout(open: false, auxiliaryHeight: 0) }
        NotificationCenter.default.post(name: .forceExitSearchMode, object: nil)
        listPickerIsOpen  = false
        searchModeIsOpen  = false
        NotificationCenter.default.post(name: NSNotification.Name("PanelDidClose"), object: nil)

        if panel?.isVisible != true { finalizePanelHide(); return }

        panelMotionToken += 1
        let closeTok = panelMotionToken
        isClosingPanel = true
        panel?.contentView?.wantsLayer = true
        runPanelCloseMotion(token: closeTok)
    }

    private func runPanelCloseMotion(token: UInt64) {
        let main     = panel?.contentView
        let duration = 0.18
        let maxBlur: CGFloat = 16
        let start    = CFAbsoluteTimeGetCurrent()

        // Prepare layer for scale transform
        main?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        if let frame = main?.frame {
            main?.layer?.position = CGPoint(x: frame.midX, y: frame.midY)
        }

        func tick() {
            guard token == self.panelMotionToken else { PanelMotionBlur.setRadius(0, on: main); main?.layer?.setAffineTransform(.identity); return }
            let raw = min(1.0, (CFAbsoluteTimeGetCurrent() - start) / duration)
            // Ease-in quartic for snappy feel on close
            let t   = CGFloat(raw * raw * raw)
            self.panel?.alphaValue       = 1 - CGFloat(t)
            self.chipsPanel?.alphaValue = 1 - CGFloat(t)
            PanelMotionBlur.setRadius(maxBlur * t, on: main)
            // Scale from 1.0 → 0.96
            let scale = 1.0 - 0.04 * t
            main?.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            if raw < 1 {
                DispatchQueue.main.async(execute: tick)
            } else {
                guard token == self.panelMotionToken else { PanelMotionBlur.setRadius(0, on: main); main?.layer?.setAffineTransform(.identity); return }
                if self.isClosingPanel {
                    self.isClosingPanel = false
                    PanelMotionBlur.setRadius(0, on: main)
                    main?.layer?.setAffineTransform(.identity)
                    self.finalizePanelHide()
                } else {
                    self.panel?.alphaValue       = 1
                    self.chipsPanel?.alphaValue = 1
                    PanelMotionBlur.setRadius(0, on: main)
                    main?.layer?.setAffineTransform(.identity)
                }
            }
        }
        tick()
    }

    private func finalizePanelHide() {
        chipsOverlayState.priorityExpanded = false
        PanelMotionBlur.setRadius(0, on: panel?.contentView)
        if mainPanelUsesSearchExpansion {
            mainPanelUsesSearchExpansion = false
        }
        
        // Let QuickAddView maintain the idle mode state.
        // We do not force reset it here so that if the user re-opens with a draft, it doesn't clip.
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        chipsPanel?.orderOut(nil)
        chipsPanel?.alphaValue = 1
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor    { NSEvent.removeMonitor(m); localKeyMonitor    = nil }
        chipsState = (0, nil, nil, false, false, false, false, nil, nil)
    }

    private func updatePanelFrame(targetW: CGFloat, targetH: CGFloat, oldIdleMode: Bool, oldTabVisible: Bool) {
        guard var f = panel?.frame else { return }
        guard abs(f.size.height - targetH) > 0.5 || abs(f.size.width - targetW) > 0.5 else {
            DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }
            return
        }
        
        let oldTabH: CGFloat = oldTabVisible ? tabHeight : 0
        let oldInputBarH: CGFloat = oldIdleMode ? idleHeight : mainPanelCollapsedHeight
        let oldCenterY_in_window = oldTabH + oldInputBarH / 2.0
        let screen_center_y = f.origin.y + oldCenterY_in_window
        
        let newTabH: CGFloat = self.isTabVisible ? tabHeight : 0
        let newInputBarH: CGFloat = self.isIdleMode ? idleHeight : mainPanelCollapsedHeight
        let newCenterY_in_window = newTabH + newInputBarH / 2.0
        
        let dw = targetW - f.size.width
        
        f.size.width = targetW
        f.size.height = targetH
        f.origin.x -= dw / 2
        f.origin.y = screen_center_y - newCenterY_in_window
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            ctx.allowsImplicitAnimation = true
            panel?.animator().setFrame(f, display: true)
        } completionHandler: { [weak self] in
            self?.syncChipsPanel()
        }
    }

    private func resizeMainPanelForListPicker(open: Bool) {
        let oldIdleMode = self.isIdleMode
        let oldTabVisible = self.isTabVisible
        mainPanelUsesSearchExpansion = false
        
        let initialW = open ? maxPanelWidth : (isIdleMode ? idleWidth : min(maxPanelWidth, max(minExpandedWidth, currentTextWidth + 80)))
        
        var newIdleMode = oldIdleMode
        if open && newIdleMode {
            newIdleMode = false
        } else if !open && initialW == idleWidth && !newIdleMode {
            newIdleMode = true
        }
        self.isIdleMode = newIdleMode
        
        let baseH = open ? mainPanelListPickerExpandedHeight : (newIdleMode ? idleHeight : mainPanelCollapsedHeight)
        let newH = baseH + (isTabVisible ? tabHeight : 0)
        let newW = open ? maxPanelWidth : (newIdleMode ? idleWidth : min(maxPanelWidth, max(minExpandedWidth, currentTextWidth + 80)))
        
        updatePanelFrame(targetW: newW, targetH: newH, oldIdleMode: oldIdleMode, oldTabVisible: oldTabVisible)
    }

    private func resizeMainPanelForSearchLayout(open: Bool, auxiliaryHeight: CGFloat) {
        guard !listPickerIsOpen else { return }
        let oldIdleMode = self.isIdleMode
        let oldTabVisible = self.isTabVisible
        let baseH: CGFloat
        if open {
            mainPanelUsesSearchExpansion = true
            baseH = mainPanelCollapsedHeight + auxiliaryHeight
        } else {
            mainPanelUsesSearchExpansion = false
            baseH = isIdleMode ? idleHeight : mainPanelCollapsedHeight
        }
        let targetW = open ? maxPanelWidth : (isIdleMode ? idleWidth : min(maxPanelWidth, max(minExpandedWidth, currentTextWidth + 80)))
        let targetH = baseH + (isTabVisible ? tabHeight : 0)
        
        updatePanelFrame(targetW: targetW, targetH: targetH, oldIdleMode: oldIdleMode, oldTabVisible: oldTabVisible)
    }
    
    private func resizePanelForText(textWidth: CGFloat, oldIdleMode: Bool, oldTabVisible: Bool) {
        guard !searchModeIsOpen && !listPickerIsOpen else { return }
        
        let targetWidth = isIdleMode ? idleWidth : min(maxPanelWidth, max(minExpandedWidth, textWidth + 80))
        let baseHeight = isIdleMode ? idleHeight : mainPanelCollapsedHeight
        let targetHeight = baseHeight + (isTabVisible ? tabHeight : 0)
        
        updatePanelFrame(targetW: targetWidth, targetH: targetHeight, oldIdleMode: oldIdleMode, oldTabVisible: oldTabVisible)
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

        let hasChips = chipsState.priority > 0 || chipsState.date != nil || chipsState.listName != nil || chipsState.recurrenceText != nil || chipsState.locationTitle != nil

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
                listName:     chipsState.listName,
                recurrenceText: chipsState.recurrenceText,
                locationTitle: chipsState.locationTitle
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

        // PERF: reuse cached probe view for measurement instead of allocating a new one.
        if chipsProbeView == nil {
            chipsProbeView = NSHostingView(rootView: chipsRoot)
            chipsProbeView?.frame = NSRect(x: 0, y: 0, width: 900, height: 200)
        } else {
            chipsProbeView?.rootView = chipsRoot
        }
        chipsProbeView?.layoutSubtreeIfNeeded()
        let fit = chipsProbeView?.fittingSize ?? NSSize(width: 100, height: 30)
        // Small padding so capsule shadows aren't clipped.
        let safeSize = NSSize(width: ceil(fit.width) + 8, height: ceil(fit.height) + 14)

        // Position: centred below main panel
        guard let panelFrame = panel?.frame else { return }
        let gapBelow: CGFloat = 6
        let x = panelFrame.midX - safeSize.width  / 2
        let y = panelFrame.minY - safeSize.height - gapBelow
        let targetFrame = NSRect(origin: NSPoint(x: x, y: y), size: safeSize)

        if chipsPanel?.isVisible == false {
            // Animate in: start at the panel midY, drop to resting position below.
            let anchorY   = panelFrame.minY + mainPanelCollapsedHeight / 2
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
        NotificationCenter.default.post(name: NSNotification.Name("OpenSettingsRequest"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.hidePanel()
        }
    }

    // MARK: - Toast

    func showToast(title: String, list: String, date: String?) {
        toastShowGeneration += 1
        let showGen = toastShowGeneration

        let toastRoot = AnyView(ToastView(title: title, list: list, dateStr: date))

        // PERF: reuse the hosting view and update its rootView instead of creating a new one.
        if toastHostingView == nil {
            let hv = NSHostingView(rootView: toastRoot)
            toastHostingView = hv
        } else {
            toastHostingView?.rootView = toastRoot
        }
        toastHostingView?.layout()
        let size = toastHostingView?.fittingSize ?? NSSize(width: 300, height: 44)

        if toastPanel == nil {
            toastPanel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height))
            toastPanel?.ignoresMouseEvents = true
            toastPanel?.level = .screenSaver
            toastPanel?.styleMask.insert(.nonactivatingPanel)
        }

        toastDismissWorkItem?.cancel()
        toastPanel?.contentView = toastHostingView

        guard let screen = panel?.screen ?? NSScreen.main else { return }
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
