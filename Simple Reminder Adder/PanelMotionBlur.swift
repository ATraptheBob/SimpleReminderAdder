import AppKit
import CoreImage
import QuartzCore

enum PanelMotionBlur {
    /// Horizontal motion blur (angle 0) for panel emerge / dismiss.
    static func setRadius(_ radius: CGFloat, on view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        if radius < 0.25 {
            layer.filters = nil
            return
        }
        guard let blur = CIFilter(name: "CIMotionBlur") else { return }
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        blur.setValue(0.0, forKey: kCIInputAngleKey)
        layer.masksToBounds = false
        layer.filters = [blur]
    }
} 

