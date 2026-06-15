import SwiftUI

/// A small, tinted, rounded metadata pill used across VellumX: venue, score,
/// citations, dates, topics, "Today", and any future compact label. One
/// component so every list / detail / menu surface shares identical styling —
/// new chips reuse this instead of redrawing a bespoke pill.
///
/// Use the semantic factories (`.venue`, `.score`, `.citations`, `.date`) for
/// the common cases so icon and formatting choices stay centralized; fall back
/// to the memberwise initializer for one-off labels.
struct TagChip: View {
    /// Density. `small` suits dense list rows; `regular` the detail meta card.
    enum Size {
        case small
        case regular

        var font: Font {
            switch self {
            case .small:   return .system(size: 9, weight: .bold)
            case .regular: return .system(size: 11, weight: .bold)
            }
        }
        var horizontalPadding: CGFloat {
            switch self {
            case .small:   return 6
            case .regular: return 7
            }
        }
        var height: CGFloat {
            switch self {
            case .small:   return 16
            case .regular: return 20
            }
        }
        var iconSpacing: CGFloat { 3 }
        var cornerRadius: CGFloat { 4 }
    }

    /// Color treatment. `tinted` reads as a colored category chip; `subtle`
    /// recedes to secondary for neutral metadata like dates and citations.
    enum Emphasis {
        case tinted
        case subtle

        func background(_ color: Color) -> Color {
            switch self {
            case .tinted: return color.opacity(0.14)
            case .subtle: return Color.secondary.opacity(0.10)
            }
        }
        func foreground(_ color: Color) -> Color {
            switch self {
            case .tinted: return color
            case .subtle: return .secondary
            }
        }
    }

    let text: String
    var icon: String? = nil
    var color: Color = .secondary
    var size: Size = .small
    var emphasis: Emphasis = .tinted

    var body: some View {
        HStack(spacing: size.iconSpacing) {
            if let icon {
                Image(systemName: icon)
            }
            if !text.isEmpty {
                Text(text)
                    .lineLimit(1)
            }
        }
        .font(size.font)   // unified font keeps the SF Symbol on the text baseline
        .padding(.horizontal, size.horizontalPadding)
        .frame(height: size.height)
        .background(emphasis.background(color))
        .foregroundStyle(emphasis.foreground(color))
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
    }
}

// MARK: - Semantic factories

extension TagChip {
    /// Venue abbreviation, tinted by its field color.
    static func venue(_ abbr: String, color: Color, size: Size = .small) -> TagChip {
        TagChip(text: abbr, icon: "building.2", color: color, size: size)
    }

    /// Recommendation score, tinted by its tier color.
    static func score(_ score: Double, color: Color, size: Size = .small) -> TagChip {
        TagChip(text: String(format: "%.0f", score), icon: "star.fill", color: color, size: size)
    }

    /// Citation count — neutral, secondary styling.
    static func citations(_ count: Int, size: Size = .small) -> TagChip {
        TagChip(text: "\(count)", icon: "quote.bubble", size: size, emphasis: .subtle)
    }

    /// Publication date — neutral, secondary styling.
    static func date(_ text: String, size: Size = .small) -> TagChip {
        TagChip(text: text, icon: "calendar", size: size, emphasis: .subtle)
    }

    /// Marks that a validated PDF is stored locally — icon-only, green.
    static func pdf(size: Size = .small) -> TagChip {
        TagChip(text: "", icon: "doc.fill", color: .green, size: size)
    }

    /// Estimated minutes to read a passage — neutral, secondary styling.
    static func readingTime(minutes: Int, size: Size = .small) -> TagChip {
        TagChip(text: "\(minutes) min", icon: "clock", size: size, emphasis: .subtle)
    }
}
