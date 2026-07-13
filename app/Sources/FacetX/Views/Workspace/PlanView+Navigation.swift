import FacetXCore
import SwiftUI

extension PlanView {
    var planNav: some View {
        PeriodNavigationBar(
            title: L10n.t(.modePlan),
            subtitle: "\(planMonth.label) · \(weekShortLabel)",
            previousHelp: L10n.t(.prevWeek),
            nextHelp: L10n.t(.nextWeek),
            currentHelp: L10n.t(.currentWeek),
            onPrevious: { week = week.shifted(by: -1) },
            onNext: { week = week.shifted(by: 1) },
            onCurrent: { week = ISOWeek.containing(Date()) },
            leading: {
                summaryCluster
            },
            accessory: {
                HStack(spacing: 8) {
                    if hasActiveSearch {
                        FacetInfoBadge(
                            text: "\(weekItems.count) \(L10n.t(.resultsUnit))",
                            systemImage: "magnifyingglass",
                            tint: .secondary,
                            fill: Color.accentColor.opacity(0.08)
                        )
                    }
                    if !showCompleted && hiddenReminderCount > 0 {
                        FacetInfoBadge(
                            text: "\(hiddenReminderCount) \(L10n.t(.hiddenUnit))",
                            systemImage: "eye.slash",
                            tint: .secondary,
                            fill: Color.orange.opacity(0.08)
                        )
                    }
                    if !tagFilter.isEmpty {
                        ActiveTagFilterBar(tagFilter: $tagFilter)
                    }
                    if itemFilter.isActive {
                        FacetInfoBadge(
                            text: "\(weekItems.count) \(L10n.t(.shownUnit))",
                            systemImage: "line.3.horizontal.decrease.circle",
                            tint: .secondary,
                            fill: Color.accentColor.opacity(0.08)
                        )
                    }
                    Button {
                        showingReview = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                            .contentShape(Rectangle())
                            .facetHoverSurface(tint: .secondary,
                                               fill: Color.primary.opacity(0.04),
                                               hoverFill: Color.primary.opacity(0.07),
                                               hoverStroke: FacetTheme.hairline)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.pick("Review this week", "回顾本周"))
                    Button {
                        draftPlanWithAI()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: FacetTheme.chipHeight, height: FacetTheme.chipHeight)
                            .contentShape(Rectangle())
                            .facetHoverSurface(tint: Color.accentColor,
                                               fill: Color.accentColor.opacity(assistant.isBusy ? 0.04 : 0.12),
                                               hoverFill: Color.accentColor.opacity(0.18),
                                               stroke: assistant.isBusy ? Color.clear : Color.accentColor.opacity(0.18),
                                               hoverStroke: Color.accentColor.opacity(0.36))
                    }
                    .buttonStyle(.plain)
                    .disabled(assistant.isBusy)
                    .help(L10n.pick("Draft this week's plan with AI", "用 AI 起草本周计划"))
                    PlanSortMenu(selection: $sortOption, onSelect: setSortOption)
                    ItemActionCluster(itemFilter: $itemFilter, showCompleted: $showCompleted, animation: listAnimation) {
                        onCreateItem(week.startDate)
                    }
                }
            }
        )
    }

    private var summaryCluster: some View {
        HStack(spacing: 6) {
            SummaryChip(
                value: weekBaseItems.count,
                label: L10n.pick("All", "全部"),
                systemImage: "square.grid.2x2",
                isActive: itemFilter.kindScope == .all,
                help: L10n.pick("Show all items", "显示全部条目"),
                onTap: {
                    withAnimation(listAnimation) {
                        itemFilter.kindScope = .all
                    }
                }
            )
            SummaryChip(
                value: weekBaseItems.filter { $0.kind == .reminder }.count,
                label: L10n.pick("Tasks", "任务"),
                systemImage: ProjectItem.Kind.reminder.systemImage,
                tint: ProjectItem.Kind.reminder.color,
                isActive: itemFilter.kindScope == .tasks,
                help: L10n.pick("Show only tasks", "仅显示任务"),
                onTap: {
                    withAnimation(listAnimation) {
                        itemFilter.kindScope = (itemFilter.kindScope == .tasks) ? .all : .tasks
                    }
                }
            )
            SummaryChip(
                value: weekBaseItems.filter { $0.kind == .event }.count,
                label: L10n.pick("Events", "事件"),
                systemImage: ProjectItem.Kind.event.systemImage,
                tint: ProjectItem.Kind.event.color,
                isActive: itemFilter.kindScope == .events,
                help: L10n.pick("Show only events", "仅显示事件"),
                onTap: {
                    withAnimation(listAnimation) {
                        itemFilter.kindScope = (itemFilter.kindScope == .events) ? .all : .events
                    }
                }
            )
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

    var weekShortLabel: String {
        L10n.language == "zh" ? "第 \(week.week) 周" : "Week \(week.week)"
    }
}
