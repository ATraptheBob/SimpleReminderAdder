import SwiftUI

public enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case midnightObsidian = "Midnight Obsidian"
    case frostGlass = "Frost Glass"
    case deepForest = "Deep Forest"
    case classicOrange = "Classic Orange"
    
    public var id: String { self.rawValue }
}

/// Shared muted palette and radii for floating panels, chips, and menus.
enum PanelChrome {
    static let outerCorner: CGFloat = 14
    static let pillCorner: CGFloat = 22
    static let innerCorner: CGFloat = 10
    
    static var currentTheme: AppTheme {
        let raw = UserDefaults.standard.string(forKey: "appTheme") ?? ""
        return AppTheme(rawValue: raw) ?? .system
    }
    
    static var strokeSubtle: Color {
        Color.primary.opacity(0.07)
    }
    
    static var accentColor: Color {
        switch currentTheme {
        case .system:
            return .accentColor
        case .midnightObsidian:
            return Color(hue: 0.70, saturation: 0.15, brightness: 0.75)
        case .frostGlass:
            return Color(hue: 0.55, saturation: 0.50, brightness: 0.90)
        case .deepForest:
            return Color(hue: 0.40, saturation: 0.35, brightness: 0.80)
        case .classicOrange:
            return Color.orange
        }
    }
    
    static var rowFillSelected: Color {
        accentColor.opacity(0.14)
    }

    static var priorityHigh: Color {
        switch currentTheme {
        case .midnightObsidian:
            return Color(hue: 0.0, saturation: 0.30, brightness: 0.70)
        case .deepForest:
            return Color(hue: 0.05, saturation: 0.40, brightness: 0.75)
        default:
            return Color(hue: 0.02, saturation: 0.42, brightness: 0.88)
        }
    }
    
    static var priorityMed: Color {
        switch currentTheme {
        case .midnightObsidian:
            return Color(hue: 0.10, saturation: 0.25, brightness: 0.75)
        case .deepForest:
            return Color(hue: 0.12, saturation: 0.35, brightness: 0.80)
        default:
            return Color(hue: 0.09, saturation: 0.38, brightness: 0.86)
        }
    }
    
    static var priorityLow: Color {
        switch currentTheme {
        case .midnightObsidian:
            return Color(hue: 0.60, saturation: 0.20, brightness: 0.75)
        case .deepForest:
            return Color(hue: 0.55, saturation: 0.25, brightness: 0.75)
        default:
            return Color(hue: 0.58, saturation: 0.32, brightness: 0.82)
        }
    }
    
    static var dateTime: Color {
        switch currentTheme {
        case .midnightObsidian:
            return Color(hue: 0.55, saturation: 0.15, brightness: 0.75)
        case .frostGlass:
            return Color(hue: 0.55, saturation: 0.40, brightness: 0.85)
        case .deepForest:
            return Color(hue: 0.15, saturation: 0.20, brightness: 0.75)
        default:
            return Color(hue: 0.09, saturation: 0.36, brightness: 0.84)
        }
    }
    
    static var listAccent: Color {
        switch currentTheme {
        case .midnightObsidian:
            return Color(hue: 0.65, saturation: 0.15, brightness: 0.75)
        case .frostGlass:
            return Color(hue: 0.55, saturation: 0.45, brightness: 0.85)
        case .deepForest:
            return Color(hue: 0.35, saturation: 0.25, brightness: 0.75)
        case .classicOrange:
            return Color.orange
        default:
            return Color(hue: 0.62, saturation: 0.28, brightness: 0.82)
        }
    }
    
    static var searchAccent: Color {
        switch currentTheme {
        case .midnightObsidian:
            return Color(hue: 0.50, saturation: 0.15, brightness: 0.75)
        case .frostGlass:
            return Color(hue: 0.50, saturation: 0.40, brightness: 0.85)
        case .deepForest:
            return Color(hue: 0.45, saturation: 0.25, brightness: 0.75)
        default:
            return Color(hue: 0.55, saturation: 0.30, brightness: 0.80)
        }
    }

    static let chipFillGlow: Double = 0.42
    static let chipFillRest: Double = 0.28
    static let chipMaterialOpacity: Double = 0.35
    static let chipStrokeGlow: Double = 0.55
    static let chipStrokeRest: Double = 0.28
    static let chipShadowGlow: Double = 0.22
    static let chipShadowRadius: CGFloat = 3
}
