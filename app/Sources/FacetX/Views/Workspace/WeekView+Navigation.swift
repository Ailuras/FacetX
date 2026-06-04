import FacetXCore
import SwiftUI

extension WeekView {
    var weekNav: some View {
        HStack(spacing: 12) {
            weekNavCluster

            Spacer()

            if hasActiveSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(weekItems.count) results")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
            }
        }
        .frame(minHeight: 30, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FacetTheme.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FacetTheme.hairline).frame(height: 1)
        }
        .overlay(alignment: .center) {
            VStack(spacing: 2) {
                Text("Week \(week.week)")
                    .font(.system(size: 13, weight: .semibold))
                Text(weekRangeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    var weekRangeLabel: String {
        let start = week.startDate
        let end = Calendar(identifier: .iso8601).date(byAdding: .day, value: 6, to: start) ?? start
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = Calendar.current.isDate(start, equalTo: end, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "MMM d, yyyy"
        return "\(startFormatter.string(from: start)) - \(endFormatter.string(from: end))"
    }

    private var weekNavCluster: some View {
        HStack(spacing: 2) {
            pillIconButton(systemName: "chevron.left", help: "Previous week") {
                week = week.shifted(by: -1)
            }
            pillIconButton(systemName: "chevron.right", help: "Next week") {
                week = week.shifted(by: 1)
            }
            pillTextButton("Current", help: "Go to current week") {
                week = ISOWeek.containing(Date())
            }
        }
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

    private func pillIconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func pillTextButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: 24)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
