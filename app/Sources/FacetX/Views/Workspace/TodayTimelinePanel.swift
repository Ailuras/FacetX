import FacetXCore
import SwiftUI
import UniformTypeIdentifiers

struct TodayTimelinePanel: View {
    @EnvironmentObject var ek: EventKitService
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var settings: AppSettings
    @Binding var isPresented: Bool

    @State private var items: [ProjectItem] = []
    @State private var selectedItem: ProjectItem?
    @State private var draggingItemID: String? = nil
    @State private var dragOffsetY: CGFloat = 0
    /// Snapped position + time label of an item being dragged in from the All
    /// list, shown as a live drop guide while hovering the grid.
    @State private var dropPreview: (y: CGFloat, label: String)? = nil

    // MARK: – Derived

    var projectsByPrefix: [String: Project] {
        Dictionary(store.activeProjects.map { ($0.prefix, $0) }) { first, _ in first }
    }

    var todayTimelineItems: [ProjectItem] {
        ItemQuery.todayItems(items).filter { item in
            switch item.kind {
            case .reminder:
                return !item.isCompleted && item.hasTime
            case .event:
                return !item.isAllDay
            }
        }
    }

    var todayDateLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        return fmt.string(from: Date())
    }

    // MARK: – Body

    var body: some View {
        FacetSidebarPane(
            title: "Today",
            systemImage: "sun.max.fill",
            subtitle: todayDateLabel,
            closeHelp: "Close Today panel",
            onClose: { withAnimation(FacetTheme.detailSpring) { isPresented = false } }
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    compactTimelineView
                }
                .onAppear {
                    scrollToCurrentHour(proxy: proxy)
                }
            }
            .overlay {
                if todayTimelineItems.isEmpty {
                    ContentUnavailableView {
                        Label("No timed items today", systemImage: "sun.max")
                    } description: {
                        Text("Drag an item from the list onto a time slot to schedule it.")
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .onAppear { Task { await reload() } }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
    }

    // MARK: – Scroll

    private func scrollToCurrentHour(proxy: ScrollViewProxy) {
        let hour = Calendar.current.component(.hour, from: Date())
        if let item = todayTimelineItems.first(where: { item in
            guard let d = item.date else { return false }
            return Calendar.current.component(.hour, from: d) >= hour
        }) {
            proxy.scrollTo(item.id, anchor: .center)
        }
    }

    // MARK: – Reload

    private func reload() async {
        let prefixes = Set(store.activeProjects.map(\.prefix))
        let fetched = await ek.items(
            forProjects: prefixes,
            enabledReminderLists: settings.effectiveReminderListNames,
            enabledCalendars: settings.effectiveCalendarNames
        )
        items = fetched
    }

    // MARK: – Timeline rendering

    private var timelineContentInset: CGFloat { FacetSidebarStyle.contentInset }

    private var compactTimelineView: some View {
        let startHour = settings.todayTimelineStartHour
        let endHour = settings.todayTimelineEndHour
        let hourHeight: CGFloat = 52
        let totalHeight = CGFloat(max(endHour - startHour, 1)) * hourHeight
        let itemPositions = compactPositionedItems(startHour: startHour, hourHeight: hourHeight)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                    // Hour labels
                    VStack(spacing: 0) {
                        ForEach(startHour..<endHour, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                                .frame(height: hourHeight, alignment: .top)
                        }
                    }
                    .frame(width: 42)

                    // Item cards with grid
                    ZStack(alignment: .topLeading) {
                        // Grid lines
                        VStack(spacing: 0) {
                            ForEach(startHour..<endHour, id: \.self) { _ in
                                Rectangle()
                                    .fill(FacetTheme.hairline)
                                    .frame(height: 0.5)
                                    .frame(height: hourHeight, alignment: .top)
                            }
                        }

                        // Item cards
                        ForEach(itemPositions.indices, id: \.self) { idx in
                            compactTimelineCard(itemPositions[idx])
                        }

                        // Live drag time indicator
                        if let draggingID = draggingItemID,
                           let draggingPos = itemPositions.first(where: { $0.item.id == draggingID }),
                           let originalDate = draggingPos.item.date {
                            let rawMinutes = (dragOffsetY / hourHeight) * 60
                            let snappedMinutes = Int((rawMinutes / 15).rounded()) * 15
                            let previewDate = Calendar.current.date(
                                byAdding: .minute, value: snappedMinutes, to: originalDate
                            ) ?? originalDate
                            Text(dragTimeLabel(previewDate))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.85))
                                .clipShape(Capsule())
                                .offset(y: draggingPos.yOffset + dragOffsetY - 20)
                                .allowsHitTesting(false)
                                .zIndex(200)
                        }

                        // Live drop guide for items dragged in from the All list
                        if let preview = dropPreview {
                            HStack(spacing: 5) {
                                Text(preview.label)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .clipShape(Capsule())
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.55))
                                    .frame(height: 1.5)
                            }
                            .offset(y: preview.y - 8)
                            .allowsHitTesting(false)
                            .zIndex(180)
                        }
                    }
                    .frame(height: totalHeight)
                    .frame(maxWidth: .infinity)
                    .onDrop(of: [.text], delegate: TimelineDropDelegate(
                        startHour: startHour,
                        endHour: endHour,
                        hourHeight: hourHeight,
                        onPreview: { dropPreview = $0 },
                        onCommit: { provider, date in handleTimelineDrop(provider: provider, date: date) }
                    ))
                }
            .padding(.horizontal, timelineContentInset)
            .padding(.vertical, 14)
        }
    }

    // MARK: – Layout engine

    struct PositionedTimelineItem {
        let item: ProjectItem
        let yOffset: CGFloat
        let height: CGFloat
    }

    private func compactPositionedItems(startHour: Int, hourHeight: CGFloat) -> [PositionedTimelineItem] {
        let cal = Calendar.current
        let startH = Double(startHour)

        let sorted = todayTimelineItems.compactMap { item -> (item: ProjectItem, start: Double, duration: Double)? in
            guard let date = item.date else { return nil }
            let h = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60.0
            let dur: Double
            if let end = item.endDate {
                dur = end.timeIntervalSince(date) / 3600.0
            } else {
                dur = 1.0
            }
            return (item, h, max(dur, 0.5))
        }.sorted { $0.start < $1.start }

        var result: [PositionedTimelineItem] = []

        for item in sorted {
            let y = (item.start - startH) * Double(hourHeight)
            let h = item.item.kind == .reminder ? 20.0 : item.duration * Double(hourHeight)
            var finalY = y

            for prev in result {
                let prevBottom = prev.yOffset + prev.height
                if finalY < prevBottom && prev.yOffset < finalY + CGFloat(h) {
                    finalY = prevBottom + 3
                }
            }

            result.append(PositionedTimelineItem(item: item.item, yOffset: CGFloat(finalY), height: CGFloat(h)))
        }

        return result
    }

    // MARK: – Timeline card

    private func compactTimelineCard(_ pos: PositionedTimelineItem) -> some View {
        let item = pos.item
        let isSelected = item.id == selectedItem?.id
        let project = projectsByPrefix[item.projectPrefix]
        let tint: Color = item.kind == .reminder ? .green : .blue
        let cardBg = isSelected ? tint.opacity(0.16) : tint.opacity(0.12)
        let cardStroke = isSelected ? tint.opacity(0.68) : tint.opacity(0.34)
        let isReminder = item.kind == .reminder

        return Button {
            selectedItem = selectedItem?.id == item.id ? nil : item
        } label: {
            Group {
                if isReminder {
                    Text(item.content)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(tint)

                            Text(item.content)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }

                        if let name = project?.name {
                            Text(name)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }

                        if let date = item.date {
                            Text(timeString(for: item, start: date))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, isReminder ? 6 : 5)
            .padding(.vertical, isReminder ? 3 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .id(item.id)
        .frame(height: max(pos.height, isReminder ? 20 : 26))
        .offset(y: pos.yOffset + (draggingItemID == item.id ? dragOffsetY : 0))
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { val in
                    draggingItemID = item.id
                    dragOffsetY = val.translation.height
                }
                .onEnded { val in
                    let hourHeight: CGFloat = 52
                    let rawMinutes = (val.translation.height / hourHeight) * 60
                    let snappedMinutes = Int((rawMinutes / 15).rounded()) * 15
                    if let originalDate = item.date, snappedMinutes != 0 {
                        let newDate = Calendar.current.date(
                            byAdding: .minute,
                            value: snappedMinutes,
                            to: originalDate
                        ) ?? originalDate
                        // Optimistic update — move card visually before EventKit confirms
                        applyOptimisticReschedule(item: item, newDate: newDate)
                        Task { await rescheduleToTime(item, newDate: newDate) }
                    }
                    draggingItemID = nil
                    dragOffsetY = 0
                }
        )
        .zIndex(draggingItemID == item.id ? 1 : 0)
        .padding(.horizontal, 4)
    }

    private func timeRangeString(start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }

    private func timeString(for item: ProjectItem, start: Date) -> String {
        guard let end = item.endDate else {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            return fmt.string(from: start)
        }
        return timeRangeString(start: start, end: end)
    }

    // MARK: – Drag reschedule

    private func dragTimeLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func applyOptimisticReschedule(item: ProjectItem, newDate: Date) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newEndDate: Date?
        if let origStart = item.date, let origEnd = item.endDate {
            newEndDate = newDate.addingTimeInterval(origEnd.timeIntervalSince(origStart))
        } else {
            newEndDate = nil
        }
        var updated = items
        updated[idx] = item.replacingDate(newDate, endDate: newEndDate, hasTime: true)
        items = updated
    }

    private func rescheduleToTime(_ item: ProjectItem, newDate: Date) async {
        let newEndDate: Date?
        if let origStart = item.date, let origEnd = item.endDate {
            let duration = origEnd.timeIntervalSince(origStart)
            newEndDate = newDate.addingTimeInterval(duration)
        } else {
            newEndDate = nil
        }
        _ = await ek.updateItem(
            id: item.id,
            project: item.projectPrefix,
            content: item.content,
            date: newDate,
            useDate: true,
            dateIncludesTime: true,
            containerName: item.containerName,
            notes: item.notes,
            tags: item.tags,
            priority: item.priority,
            isAllDay: false,
            endDate: newEndDate
        )
        // ek.changeToken fires automatically → .onChange(of: ek.changeToken) in body triggers reload()
    }

    // MARK: – Drop-to-schedule (from the All list)

    /// Resolve the dragged item id off the provider, then schedule it onto
    /// today at `date`. The All list registers each row as an `NSString` id.
    private func handleTimelineDrop(provider: NSItemProvider, date: Date) {
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            Task { @MainActor in await scheduleDroppedItem(id: id, at: date) }
        }
    }

    @MainActor
    private func scheduleDroppedItem(id: String, at start: Date) async {
        guard let item = items.first(where: { $0.id == id }), !item.isCompleted else { return }

        let end: Date?
        if item.kind == .event {
            if !item.isAllDay, let s = item.date, let e = item.endDate, e > s {
                end = start.addingTimeInterval(e.timeIntervalSince(s))
            } else {
                end = Calendar.current.date(
                    byAdding: .minute, value: settings.defaultEventDurationMinutes, to: start
                )
            }
        } else {
            end = nil
        }

        applyDroppedOptimistic(item: item, start: start, end: end)
        _ = await ek.updateItem(
            id: item.id,
            project: item.projectPrefix,
            content: item.content,
            date: start,
            useDate: true,
            dateIncludesTime: true,
            containerName: item.containerName,
            notes: item.notes,
            tags: item.tags,
            priority: item.priority,
            isAllDay: item.kind == .event ? false : nil,
            endDate: end
        )
        // ek.changeToken fires automatically → reload() reconciles with EventKit.
    }

    /// Drop the item onto the timeline immediately as a timed item, before
    /// EventKit confirms — mirrors `applyOptimisticReschedule` but also clears
    /// the all-day / untimed flags so it surfaces in `todayTimelineItems`.
    private func applyDroppedOptimistic(item: ProjectItem, start: Date, end: Date?) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        updated[idx] = ProjectItem(
            id: item.id,
            kind: item.kind,
            rawTitle: item.rawTitle,
            projectPrefix: item.projectPrefix,
            content: item.content,
            containerName: item.containerName,
            isCompleted: item.isCompleted,
            date: start,
            notes: item.notes,
            tags: item.tags,
            priority: item.priority,
            url: item.url,
            hasTime: true,
            isAllDay: false,
            endDate: end
        )
        items = updated
    }
}

/// Accepts an item dragged from the All list and turns the drop location into a
/// 15-minute-snapped time on today's timeline, reporting a live guide position
/// while hovering.
private struct TimelineDropDelegate: DropDelegate {
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let onPreview: ((y: CGFloat, label: String)?) -> Void
    let onCommit: (NSItemProvider, Date) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) { updatePreview(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePreview(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { onPreview(nil) }

    func performDrop(info: DropInfo) -> Bool {
        onPreview(nil)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        onCommit(provider, snappedDate(forY: info.location.y))
        return true
    }

    private func updatePreview(_ info: DropInfo) {
        let date = snappedDate(forY: info.location.y)
        onPreview((y: yOffset(for: date), label: label(for: date)))
    }

    /// Map a vertical drop offset to a concrete time on today, snapped to the
    /// nearest 15 minutes and clamped to the visible hour range.
    private func snappedDate(forY y: CGFloat) -> Date {
        let minutesFromTop = Double(max(y, 0) / hourHeight) * 60
        let absolute = Double(startHour) * 60 + minutesFromTop
        let snapped = (absolute / 15).rounded() * 15
        let clamped = min(max(snapped, Double(startHour) * 60), Double(endHour) * 60 - 15)
        let hour = Int(clamped) / 60
        let minute = Int(clamped) % 60
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func yOffset(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60
        return CGFloat((h - Double(startHour)) * Double(hourHeight))
    }

    private func label(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
