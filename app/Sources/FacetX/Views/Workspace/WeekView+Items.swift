import FacetXCore
import SwiftUI

extension WeekView {
    @ViewBuilder var itemsSection: some View {
        if loading {
            ProgressView()
        } else if nonGoalItems.isEmpty && hasActiveSearch {
            Text("No items match this search.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            List {
                ForEach(dayGroups) { group in
                    Section {
                        if group.items.isEmpty {
                            Text("No items")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 4)
                        } else {
                            if !group.scheduleItems.isEmpty {
                                dayKindHeader("Schedule", systemImage: "calendar", count: group.scheduleItems.count, color: .blue)
                                ForEach(group.scheduleItems) { item in
                                    weekItemRow(item)
                                }
                            }

                            if !group.taskItems.isEmpty {
                                dayKindHeader("Tasks", systemImage: "checklist", count: group.taskItems.count, color: .green)
                                ForEach(group.taskItems) { item in
                                    weekItemRow(item)
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(group.isToday ? Color.accentColor : .secondary)
                            if group.isToday {
                                Text("Today")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Text("\(group.items.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Button {
                                createDate = DateWrapper(date: group.date)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Add item for \(group.label)")
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(listAnimation, value: nonGoalItems.map { "\($0.id)-\($0.isCompleted)" })
        }
    }

    func dayKindHeader(_ title: String, systemImage: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.top, 5)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 1, trailing: 0))
    }

    func weekItemRow(_ item: ProjectItem) -> some View {
        ItemRow(
            item: item,
            isSelected: item.id == selectedItem?.id,
            showDragGrip: false,
            onToggle: { completed in
                Task {
                    await ItemActionHelpers.toggleCompletion(item, completed: completed, ek: ek)
                    await reload()
                }
            },
            onEdit: {
                selectItem(item)
            },
            inlineEditingText: $inlineEditingText,
            isInlineEditing: item.id == inlineEditingID,
            onInlineCommit: {
                commitInlineEdit(for: item)
            },
            onInlineCancel: {
                cancelInlineEdit(for: item)
            }
        )
        .contextMenu {
            Button("Edit...") { selectItem(item) }
            Button("Delete", role: .destructive) {
                Task { await ItemActionHelpers.deleteItem(item, ek: ek); await reload() }
            }
        }
        .itemSelectionGestures(
            item: item,
            selectedItem: $selectedItem,
            onDoubleTap: { startInlineEdit(for: item) }
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        ))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
    }

    func startInlineEdit(for item: ProjectItem) {
        ItemEditHelpers.startTitleEdit(for: item, editingID: &inlineEditingID, editingText: &inlineEditingText)
    }

    func commitInlineEdit(for item: ProjectItem) {
        Task {
            _ = await ItemEditHelpers.commitTitleEdit(
                editingID: inlineEditingID,
                editingText: inlineEditingText,
                for: item,
                projectPrefix: project.prefix,
                ek: ek
            )
            inlineEditingID = nil
            await reload()
        }
    }

    func cancelInlineEdit(for item: ProjectItem) {
        ItemEditHelpers.cancelTitleEdit(editingID: &inlineEditingID)
    }

    func selectItem(_ item: ProjectItem) {
        withAnimation(.easeOut(duration: 0.15)) {
            if selectedItem?.id == item.id {
                selectedItem = nil
            } else {
                selectedItem = item
            }
        }
    }
}
