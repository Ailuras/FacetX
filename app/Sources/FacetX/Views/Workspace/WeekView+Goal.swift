import FacetXCore
import SwiftUI

extension WeekView {
    @ViewBuilder var goalSection: some View {
        if editingGoal {
            VStack(alignment: .leading, spacing: 10) {
                goalEyebrow("This Week's Focus", systemImage: "target")
                TextField("This week I'm focused on...", text: $goalTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(FacetTheme.panel.opacity(0.70))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
                TextField("Details and constraints...", text: $goalBody, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(2...4)
                    .padding(10)
                    .background(FacetTheme.panel.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(FacetTheme.hairline, lineWidth: 1)
                    )
                if let goalError {
                    Text(goalError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Save") {
                        Task { await saveGoal() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(savingGoal)
                    if savingGoal { ProgressView().scaleEffect(0.7) }
                    Button("Cancel") { editingGoal = false }
                        .disabled(savingGoal)
                }
                .controlSize(.small)
            }
            .goalCard(accented: true)
        } else if let goal {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    goalEyebrow("This Week's Focus", systemImage: "target")
                    Spacer()
                    Button("Edit") { startEditingGoal() }
                        .font(.caption)
                        .help("Edit weekly goal")
                }
                Text(goal.title)
                    .font(.system(size: 20, weight: .bold))
                if !goal.body.isEmpty {
                    Text(goal.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .goalCard(accented: true)
        } else {
            Button { startEditingGoal() } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.13))
                        Image(systemName: "target")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Set this week's focus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Pick one outcome to keep this project's week anchored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .help("Set this week's project goal")
            .frame(maxWidth: .infinity, alignment: .leading)
            .goalCard(accented: false)
        }
    }

    func goalEyebrow(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
    }

    func startEditingGoal() {
        goalTitle = goal?.title ?? ""
        goalBody = goal?.body ?? ""
        goalError = nil
        editingGoal = true
    }

    func saveGoal() async {
        guard !savingGoal else { return }
        savingGoal = true
        goalError = nil
        defer { savingGoal = false }

        let trimmed = goalTitle.trimmingCharacters(in: .whitespaces)
        let currentWeek = week

        if trimmed.isEmpty {
            if let eventId = goal?.eventId {
                let deleted = await ek.deleteGoalEvent(eventId: eventId)
                guard deleted else {
                    goalError = "Could not delete the schedule item. Check Calendar access."
                    return
                }
            }
            store.setWeekGoal(projectID: project.id, weekId: currentWeek.id, title: "", body: "")
        } else {
            let eventId = await ek.createOrUpdateGoalEvent(
                project: project.prefix,
                title: trimmed,
                body: goalBody,
                week: currentWeek,
                calendarName: goalCalendarName,
                existingEventId: goal?.eventId,
                enabledCalendars: settings.effectiveCalendarNames
            )
            guard let eventId else {
                goalError = "Could not save the schedule item. Check Calendar access and enabled calendars."
                return
            }
            store.setWeekGoal(
                projectID: project.id,
                weekId: currentWeek.id,
                title: goalTitle,
                body: goalBody,
                eventId: eventId
            )
        }

        editingGoal = false
        await reload()
    }

    var goalCalendarName: String? {
        if let name = project.weekGoalCalendarName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if !settings.weekGoalCalendarName.isEmpty { return settings.weekGoalCalendarName }
        if !settings.defaultCalendarName.isEmpty { return settings.defaultCalendarName }
        return project.calendarName.nonEmpty
    }
}
