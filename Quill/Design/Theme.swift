import SwiftUI

enum Theme {
    /// Modern minimal greys — soft paper, charcoal ink, cool mid-grey accents.
    static let ink = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let steel = Color(red: 0.38, green: 0.39, blue: 0.41)
    static let steelBright = Color(red: 0.52, green: 0.53, blue: 0.55)
    static let mist = Color(red: 0.90, green: 0.90, blue: 0.91)
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let accent = steelBright
    static let danger = Color(red: 0.72, green: 0.30, blue: 0.28)
    static let caution = Color(red: 0.72, green: 0.55, blue: 0.22)
    static let ok = Color(red: 0.32, green: 0.52, blue: 0.40)

    static let brandName = "Quill"
    static let brandSubtitle = "Pen plotter for home makers"

    static var brandFont: Font {
        .system(.largeTitle, design: .rounded).weight(.bold)
    }

    static var stepTitleFont: Font {
        .system(.title2, design: .rounded).weight(.semibold)
    }

    static var bodyFont: Font {
        .system(.body, design: .rounded)
    }

    static var captionFont: Font {
        .system(.caption, design: .rounded)
    }
}
