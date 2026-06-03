# FacetX Architecture

FacetX is a native macOS SwiftUI app that layers projects over Apple Calendar
and Reminders without owning item content. EventKit remains the source of truth;
FacetX persists only project metadata that EventKit cannot represent.

## Core Contract

An item belongs to a project when its title starts with `ProjectName:`.
All parsing and composition must go through `ProjectPrefix`.

- Reads accept ASCII `:` and fullwidth `：`.
- Writes always use ASCII `:`.
- Prefix matching uses the first line only.
- Items without a recognized prefix are ignored and never modified.

`FacetAssociation` is the unified classifier for regular project items, week
goal events, and unrelated EventKit items. Week goal events must not leak into
ordinary item lists.

## Runtime Objects

`FacetXApp` creates and injects three environment objects:

- `EventKitService`: the only EventKit boundary; handles auth, fetch, writes,
  container CRUD, prefix filtering, and live change notifications.
- `ProjectStore`: project-side JSON metadata under Application Support. It
  does not store reminder or calendar content.
- `AppSettings`: app-wide container filters and default save targets.

Application Support paths come from `AppSupport`. Canonical builds use
`~/Library/Application Support/FacetX`; branch variants use the support name
written into the app bundle Info.plist.

## Persistence

Project metadata:

```text
Project
  id
  name
  prefix
  tagline
  reminderListName
  calendarName
  weekGoalCalendarName
  createdAt
  archived
  weekGoals
  itemOrder
  sortOrder
  githubRepo

WeekGoal
  id
  weekId
  title
  body
  eventId
```

JSON writes are atomic and use `[.prettyPrinted, .sortedKeys]`.

## EventKit Concurrency

`EventKitService` is intentionally not `@MainActor`.
`EKEventStore`, `EKReminder`, and `EKEvent` are not `Sendable`, and EventKit
reminder callbacks arrive on a background queue. Flatten EventKit objects into
the Sendable `ProjectItem` value type inside the callback before crossing any
actor boundary. Only published auth flags should hop back through
`MainActor.run`.

## Containers

Containers are keyed by title, not identifier. Calendar/list identifiers are
device-local; titles are stable across the user's devices. Empty enabled sets
mean all containers. Save-target selection should use
`AppSettings.reminderSaveTarget` and `AppSettings.calendarSaveTarget`.

## Source Layout

`app/Sources/FacetXCore` contains pure shared logic only. It must not depend on
SwiftUI or EventKit.

`app/Sources/FacetX` is grouped by app boundary:

- `App`
- `Services`
- `Stores`
- `Views`
- `UI`
- `Utilities`
