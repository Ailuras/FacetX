import FacetXCore
import SwiftUI

extension PlanView {
    func syncGoalWithCalendar(for currentWeek: ISOWeek) async {
        guard ek.calendarAuthorized,
              !ek.calendarNames(enabled: settings.effectiveCalendarNames).isEmpty else { return }

        let localGoal = store.weekGoal(workID: work.id, weekId: currentWeek.id)
        let snapshot = await ek.weekGoalEvent(work: work.prefix,
                                               week: currentWeek,
                                               existingEventId: localGoal?.eventId,
                                               enabledCalendars: settings.effectiveCalendarNames)
        guard !Task.isCancelled, currentWeek == week else { return }

        if let snapshot {
            if localGoal?.title != snapshot.title
                || localGoal?.body != snapshot.body
                || localGoal?.eventId != snapshot.eventId {
                store.setWeekGoal(workID: work.id, weekId: currentWeek.id,
                                  title: snapshot.title, body: snapshot.body,
                                  eventId: snapshot.eventId)
            }
        } else if localGoal?.eventId != nil {
            store.setWeekGoal(workID: work.id, weekId: currentWeek.id, title: "", body: "")
        }
    }

    func reload() async {
        let requestedWeek = week
        let requestedMonth = planMonth
        loading = allItems.isEmpty
        let fetched = await ek.items(forWork: work.prefix,
                                     enabledReminderLists: settings.effectiveReminderListNames,
                                     enabledCalendars: settings.effectiveCalendarNames,
                                     eventStartDate: planEventStartDate,
                                     eventEndDate: planEventEndDate)
        let tieOrder = allItems.isEmpty ? currentManualOrder : allItems.map(\.id)
        let sortedItems = sortedItems(
            fetched,
            savedOrder: sortOption == .manual ? currentManualOrder : tieOrder
        )
        store.reportTags(workID: work.id, items: sortedItems)
        await syncGoalWithCalendar(for: requestedWeek)
        guard !Task.isCancelled, requestedWeek == week, requestedMonth == planMonth else { return }
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
