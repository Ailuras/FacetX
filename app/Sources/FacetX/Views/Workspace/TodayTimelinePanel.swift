import FacetXCore
import SwiftUI
import UniformTypeIdentifiers

struct TodayTimelinePanel: View {
    @EnvironmentObject var ek: EventKitService
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var settings: AppSettings
    @Binding var isPresented: Bool
    @Binding var isFullscreen: Bool

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
            title: L10n.t(.today),
            systemImage: "sun.max.fill",
            closeHelp: L10n.t(.closeTodayPanel),
            fillWidth: isFullscreen,
            onClose: { withAnimation(FacetTheme.detailSpring) { isPresented = false } },
            accessory: { todayFullscreenToggle }
        ) {
            ScrollViewReader { proxy in
                ScrollView {
                    compactTimelineView
                        .hideScrollIndicators()
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToCurrentHour(proxy: proxy)
                }
            }
        }
        .onAppear { Task { await reload() } }
        .onChange(of: ek.changeToken) { Task { await reload() } }
        .onChange(of: settings.changeToken) { Task { await reload() } }
    }

    private var todayFullscreenToggle: some View {
        Button {
            withAnimation(FacetTheme.detailSpring) { isFullscreen.toggle() }
        } label: {
            Image(systemName: isFullscreen
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .facetHoverSurface(tint: .secondary,
                                   fill: Color.clear,
                                   hoverFill: Color.primary.opacity(0.055),
                                   hoverStroke: FacetTheme.hairline)
        }
        .buttonStyle(.plain)
        .help(isFullscreen ? L10n.pick("Exit fullscreen", "退出全屏")
                           : L10n.pick("Fullscreen", "全屏"))
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

                        // Item cards — laid out in overlap columns within the area width.
                        GeometryReader { geo in
                            ForEach(itemPositions.indices, id: \.self) { idx in
                                compactTimelineCard(itemPositions[idx], containerWidth: geo.size.width)
                            }
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
                    .onDrop(of: ItemDragHelpers.acceptedTypes, delegate: TimelineDropDelegate(
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
        /// Lane index and total lanes in this item's overlap cluster, used to lay
        /// overlapping items out in side-by-side columns rather than stacking.
        var column: Int = 0
        var columnCount: Int = 1
    }

    /// Lay items at their true time positions, then split overlapping items into
    /// side-by-side columns (calendar-style) instead of pushing them downward.
    private func compactPositionedItems(startHour: Int, hourHeight: CGFloat) -> [PositionedTimelineItem] {
        let cal = Calendar.current
        let startH = Double(startHour)

        let sorted = todayTimelineItems.compactMap { item -> (item: ProjectItem, start: Double, duration: Double)? in
            guard let date = item.date else { return nil }
            let h = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60.0
            return (item, h, max(FacetSessionDuration.hours(
                for: item,
                eventDefaultMinutes: settings.defaultEventDurationMinutes,
                paperDefaultMinutes: settings.defaultPaperSessionMinutes,
                noteDefaultMinutes: settings.defaultNoteSessionMinutes
            ), 0.5))
        }.sorted { $0.start < $1.start }

        var result: [PositionedTimelineItem] = sorted.map { entry in
            let y = (entry.start - startH) * Double(hourHeight)
            let h = entry.item.facetKind == .task ? 20.0 : entry.duration * Double(hourHeight)
            return PositionedTimelineItem(item: entry.item, yOffset: CGFloat(y), height: CGFloat(h))
        }

        assignColumns(&result)
        return result
    }

    /// Greedy lane assignment: walk items top-to-bottom, reuse a freed lane when
    /// one exists, otherwise open a new one. A cluster ends once an item starts at
    /// or below every active lane's bottom; every item in a cluster shares the
    /// cluster's lane count so their widths match.
    private func assignColumns(_ items: inout [PositionedTimelineItem]) {
        let order = items.indices.sorted {
            items[$0].yOffset != items[$1].yOffset
                ? items[$0].yOffset < items[$1].yOffset
                : items[$0].height > items[$1].height
        }

        var laneBottoms: [CGFloat] = []   // current bottom y of each active lane
        var cluster: [Int] = []           // result indices in the current cluster
        var clusterLanes = 0

        func flush() {
            for i in cluster { items[i].columnCount = max(clusterLanes, 1) }
            cluster.removeAll()
            laneBottoms.removeAll()
            clusterLanes = 0
        }

        for idx in order {
            let top = items[idx].yOffset
            let bottom = top + items[idx].height
            if !laneBottoms.isEmpty, top >= (laneBottoms.max() ?? 0) {
                flush()
            }
            var lane = laneBottoms.firstIndex(where: { $0 <= top }) ?? -1
            if lane == -1 {
                laneBottoms.append(bottom)
                lane = laneBottoms.count - 1
            } else {
                laneBottoms[lane] = bottom
            }
            items[idx].column = lane
            cluster.append(idx)
            clusterLanes = max(clusterLanes, laneBottoms.count)
        }
        flush()
    }

    // MARK: – Timeline card

    private func compactTimelineCard(_ pos: PositionedTimelineItem, containerWidth: CGFloat) -> some View {
        let item = pos.item
        let isSelected = item.id == selectedItem?.id
        let project = projectsByPrefix[item.projectPrefix]
        let tint: Color = item.facetKind.color
        let cardBg = isSelected ? tint.opacity(0.16) : tint.opacity(0.12)
        let cardStroke = isSelected ? tint.opacity(0.68) : tint.opacity(0.34)
        let isCompactMarker = item.facetKind == .task

        let gutter: CGFloat = 3
        let columnCount = max(pos.columnCount, 1)
        let cardWidth = max((containerWidth - gutter * CGFloat(columnCount - 1)) / CGFloat(columnCount), 1)
        let xOffset = CGFloat(pos.column) * (cardWidth + gutter)

        return Button {
            selectedItem = selectedItem?.id == item.id ? nil : item
        } label: {
            Group {
                if isCompactMarker {
                    Text(item.content)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: item.facetKind.systemImage)
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
            .padding(.horizontal, isCompactMarker ? 6 : 5)
            .padding(.vertical, isCompactMarker ? 3 : 5)
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
        .frame(width: cardWidth, height: max(pos.height, isCompactMarker ? 20 : 26), alignment: .topLeading)
        .offset(x: xOffset, y: pos.yOffset + (draggingItemID == item.id ? dragOffsetY : 0))
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
    }

    private func timeRangeString(start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }

    private func timeString(for item: ProjectItem, start: Date) -> String {
        guard let end = timelineEnd(for: item, start: start) else {
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

    private func timelineEnd(for item: ProjectItem, start: Date) -> Date? {
        FacetSessionDuration.endDate(
            for: item,
            start: start,
            eventDefaultMinutes: settings.defaultEventDurationMinutes,
            paperDefaultMinutes: settings.defaultPaperSessionMinutes,
            noteDefaultMinutes: settings.defaultNoteSessionMinutes
        )
    }

    private func applyOptimisticReschedule(item: ProjectItem, newDate: Date) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newEndDate = timelineEnd(for: item, start: newDate)
        var updated = items
        updated[idx] = item.replacingDate(newDate, endDate: newEndDate, hasTime: true)
        items = updated
    }

    private func rescheduleToTime(_ item: ProjectItem, newDate: Date) async {
        let newEndDate = timelineEnd(for: item, start: newDate)
        _ = await ek.updateItem(
            id: item.id,
            project: item.projectPrefix,
            content: item.content,
            date: newDate,
            useDate: true,
            dateIncludesTime: true,
            containerName: item.containerName,
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
        if provider.hasItemConformingToTypeIdentifier(UTType.facetXProjectItem.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.facetXProjectItem.identifier) { data, _ in
                if let data,
                   let mention = try? JSONDecoder().decode(AssistantItemMention.self, from: data) {
                    Task { @MainActor in await scheduleDroppedItem(id: mention.eventKitID, at: date) }
                }
            }
            return
        }
        loadPlainTimelineDrop(provider: provider, date: date)
    }

    private func loadPlainTimelineDrop(provider: NSItemProvider, date: Date) {
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            Task { @MainActor in await scheduleDroppedItem(id: id, at: date) }
        }
    }

    @MainActor
    private func scheduleDroppedItem(id: String, at start: Date) async {
        dropPreview = nil
        guard let item = items.first(where: { $0.id == id }), !item.isCompleted else { return }

        let end = timelineEnd(for: item, start: start)

        applyDroppedOptimistic(item: item, start: start, end: end)
        _ = await ek.updateItem(
            id: item.id,
            project: item.projectPrefix,
            content: item.content,
            date: start,
            useDate: true,
            dateIncludesTime: true,
            containerName: item.containerName,
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
        info.hasItemsConforming(to: ItemDragHelpers.acceptedTypes)
    }

    func dropEntered(info: DropInfo) { updatePreview(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePreview(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { onPreview(nil) }

    func performDrop(info: DropInfo) -> Bool {
        // Clear on the next runloop: a state write made synchronously here can be
        // dropped as SwiftUI tears down the drag-tracking transaction, which would
        // leave the time guide stranded after a successful drop.
        DispatchQueue.main.async { onPreview(nil) }
        guard let provider = itemProvider(from: info) else { return false }
        onCommit(provider, snappedDate(forY: info.location.y))
        return true
    }

    private func itemProvider(from info: DropInfo) -> NSItemProvider? {
        for type in ItemDragHelpers.acceptedTypes {
            if let provider = info.itemProviders(for: [type]).first {
                return provider
            }
        }
        return nil
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
