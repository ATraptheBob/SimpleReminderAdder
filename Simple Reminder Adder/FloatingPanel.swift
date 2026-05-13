import AppKit

class FloatingPanel: NSPanel {
    /// - Parameter styleMask: Pass a custom mask for borderless overlays (e.g. chips); default keeps the titled key panel for the quick-add field.
    init(contentRect: NSRect, styleMask customStyleMask: NSWindow.StyleMask? = nil) {
        let mask = customStyleMask ?? [.titled, .fullSizeContentView]
        super.init(
            contentRect: contentRect,
            styleMask: mask,
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}
