import AppKit

class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Define HUD behaviors
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        
        // Remove default backgrounds
        self.backgroundColor = .clear
        self.isOpaque = false
    }
    
    // Required to allow a borderless panel to accept keyboard input
    override var canBecomeKey: Bool {
        return true
    }
}
