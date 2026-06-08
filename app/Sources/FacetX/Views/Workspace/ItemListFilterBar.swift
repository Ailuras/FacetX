import AppKit
import FacetXCore
import SwiftUI

/// The active include/exclude tag filters with quick removal. Shared by the
/// All, Week and Month views so the filter chips look identical everywhere.
struct ActiveTagFilterBar: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var tagFilter: TagFilter

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tagFilter.included).sorted(), id: \.self) { tag in
                miniTagBadge(tag: tag, included: true)
            }
            ForEach(Array(tagFilter.excluded).sorted(), id: \.self) { tag in
                miniTagBadge(tag: tag, included: false)
            }
            Button {
                tagFilter.clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear all tag filters")
        }
    }

    private func miniTagBadge(tag: String, included: Bool) -> some View {
        let color = settings.tagColor(for: tag)
        return Button {
            if included { tagFilter.included.remove(tag) }
            else { tagFilter.excluded.remove(tag) }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: included ? "plus" : "minus")
                    .font(.system(size: 8, weight: .bold))
                Text(tag)
                    .font(.system(size: 11, weight: .semibold))
                    .strikethrough(!included)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(included ? 0.14 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(color.opacity(included ? 0.30 : 0.55),
                            style: StrokeStyle(lineWidth: 1, dash: included ? [] : [2.5, 2]))
            )
        }
        .buttonStyle(.plain)
        .help(included ? "Remove include filter" : "Remove exclude filter")
    }
}

/// A single pill button matching the All view's action-cluster styling. Shared
/// so the Week/Month controls are pixel-identical to the All view.
struct FilterPillButton: View {
    let systemName: String
    let help: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .frame(width: 26, height: 24)
                .background(active ? Color.accentColor.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The show-completed toggle wrapped in the shared pill-group container, used by
/// the Week and Month views so their top-right control matches the All view.
struct ShowCompletedCluster: View {
    @Binding var showCompleted: Bool
    var animation: Animation = FacetTheme.listSpring

    var body: some View {
        HStack(spacing: 2) {
            FilterPillButton(
                systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle",
                help: showCompleted ? "Hide completed reminders" : "Show completed reminders",
                active: showCompleted
            ) {
                withAnimation(animation) { showCompleted.toggle() }
            }
        }
        .pillGroupContainer()
    }
}

extension View {
    /// The rounded, hairline-stroked container that wraps the All view's pill
    /// action group. Shared so the Week/Month clusters match exactly.
    func pillGroupContainer() -> some View {
        self
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
            )
    }
}
