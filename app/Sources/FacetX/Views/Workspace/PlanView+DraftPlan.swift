import FacetXCore
import SwiftUI

extension PlanView {
    func draftPlanWithAI() {
        showAssistantPanel.wrappedValue = true
        let prompt = aiDraftPlanPrompt()
        let mentions = aiDraftPlanMentions()
        assistant.send(
            prompt,
            mentions: mentions,
            displayText: L10n.pick("Draft this week's plan.", "帮我起草本周计划。")
        )
    }

    private func aiDraftPlanPrompt() -> String {
        """
        Draft a weekly plan for this FacetX project using the context below.

        Important rules:
        - Do not create, update, delete, complete, or move any item in this turn.
        - Do not call mutation tools in this turn. Read-only tools are allowed only if the context is insufficient.
        - Return a concrete draft grouped by day.
        - For each proposed move, include the item's reference_id and the target day/time.
        - Explain overload risks briefly using the day_load values.
        - Ask for confirmation before applying changes.

        <facetx_week_plan_context>
        \(aiDraftPlanContextJSON())
        </facetx_week_plan_context>
        """
    }

    private func aiDraftPlanContextJSON() -> String {
        let object: [String: Any] = [
            "project": [
                "name": project.name,
                "prefix": project.prefix,
            ],
            "week": [
                "id": week.id,
                "range": weekRangeLabel,
                "start": isoDate(week.startDate),
                "end": isoDate(week.endDate),
            ],
            "goal": [
                "title": goal?.title ?? "",
                "body": goal?.body ?? "",
            ],
            "unscheduled_tasks": aiUnscheduledTasks.map(aiItemObject),
            "days": aiDayObjects(),
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private var aiUnscheduledTasks: [ProjectItem] {
        allItems.filter { item in
            item.kind == .reminder
                && item.facetKind == .task
                && item.date == nil
                && !item.isCompleted
        }
    }

    private func aiDayObjects() -> [[String: Any]] {
        let calendar = Calendar(identifier: .iso8601)
        return (0..<7).compactMap { offset -> [String: Any]? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: week.startDate) else {
                return nil
            }
            let dayItems = weekReviewItems.filter { item in
                guard let itemDate = item.date else { return false }
                return calendar.isDate(itemDate, inSameDayAs: date)
            }
            let activeItems = dayItems.filter { !$0.isCompleted }
            let load = PlanDayLoad.measure(activeItems, calendar: calendar)
            return [
                "date": isoDate(date),
                "day_load": [
                    "level": load.level.title,
                    "scheduled_time": load.hoursLabel,
                    "task_count": load.taskCount,
                    "high_priority_count": load.highPriorityCount,
                ],
                "items": activeItems.map(aiItemObject),
            ]
        }
    }

    private func aiItemObject(_ item: ProjectItem) -> [String: Any] {
        let mention = AssistantItemMention(item: item)
        var object = mention.promptObject
        object["facet_kind"] = item.facetKind.rawValue
        object["pinned"] = item.isPinned
        object["overdue"] = item.isOverdue
        return object
    }

    private func aiDraftPlanMentions() -> [AssistantItemMention] {
        var seen = Set<String>()
        let relevant = aiUnscheduledTasks + weekReviewItems.filter { !$0.isCompleted }
        return relevant.compactMap { item in
            let mention = AssistantItemMention(item: item)
            guard seen.insert(mention.referenceID).inserted else { return nil }
            return mention
        }
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
