# FacetX Architecture

FacetX is a native macOS SwiftUI app that layers projects over Apple Calendar
and Reminders without owning item content. EventKit remains the source of truth;
FacetX persists only project metadata that EventKit cannot represent.

Task and event items are the primary work atoms. Projects group them by prefix;
papers, commits, and long-form work notes attach to an item rather than to the
project.

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

Item work notes:

```text
item-notes.db
  item_notes
    id
    body
    created_at
    updated_at
```

Reminder and calendar notes hold only FacetX metadata for normal project items.
The user-facing work note body lives in the local item note database and is
referenced by `note-id`.

Canonical item metadata:

```text
FacetX-Metadata-Begin
commits: owner/repo@sha,...
facetx-kind: item-v1
item-id: stable-facetx-item-uuid
note-id: local-note-uuid
papers: paper-id,...
tags: tag, tag
FacetX-Metadata-End
```

The `item-id` is the stable FacetX identity for the task/event. It is preserved
when a reminder is converted to a calendar event or vice versa. The EventKit
`calendarItemIdentifier` can change after conversion or sync, so durable links
must use metadata carried inside the item notes, not the EventKit identifier
alone.

FacetX does not maintain a separate link table for item relationships. Linked
paper ids and commit ids are stored in the item metadata. This keeps task/event
links portable with the EventKit item and avoids a second source of truth for
relationships.

If an existing item has plain notes or an incomplete metadata block, the item
detail pane offers a rebuild action. Rebuild absorbs the old user-facing notes
into `item-notes.db`, then rewrites the EventKit notes field as canonical
metadata.

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
