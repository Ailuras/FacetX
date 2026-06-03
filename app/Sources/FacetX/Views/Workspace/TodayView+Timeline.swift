import FacetXCore
import SwiftUI

extension TodayView {

    // MARK: – Timeline Content

    @ViewBuilder var timelineContent: some View {
        if filteredItems.isEmpty {
            emptyStateView
        } else {
            VStack(spacing: 0) {
                // All-day events strip
                if !allDayEvents.isEmpty {
                    allDayStrip
                }

                // Main scrollable area: timeline + reminders
                ScrollView {
                    VStack(spacing: 0) {
                        timelineView
                            .frame(minHeight: 400)

                        if !unscheduledReminders.isEmpty {
                            Divider()
                            reminderSection
                        }
                    }
                }
            }
        }
    }

    private var allDayStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text("All-day")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allDayEvents) { event in
                        allDayPill(event)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
    }

    private func allDayPill(_ event: ProjectItem) -> some View {
        Button {
            selectedItem = event
        } label: {
            Text(event.content)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: – Timeline View

    private var timelineView: some View {
        let events = timedEvents
        let startHour = settings.todayTimelineStartHour
        let endHour = settings.todayTimelineEndHour
        let hourHeight: CGFloat = 60
        let totalHeight = CGFloat(max(endHour - startHour, 1)) * hourHeight

        let positioned = positionedEvents(from: events, startHour: startHour, hourHeight: hourHeight)

        return HStack(spacing: 0) {
            // Time ruler
            timeRuler(startHour: startHour, endHour: endHour, hourHeight: hourHeight)
                .frame(width: 52)

            // Events area
            ZStack(alignment: .topLeading) {
                // Grid lines
                hourGridLines(startHour: startHour, endHour: endHour, hourHeight: hourHeight)

                // Events
                ForEach(positioned, id: \.item.id) { pos in
                    timelineEventCard(pos)
                }
            }
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: – Layout Engine

    struct PositionedEvent {
        let item: ProjectItem
        let yOffset: CGFloat
        let height: CGFloat
    }

    private func positionedEvents(from events: [ProjectItem], startHour: Int, hourHeight: CGFloat) -> [PositionedEvent] {
        let cal = Calendar.current
        let startH = Double(startHour)

        let sorted = events.compactMap { item -> (item: ProjectItem, start: Double, duration: Double)? in
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

            // Simple overlap handling: push down by 4pt per overlap layer
            var overlapCount = 0
            for prev in result {
                let prevBottom = prev.yOffset + prev.height
                if finalY < prevBottom && prev.yOffset < finalY + CGFloat(h) {
                    overlapCount += 1
                    finalY = prevBottom + 4
                }
            }

            result.append(PositionedEvent(item: event.item, yOffset: CGFloat(finalY), height: CGFloat(h)))
        }

        return result
    }

    // MARK: – Subviews

    private func timeRuler(startHour: Int, endHour: Int, hourHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: hourHeight, alignment: .top)
                    .padding(.top, 3)
            }
        }
    }

    private func hourGridLines(startHour: Int, endHour: Int, hourHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { _ in
                Rectangle()
                    .fill(FacetTheme.hairline)
                    .frame(height: 0.5)
                    .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    private func timelineEventCard(_ pos: PositionedEvent) -> some View {
        let event = pos.item
        let project = projectsByPrefix[event.projectPrefix]

        return Button {
            selectedItem = event
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.content)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if let projectName = project?.name {
                    Text(projectName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                if let date = event.date, let endDate = event.endDate {
                    Text(timeRangeString(start: date, end: endDate))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.accentColor.opacity(0.07))
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(height: max(pos.height, 28))
        .offset(y: pos.yOffset)
        .padding(.horizontal, 6)
    }

    private func timeRangeString(start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }

    // MARK: – Reminder Section

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Tasks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(unscheduledReminders.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(FacetTheme.canvas)
            .overlay(alignment: .bottom) {
                Rectangle().fill(FacetTheme.hairline).frame(height: 1)
            }

            LazyVStack(spacing: 0) {
                ForEach(unscheduledReminders) { item in
                    todayItemRow(item)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                }
            }
            .padding(.vertical, 6)
        }
        .background(FacetTheme.canvas)
    }
}
