import FacetXCore
import SwiftUI
import UniformTypeIdentifiers

extension PlanView {
    var monthMap: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(planMonth.label, systemImage: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(weekRangeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                FacetInfoBadge(
                    text: "\(planMonthItems.count) \(L10n.t(.shownUnit))",
                    systemImage: "calendar.day.timeline.left",
                    tint: .secondary,
                    fill: Color.accentColor.opacity(0.08)
                )
            }

            weekdayHeader
            monthGrid
        }
        .padding(12)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private var weekdaySymbols: [String] {
        L10n.language == "zh"
            ? ["一", "二", "三", "四", "五", "六", "日"]
            : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let offset = planMonth.firstWeekdayOffset
        let days = planMonth.numberOfDays
        let totalCells = ((offset + days + 6) / 7) * 7

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 4
        ) {
            ForEach(0..<totalCells, id: \.self) { index in
                let day = index - offset + 1
                if day > 0 && day <= days {
                    monthDayCell(day)
                } else {
                    Color.clear
                        .frame(height: 40)
                }
            }
        }
    }

    private func monthDayCell(_ day: Int) -> some View {
        guard let date = planMonth.dateForDay(day) else {
            return AnyView(Color.clear.frame(height: 36))
        }

        let items = planItemsByMonthDay[day] ?? []
        let load = PlanDayLoad.measure(
            items,
            calendar: MonthYear.calendar,
            eventDefaultMinutes: settings.defaultEventDurationMinutes
        )
        let isCurrentWeek = week.contains(date)
        let isToday = MonthYear.calendar.isDateInToday(date)
        let isDropTarget = dropTargetDate.map { MonthYear.calendar.isDate($0, inSameDayAs: date) } ?? false

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(day)")
                        .font(.system(size: 11, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color.accentColor : .primary)
                    Spacer(minLength: 2)
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isCurrentWeek ? Color.accentColor : .secondary)
                    }
                }

                HStack(spacing: 3) {
                    monthKindDot(count: items.filter { $0.kind == .event }.count, color: ProjectItem.Kind.event.color)
                    monthKindDot(count: items.filter { $0.kind == .reminder }.count, color: ProjectItem.Kind.reminder.color)
                    Spacer(minLength: 0)
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(monthCellFill(isCurrentWeek: isCurrentWeek, hasItems: !items.isEmpty, isDropTarget: isDropTarget))
            .overlay(alignment: .bottom) {
                monthLoadBar(load)
            }
            .overlay(monthCellStroke(isCurrentWeek: isCurrentWeek, isToday: isToday, isDropTarget: isDropTarget))
            .contentShape(Rectangle())
            .onTapGesture {
                selectWeek(containing: date)
            }
            .onTapGesture(count: 2) {
                selectWeek(containing: date)
                onCreateItem(date)
            }
            .onDrop(of: ItemDragHelpers.acceptedTypes, delegate: dayDropDelegate(for: date, calendar: MonthYear.calendar))
            .help(monthCellHelp(for: date, load: load))
        )
    }

    @ViewBuilder
    private func monthKindDot(count: Int, color: Color) -> some View {
        if count > 0 {
            Circle()
                .fill(color.opacity(0.78))
                .frame(width: 5, height: 5)
        }
    }

    @ViewBuilder
    private func monthLoadBar(_ load: PlanDayLoad) -> some View {
        if load.hasWork {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(load.level.color.opacity(0.78))
                .frame(height: 3)
                .padding(.horizontal, 7)
                .padding(.bottom, 3)
                .help(load.detailLabel)
        }
    }

    private func monthCellHelp(for date: Date, load: PlanDayLoad) -> String {
        let base = L10n.language == "zh"
            ? "选择第 \(ISOWeek.containing(date).week) 周"
            : "Select Week \(ISOWeek.containing(date).week)"
        guard load.hasWork else { return base }
        return "\(base) · \(load.detailLabel)"
    }

    private func monthCellFill(isCurrentWeek: Bool, hasItems: Bool, isDropTarget: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                isDropTarget
                    ? Color.accentColor.opacity(0.22)
                    : isCurrentWeek
                        ? Color.accentColor.opacity(0.12)
                        : hasItems
                            ? Color.accentColor.opacity(0.045)
                            : Color.clear
            )
    }

    private func monthCellStroke(isCurrentWeek: Bool, isToday: Bool, isDropTarget: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(
                isDropTarget || isCurrentWeek || isToday
                    ? Color.accentColor.opacity(isDropTarget ? 0.55 : 0.34)
                    : FacetTheme.hairline,
                lineWidth: isDropTarget || isCurrentWeek ? 1.2 : 0.6
            )
    }
}
