import SwiftUI

enum FacetTheme {
    static let radius: CGFloat = 8

    static var canvas: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var panel: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var quietPanel: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.62)
    }

    static var hairline: Color {
        Color.primary.opacity(0.08)
    }

    static var softAccent: Color {
        Color.accentColor.opacity(0.11)
    }
}
