import FacetXCore
import SwiftUI

extension WeekView {
    func syncGoalWithCalendar(for currentWeek: ISOWeek) async {
        guard ek.calendarAuthorized,
              !ek.calendarNames(enabled: settings.effectiveCalendarNames).isEmpty else { return }

        let localGoal = store.weekGoal(projectID: project.id, weekId: currentWeek.id)
        let snapshot = await ek.weekGoalEvent(project: project.prefix,
                                               week: currentWeek,
                                               existingEventId: localGoal?.eventId,
                                               enabledCalendars: settings.effectiveCalendarNames)
        guard !Task.isCancelled, currentWeek == week else { return }

        if let snapshot {
            if localGoal?.title != snapshot.title
                || localGoal?.body != snapshot.body
                || localGoal?.eventId != snapshot.eventId {
                store.setWeekGoal(projectID: project.id, weekId: currentWeek.id,
                                  title: snapshot.title, body: snapshot.body,
                                  eventId: snapshot.eventId)
            }
        } else if localGoal?.eventId != nil {
            store.setWeekGoal(projectID: project.id, weekId: currentWeek.id, title: "", body: "")
        }
    }

    func reload() async {
        let requestedWeek = week
        loading = allItems.isEmpty
        let fetched = await ek.items(forProject: project.prefix,
                                     enabledReminderLists: settings.effectiveReminderListNames,
                                     enabledCalendars: settings.effectiveCalendarNames)
        let sortedItems = ItemArrangement.arranged(fetched, savedOrder: project.itemOrder)
        store.reportTags(projectID: project.id, items: sortedItems)
        await syncGoalWithCalendar(for: requestedWeek)
        guard !Task.isCancelled, requestedWeek == week else { return }
        if allItems.isEmpty {
            allItems = sortedItems
        } else {
            withAnimation(listAnimation) {
                allItems = sortedItems
            }
        }
        loading = false
    }
}
