import SwiftUI

/// Shared muted palette and radii for floating panels, chips, and menus.
enum PanelChrome {
    static let outerCorner: CGFloat = 14
    static let innerCorner: CGFloat = 10
    static let strokeSubtle = Color.primary.opacity(0.07)
    static let rowFillSelected = Color.accentColor.opacity(0.14)

    static let priorityHigh = Color(hue: 0.02, saturation: 0.42, brightness: 0.88)
    static let priorityMed = Color(hue: 0.09, saturation: 0.38, brightness: 0.86)
    static let priorityLow = Color(hue: 0.58, saturation: 0.32, brightness: 0.82)
    static let dateTime = Color(hue: 0.09, saturation: 0.36, brightness: 0.84)
    static let listAccent = Color(hue: 0.62, saturation: 0.28, brightness: 0.82)
    static let searchAccent = Color(hue: 0.55, saturation: 0.30, brightness: 0.80)

    static let chipFillGlow: Double = 0.42
    static let chipFillRest: Double = 0.28
    static let chipMaterialOpacity: Double = 0.35
    static let chipStrokeGlow: Double = 0.55
    static let chipStrokeRest: Double = 0.28
    static let chipShadowGlow: Double = 0.22
    static let chipShadowRadius: CGFloat = 3
}
