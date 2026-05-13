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
    private var chipsState: (priority: Int, date: Date?, listName: String?) = (0, nil, nil)

    private var searchResultsPanel: FloatingPanel?
    private var searchModeIsOpen: Bool = false
    private var searchHitRows: [SearchHitRowModel] = []
    private var searchSyncGeneration: UInt64 = 0

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
            self.chipsState = (priority, date, listName)
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
            if !self.searchModeIsOpen {
                self.searchHitRows = []
            }
            self.syncChipsPanel()
            self.syncSearchResultsPanel()
        }

        NotificationCenter.default.addObserver(
            forName: .searchResultsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let raw = note.userInfo?["hits"] as? [[String: Any]] {
                self.searchHitRows = raw.compactMap { dict in
                    guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
                    let sub = dict["subtitle"] as? String ?? ""
                    return SearchHitRowModel(id: id, title: title, subtitle: sub)
                }
            } else {
                self.searchHitRows = []
            }
            self.syncSearchResultsPanel()
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
        DispatchQueue.main.async { [weak self] in self?.syncChipsPanel() }

        NotificationCenter.default.post(name: NSNotification.Name("PanelDidOpen"), object: nil)

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
        NotificationCenter.default.post(name: .forceExitSearchMode, object: nil)
        listPickerIsOpen = false
        searchModeIsOpen = false
        searchHitRows = []
        searchResultsPanel?.orderOut(nil)
        resizeMainPanelForListPicker(open: false)
        panel.orderOut(nil)
        chipsPanel?.orderOut(nil)
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor    { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        // Reset chips state for next open
        chipsState = (0, nil, nil)
    }

    private func resizeMainPanelForListPicker(open: Bool) {
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
                styleMask: [.borderless, .nonactivatingPanel]
            )
            chipsPanel?.ignoresMouseEvents = true
            chipsPanel?.level = .floating
            chipsPanel?.hasShadow = false
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

    // MARK: - Search results strip

    private func syncSearchResultsPanel() {
        searchSyncGeneration += 1
        let gen = searchSyncGeneration

        guard searchModeIsOpen else {
            if let sp = searchResultsPanel, sp.isVisible {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    ctx.allowsImplicitAnimation = true
                    sp.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    guard let self, gen == self.searchSyncGeneration else { return }
                    sp.alphaValue = 1
                    sp.orderOut(nil)
                })
            }
            return
        }

        guard !searchHitRows.isEmpty else {
            if let sp = searchResultsPanel, sp.isVisible {
                sp.orderOut(nil)
            }
            return
        }

        if searchResultsPanel == nil {
            searchResultsPanel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel])
            searchResultsPanel?.level = .floating
            searchResultsPanel?.hasShadow = false
            searchResultsPanel?.backgroundColor = .clear
            searchResultsPanel?.isOpaque = false
        }

        let strip = SearchResultsStripView(hits: searchHitRows)
        let host = NSHostingView(rootView: strip)
        host.frame = NSRect(x: 0, y: 0, width: 2000, height: 400)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let safeSize = NSSize(width: ceil(size.width) + 12, height: ceil(size.height) + 14)

        let panelFrame = panel.frame
        let anchorX = panelFrame.midX
        let anchorY = panelFrame.minY + mainInputBarHeight / 2
        let gapBelowMain: CGFloat = 6

        let x = anchorX - safeSize.width / 2
        let y = panelFrame.minY - safeSize.height - gapBelowMain
        let targetFrame = NSRect(origin: NSPoint(x: x, y: y), size: safeSize)

        searchResultsPanel?.contentView = host
        searchResultsPanel?.contentView?.clipsToBounds = false

        if let sp = searchResultsPanel, sp.isVisible, sp.alphaValue < 0.999 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                sp.alphaValue = 1
            }
        }

        if searchResultsPanel?.isVisible == false {
            let startFrame = NSRect(
                x: anchorX - safeSize.width / 2,
                y: anchorY - safeSize.height / 2,
                width: safeSize.width,
                height: safeSize.height
            )
            searchResultsPanel?.setFrame(startFrame, display: false)
            searchResultsPanel?.alphaValue = 0
            searchResultsPanel?.orderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                ctx.allowsImplicitAnimation = true
                searchResultsPanel?.animator().setFrame(targetFrame, display: true)
                searchResultsPanel?.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                searchResultsPanel?.animator().setFrame(targetFrame, display: true)
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
