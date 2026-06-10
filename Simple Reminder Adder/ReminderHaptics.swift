import AppKit

enum ReminderHaptics {
    /// Two-step haptic: alignment “snap” then a lighter level tick (pill seating into place).
    static func successSnap() {
        let p = NSHapticFeedbackManager.defaultPerformer
        p.perform(.alignment, performanceTime: .default)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055) {
            p.perform(.levelChange, performanceTime: .default)
        }
    }
}
