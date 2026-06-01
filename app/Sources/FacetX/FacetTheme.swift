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

    /// Color for an EventKit reminder priority (1 = high … 9 = low), as a heat
    /// gradient. Shared by the row stripe and the editor pill so the same
    /// priority never shows two different colors.
    static func priorityColor(_ value: Int) -> Color {
        switch value {
        case 1...4: return .red
        case 5: return .orange
        case 6...9: return .blue
        default: return .secondary
        }
    }
}
