import FacetXCore
import SwiftUI

struct TodayTimelinePanel: View {
    @EnvironmentObject var ek: EventKitService
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var settings: AppSettings
    @Binding var isPresented: Bool

    @State private var items: [ProjectItem] = []
    @State private var selectedItem: ProjectItem?
    @State private var draggingItemID: String? = nil
    @State private var dragOffsetY: CGFloat = 0

    // MARK: – Derived

    var projectsByPrefix: [String: Project] {
        Dictionary(store.activeProjects.map { ($0.prefix, $0) }) { first, _ in first }
    }

    var timelinedItems: [ProjectItem] {
        ItemQuery.todayItems(items).filter {
            $0.kind == .event || ($0.kind == .reminder && $0.hasTime)
        }
    }

    var todayDateLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM d"
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
            if timelinedItems.isEmpty {
                ContentUnavailableView {
                    Label("No timed items today", systemImage: "sun.max")
                } description: {
                    Text("Timed tasks and events for today will appear here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        compactTimelineView
                    }
                    .onAppear {
                        scrollToCurrentHour(proxy: proxy)
                    }
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
        if let item = timelinedItems.first(where: { item in
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

        let eventPos = compactPositionedEvents(startHour: startHour, hourHeight: hourHeight)
        let reminderPos = reminderPositions(startHour: startHour, hourHeight: hourHeight)

        return HStack(spacing: 0) {
            // Hour labels
            VStack(spacing: 0) {
                ForEach(startHour..<endHour, id: \.self) { hour in
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(height: hourHeight, alignment: .top)
                        .padding(.top, 2)
                }
            }
            .frame(width: 42)

            // Reminder marker column
            ZStack(alignment: .topLeading) {
                ForEach(reminderPos.indices, id: \.self) { idx in
                    reminderMarker(reminderPos[idx])
                }
            }
            .frame(width: 80, height: totalHeight)

            // Event cards column (with grid)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(startHour...endHour, id: \.self) { _ in
                        Rectangle()
                            .fill(FacetTheme.hairline)
                            .frame(height: 0.5)
                            .frame(height: hourHeight, alignment: .top)
                    }
                }
                ForEach(eventPos.indices, id: \.self) { idx in
                    compactEventCard(eventPos[idx])
                }
                // Live drag time indicator
                if let draggingID = draggingItemID,
                   let draggingPos = eventPos.first(where: { $0.item.id == draggingID }),
                   let originalDate = draggingPos.item.date {
                    let hourHeight: CGFloat = 52
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
            }
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, timelineContentInset)
        .padding(.vertical, 14)
    }

    // MARK: – Layout engine

    struct PositionedEvent {
        let item: ProjectItem
        let yOffset: CGFloat
        let height: CGFloat
    }

    private func reminderPositions(startHour: Int, hourHeight: CGFloat) -> [PositionedEvent] {
        let cal = Calendar.current
        let startH = Double(startHour)
        return timelinedItems.compactMap { item -> PositionedEvent? in
            guard item.kind == .reminder, let date = item.date else { return nil }
            let h = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60.0
            let y = (h - startH) * Double(hourHeight)
            return PositionedEvent(item: item, yOffset: CGFloat(y), height: 20)
        }
    }

    private func compactPositionedEvents(startHour: Int, hourHeight: CGFloat) -> [PositionedEvent] {
        let cal = Calendar.current
        let startH = Double(startHour)

        let sorted = timelinedItems.compactMap { item -> (item: ProjectItem, start: Double, duration: Double)? in
            guard item.kind == .event, let date = item.date else { return nil }
            let h = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60.0
            let dur: Double
            if let end = item.endDate {
                dur = end.timeIntervalSince(date) / 3600.0
            } else {
                dur = 1.0
            }
            return (item, h, max(dur, 0.5))
        }.sorted { $0.start < $1.start }

        var result: [PositionedEvent] = []

        for event in sorted {
            let y = (event.start - startH) * Double(hourHeight)
            let h = event.duration * Double(hourHeight)
            var finalY = y

            for prev in result {
                let prevBottom = prev.yOffset + prev.height
                if finalY < prevBottom && prev.yOffset < finalY + CGFloat(h) {
                    finalY = prevBottom + 3
                }
            }

            result.append(PositionedEvent(item: event.item, yOffset: CGFloat(finalY), height: CGFloat(h)))
        }

        return result
    }

    // MARK: – Event card

    private func compactEventCard(_ pos: PositionedEvent) -> some View {
        let event = pos.item
        let isSelected = event.id == selectedItem?.id
        let project = projectsByPrefix[event.projectPrefix]
        let tint: Color = event.kind == .reminder ? .green : .blue
        let cardBg = isSelected ? tint.opacity(0.16) : tint.opacity(0.12)
        let cardStroke = isSelected ? tint.opacity(0.68) : tint.opacity(0.34)

        return Button {
            selectedItem = selectedItem?.id == event.id ? nil : event
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: event.kind == .reminder ? "checkmark.circle" : "calendar")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(tint)

                    Text(event.content)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }

                if let name = project?.name {
                    Text(name)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }

                if let date = event.date {
                    Text(timeString(for: event, start: date))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(5)
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
        .id(event.id)
        .frame(height: max(pos.height, 26))
        .offset(y: pos.yOffset + (draggingItemID == event.id ? dragOffsetY : 0))
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { val in
                    draggingItemID = event.id
                    dragOffsetY = val.translation.height
                }
                .onEnded { val in
                    let hourHeight: CGFloat = 52
                    let rawMinutes = (val.translation.height / hourHeight) * 60
                    let snappedMinutes = Int((rawMinutes / 15).rounded()) * 15
                    if let originalDate = event.date, snappedMinutes != 0 {
                        let newDate = Calendar.current.date(
                            byAdding: .minute,
                            value: snappedMinutes,
                            to: originalDate
                        ) ?? originalDate
                        Task { await rescheduleToTime(event, newDate: newDate) }
                    }
                    draggingItemID = nil
                    dragOffsetY = 0
                }
        )
        .zIndex(draggingItemID == event.id ? 1 : 0)
        .padding(.horizontal, 4)
    }

    private func reminderMarker(_ pos: PositionedEvent) -> some View {
        let isSelected = pos.item.id == selectedItem?.id
        return Button {
            selectedItem = selectedItem?.id == pos.item.id ? nil : pos.item
        } label: {
            HStack(alignment: .center, spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? Color.green : Color.green.opacity(0.55))
                    .frame(width: 3, height: 16)
                Text(pos.item.content)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(height: 20, alignment: .topLeading)
            .padding(.trailing, 4)
        }
        .buttonStyle(.plain)
        .id(pos.item.id)
        .offset(y: pos.yOffset)
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
}
