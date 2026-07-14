import SwiftUI

struct GitActivityHeatmap: View {
    let activity: [LocalGitActivityDay]
    let selectedDate: Date?
    let onSelect: (Date) -> Void

    private let calendar = Calendar.autoupdatingCurrent
    private let columnCount = 53
    private let cellSpacing: CGFloat = 3

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var weekStart: Date {
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
    }

    private var firstWeekStart: Date {
        calendar.date(byAdding: .weekOfYear, value: -(columnCount - 1), to: weekStart) ?? weekStart
    }

    private var counts: [Date: Int] {
        Dictionary(uniqueKeysWithValues: activity.map {
            (calendar.startOfDay(for: $0.date), $0.commitCount)
        })
    }

    private var maximumCount: Int {
        max(activity.map(\.commitCount).max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let labelWidth: CGFloat = 26
            let availableWidth = max(proxy.size.width - labelWidth - 8, 0)
            let calculated = (availableWidth - CGFloat(columnCount - 1) * cellSpacing) / CGFloat(columnCount)
            let cellSize = max(7, min(12, calculated))
            let gridWidth = CGFloat(columnCount) * cellSize + CGFloat(columnCount - 1) * cellSpacing
            let groupWidth = labelWidth + 8 + gridWidth

            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Color.clear.frame(width: labelWidth, height: 14)
                    monthAxis(cellSize: cellSize, gridWidth: gridWidth)
                }

                HStack(alignment: .top, spacing: 8) {
                    weekdayLabels(cellSize: cellSize)
                        .frame(width: labelWidth)

                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(0..<columnCount, id: \.self) { weekOffset in
                            weekColumn(offset: weekOffset, cellSize: cellSize)
                        }
                    }
                }
            }
            .frame(width: groupWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 121)
        .padding(12)
        .background(FacetTheme.quietPanel)
        .clipShape(RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FacetTheme.radius, style: .continuous)
                .stroke(FacetTheme.hairline, lineWidth: 1)
        )
    }

    private func weekdayLabels(cellSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                Text(weekdayLabel(row))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: cellSize, alignment: .trailing)
            }
        }
    }

    private func weekColumn(offset: Int, cellSize: CGFloat) -> some View {
        let start = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeekStart) ?? firstWeekStart
        return VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { dayOffset in
                let date = calendar.date(byAdding: .day, value: dayOffset, to: start) ?? start
                dayCell(date: date, size: cellSize)
            }
        }
    }

    private func monthAxis(cellSize: CGFloat, gridWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthOffsets, id: \.self) { offset in
                let start = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeekStart) ?? firstWeekStart
                Text(monthLabel(for: start))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 14, alignment: .leading)
                    .offset(x: CGFloat(offset) * (cellSize + cellSpacing))
            }
        }
        .frame(width: gridWidth, height: 14, alignment: .leading)
        .clipped()
        .allowsHitTesting(false)
    }

    private var monthOffsets: [Int] {
        (0..<columnCount).filter { offset in
            guard offset > 0,
                  let start = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeekStart),
                  let previous = calendar.date(byAdding: .weekOfYear, value: offset - 1, to: firstWeekStart) else {
                return offset == 0
            }
            return calendar.component(.month, from: start) != calendar.component(.month, from: previous)
        }
    }

    private func dayCell(date: Date, size: CGFloat) -> some View {
        let normalized = calendar.startOfDay(for: date)
        let count = counts[normalized, default: 0]
        let isFuture = normalized > today
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: normalized) } ?? false
        let isToday = calendar.isDateInToday(normalized)

        return Button {
            onSelect(normalized)
        } label: {
            RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous)
                .fill(isFuture ? Color.clear : heatColor(count: count))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 2)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: max(2, size * 0.22), style: .continuous)
                            .stroke(Color.primary.opacity(0.48), lineWidth: 1)
                    }
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .help(dayHelp(date: normalized, count: count))
    }

    private func heatColor(count: Int) -> Color {
        guard count > 0 else { return Color.primary.opacity(0.045) }
        let ratio = Double(count) / Double(maximumCount)
        switch ratio {
        case ..<0.25: return Color.accentColor.opacity(0.22)
        case ..<0.50: return Color.accentColor.opacity(0.42)
        case ..<0.75: return Color.accentColor.opacity(0.64)
        default: return Color.accentColor.opacity(0.90)
        }
    }

    private func monthLabel(for weekStart: Date) -> String {
        return weekStart.formatted(.dateTime.month(.abbreviated))
    }

    private func weekdayLabel(_ row: Int) -> String {
        switch row {
        case 0: return L10n.pick("M", "一")
        case 2: return L10n.pick("W", "三")
        case 4: return L10n.pick("F", "五")
        default: return ""
        }
    }

    private func dayHelp(date: Date, count: Int) -> String {
        let value = date.formatted(date: .long, time: .omitted)
        return L10n.pick("\(value) · \(count) commits", "\(value) · \(count) 次提交")
    }
}

struct GitActivityLegend: View {
    private let levels = [0.045, 0.22, 0.42, 0.64, 0.90]

    var body: some View {
        HStack(spacing: 3) {
            Text(L10n.pick("Less", "少"))
            ForEach(Array(levels.enumerated()), id: \.offset) { index, opacity in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(index == 0 ? Color.primary.opacity(opacity)
                                     : Color.accentColor.opacity(opacity))
                    .frame(width: 8, height: 8)
            }
            Text(L10n.pick("More", "多"))
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.pick("Commit activity from less to more", "提交活跃度从少到多"))
    }
}
