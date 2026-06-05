import FacetXCore
import SwiftUI

extension TodayView {

    struct PositionedEvent {
        let item: ProjectItem
        let yOffset: CGFloat
        let height: CGFloat
    }

    private var timelineContentInset: CGFloat { FacetSidebarStyle.contentInset }

    // MARK: – Timeline Sidebar

    var timelineSidebar: some View {
        FacetSidebarPane(
            title: "Timeline",
            systemImage: "clock",
            subtitle: selectedItem?.content,
            closeHelp: "Close timeline",
            onClose: {
                withAnimation(sidebarAnimation) {
                    selectedItem = nil
                }
            }
        ) {
            if timelinedItems.isEmpty {
                ContentUnavailableView {
                    Label("No timed items", systemImage: "clock")
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
                        if let item = selectedItem {
                            proxy.scrollTo(item.id, anchor: .center)
                        }
                    }
                    .onChange(of: selectedItem?.id) { _, newID in
                        if let id = newID {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: – Compact Timeline

    private var compactTimelineView: some View {
        let startHour = settings.todayTimelineStartHour
        let endHour = settings.todayTimelineEndHour
        let hourHeight: CGFloat = 52
        let totalHeight = CGFloat(max(endHour - startHour, 1)) * hourHeight

        let positioned = compactPositionedEvents(startHour: startHour, hourHeight: hourHeight)

        return HStack(spacing: 0) {
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

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(startHour...endHour, id: \.self) { _ in
                        Rectangle()
                            .fill(FacetTheme.hairline)
                            .frame(height: 0.5)
                            .frame(height: hourHeight, alignment: .top)
                    }
                }

                ForEach(positioned.indices, id: \.self) { idx in
                    compactEventCard(positioned[idx])
                }
            }
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, timelineContentInset)
        .padding(.vertical, 14)
    }

    // MARK: – Layout Engine

    private func compactPositionedEvents(startHour: Int, hourHeight: CGFloat) -> [PositionedEvent] {
        let cal = Calendar.current
        let startH = Double(startHour)

        let sorted = timelinedItems.compactMap { item -> (item: ProjectItem, start: Double, duration: Double)? in
            guard let date = item.date else { return nil }
            let h = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60.0
            let dur: Double
            if let end = item.endDate {
                dur = end.timeIntervalSince(date) / 3600.0
            } else if item.kind == .reminder {
                dur = 0.5
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
        let cardBg = isSelected ? tint.opacity(0.16) : tint.opacity(0.07)
        let cardStroke = isSelected ? tint.opacity(0.68) : tint.opacity(0.22)

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
        .offset(y: pos.yOffset)
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
}
