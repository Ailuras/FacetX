# FacetX Architecture

FacetX is a native macOS SwiftUI app that layers projects over Apple Calendar
and Reminders without owning item content. EventKit remains the source of truth;
FacetX persists only project metadata that EventKit cannot represent.

Task and event items are the primary work atoms. Projects group them by prefix;
literature, commits, and repository documents attach to an item rather than to the
project.

## Project Workspaces

Each project exposes four focused workspace modes:

- **All** manages Todo and Event work items.
- **Plan** schedules and reviews those work items.
- **Git** summarizes the bound repository's branch, working changes, commits,
  and commit-to-item progress.
- **Notes** reads and edits `README.md` plus top-level `.facetx/*.md` documents.

Notes are repository documents, not work items. The Notes workspace provides
read, write, and split Markdown modes while attachments continue to use
`item_documents` under the stable Todo/Event `item-id`.

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

Local work-item state:

```text
item-notes.db
  items(id, note_body, tags_json, is_completed, is_pinned)
  item_papers(item_id, paper_id)
  item_commits(item_id, commit_id)
  item_documents(item_id, document_path)
```

Reminder and calendar notes hold only a stable `item-id` (UUID) for normal project items.
The user-facing details, tags, and resource relationships live in the local `ItemStore` SQLite database under the `item-id` key.

Canonical item identity in EventKit notes:

```text
stable-facetx-item-uuid
```

The `item-id` is the stable FacetX identity for the task/event. It is preserved
when a reminder is converted to a calendar event or vice versa. The EventKit
`calendarItemIdentifier` can change after conversion or sync, so durable links
must use the UUID carried inside the item notes, not the EventKit identifier
alone.

FacetX maintains relationship and work-item detail tables inside a local SQLite database (`item-notes.db` managed by `ItemStore`):
- `items` maps `id` to `note_body` and `tags_json`.
- `item_papers` maps `item_id` to `paper_id`.
- `item_commits` maps `item_id` to `commit_id`.
- `item_documents` maps `item_id` to `README.md` or a top-level `.facetx/*.md` path.

This avoids polluting EventKit notes with serialized CSV arrays of relationships (commits, literature papers) and makes filtering, querying, and relationship cleanups robust.

Current items write stable UUID references when they are created or first edited.

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
