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

struct ItemFilterMenuButton: View {
    @Binding var itemFilter: ItemListFilter

    var body: some View {
        Menu {
            Section("Kind") {
                kindButton(.all)
                kindButton(.tasks)
                kindButton(.events)
            }
            Section("Date") {
                dateButton(.all)
                dateButton(.today)
                dateButton(.nextSevenDays)
            }
            if itemFilter.isActive {
                Divider()
                Button {
                    itemFilter = ItemListFilter()
                } label: {
                    Label("Clear Filter", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: itemFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(itemFilter.isActive ? Color.accentColor : .secondary)
                .frame(width: 26, height: 24)
                .background(itemFilter.isActive ? Color.accentColor.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(itemFilter.isActive ? "Filter items" : "Add an item filter")
    }

    private func kindButton(_ scope: ItemKindScope) -> some View {
        Button {
            itemFilter.kindScope = scope
        } label: {
            HStack {
                Text(scope.rawValue)
                if itemFilter.kindScope == scope {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func dateButton(_ scope: ItemDateScope) -> some View {
        Button {
            itemFilter.dateScope = scope
        } label: {
            HStack {
                Text(scope.rawValue)
                if itemFilter.dateScope == scope {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

/// Shared action cluster for All, Week, and Month item lists.
struct ItemActionCluster<Accessory: View>: View {
    @Binding var itemFilter: ItemListFilter
    @Binding var showCompleted: Bool
    var animation: Animation = FacetTheme.listSpring
    let onAdd: () -> Void
    private let accessory: Accessory

    init(
        itemFilter: Binding<ItemListFilter>,
        showCompleted: Binding<Bool>,
        animation: Animation = FacetTheme.listSpring,
        onAdd: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self._itemFilter = itemFilter
        self._showCompleted = showCompleted
        self.animation = animation
        self.onAdd = onAdd
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 2) {
            accessory
            ItemFilterMenuButton(itemFilter: $itemFilter)
            FilterPillButton(
                systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle",
                help: showCompleted ? "Hide completed reminders" : "Show completed reminders",
                active: showCompleted
            ) {
                withAnimation(animation) { showCompleted.toggle() }
            }
            FilterPillButton(systemName: "plus", help: "Add an item to this project", action: onAdd)
        }
        .pillGroupContainer()
    }
}

extension ItemActionCluster where Accessory == EmptyView {
    init(
        itemFilter: Binding<ItemListFilter>,
        showCompleted: Binding<Bool>,
        animation: Animation = FacetTheme.listSpring,
        onAdd: @escaping () -> Void
    ) {
        self.init(
            itemFilter: itemFilter,
            showCompleted: showCompleted,
            animation: animation,
            onAdd: onAdd,
            accessory: { EmptyView() }
        )
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
