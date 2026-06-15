import SwiftUI

/// A small palette of named colors used for sidebar filter labels. Stored by
/// name (in the metadata tables, e.g. `metadata_topics.color`) so persistence
/// stays human-readable and dependency-free.
enum LabelColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }

    /// Display label (capitalized name).
    var title: String { rawValue.capitalized }

    static func color(named name: String?) -> Color? {
        guard let name, let c = LabelColor(rawValue: name) else { return nil }
        return c.color
    }

    /// Deterministic per-tag color: hashes the tag name into the vibrant palette
    /// (gray excluded) so the same tag always renders the same hue across
    /// launches. Lets free-form user tags read as colored categories instead of
    /// one flat neutral pill.
    static func forTag(_ tag: String) -> Color {
        let palette = allCases.filter { $0 != .gray }
        var hash = 5381
        for byte in tag.utf8 { hash = ((hash << 5) &+ hash) &+ Int(byte) }
        return palette[abs(hash) % palette.count].color
    }
}

/// A curated palette of SF Symbols offered wherever the sidebar lets the user
/// pick a glyph (collections and topics). Kept in one place so both stay
/// consistent.
enum SidebarGlyph {
    static let choices: [(symbol: String, label: String)] = [
        ("folder", "Folder"), ("tray.full", "Tray"), ("book", "Book"),
        ("graduationcap", "Academic"), ("doc.text", "Document"), ("bookmark", "Bookmark"),
        ("star", "Star"), ("flag", "Flag"), ("tag", "Tag"),
        ("lightbulb", "Idea"), ("paperclip", "Clip"), ("archivebox", "Archive"),
        ("brain", "Brain"), ("function", "Function"), ("cpu", "Chip"),
        ("network", "Network"), ("chart.bar", "Chart"), ("atom", "Science"),
    ]
}
