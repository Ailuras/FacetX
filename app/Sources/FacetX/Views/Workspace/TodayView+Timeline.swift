import FacetXCore
import SwiftUI

extension TodayView {

    struct PositionedEvent {
        let item: ProjectItem
        let yOffset: CGFloat
        let height: CGFloat
    }

    // MARK: – Timeline Sidebar

    var timelineSidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()

            if timelinedItems.isEmpty {
                Text("No timed events today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        .background(FacetTheme.canvas)
    }

    private var sidebarHeader: some View {
        HStack {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Timeline")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            if let item = selectedItem {
                Text(item.content)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)
            }

            Button {
                withAnimation(sidebarAnimation) {
                    selectedItem = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close timeline")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
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
        let cardBg = isSelected ? Color.accentColor : Color.accentColor.opacity(0.06)
        let cardStroke = isSelected ? Color.accentColor : Color.accentColor.opacity(0.18)

        return Button {
            selectedItem = event
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.content)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                if let name = project?.name {
                    Text(name)
                        .font(.system(size: 8))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                }

                if let date = event.date, let end = event.endDate {
                    Text(timeRangeString(start: date, end: end))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
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
}
