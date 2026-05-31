# FacetX

FacetX is a **native macOS project lens** for your existing Apple Calendar and
Reminders.

Your tasks and events already live in Reminders and Calendar (synced via iCloud,
visible in Apple's own apps). Those apps organize them flatly — by list, by
calendar — with no notion of a *project*. FacetX adds that missing dimension:
create a project, and FacetX gathers the subset of your calendar/reminder
items that belong to it into one panel — each project is a *facet* of the same
underlying data.

## Highlights

- **Project workspace**: Manage projects in the main window and review each
  project's reminders and calendar events together.
- **Today view**: See all project items dated today in one cross-project list.
- **Week planning**: Switch a project into a weekly view with an ISO-week goal
  and dated items for the selected week.
- **Quick capture**: Add project-prefixed items from the menu bar without
  opening the main window.
- **Native data model**: FacetX reads and writes Apple Calendar/Reminders data
  through EventKit instead of keeping a separate task database.

## How items map to projects

A project owns items by a **title prefix**:

```
Regulus: 问题最小化&修复bugs      →  project "Regulus"
调研: 机器学习+运筹优化            →  ignored (no matching project)
```

Items without a recognized project prefix are never touched — your day-to-day
reminders stay exactly as they are. (EventKit exposes no tag API, so a title
prefix is the only reliable association mechanism — see `CLAUDE.md`.)

## Build & run

```bash
cd app
./build-app.sh            # compile + bundle + ad-hoc sign FacetX.app
open ./FacetX.app
```

The app must run as a bundled, signed `.app` — a bare binary is denied EventKit
access by macOS. See [CLAUDE.md](CLAUDE.md) for architecture notes.

To create a distributable disk image:

```bash
cd app
./build-app.sh
./make-dmg.sh
```

The DMG contains `FacetX.app` and an `/Applications` shortcut. The app is
ad-hoc signed rather than notarized, so a first launch on another Mac may need
right-click > Open.

## Checks

```bash
cd app
swift build -c debug
swift run FacetXCoreChecks
```

## Status

Native SwiftUI app (v0.3, local beta). The app includes a polished three-pane
workspace, cross-project Today view, project search and controls, modern detail
and settings surfaces, menu bar quick capture, project-specific week planning,
completed-item controls, and lightweight core checks. See
**[RELEASE_NOTES.md](RELEASE_NOTES.md)** for the latest release notes and
**[CLAUDE.md](CLAUDE.md)** for architecture and maintenance notes.

## Layout

- `CLAUDE.md` — repository guide for future coding agents
- `RELEASE_NOTES.md` — current release notes in English and Chinese
- `app/` — the SwiftUI app (sources, checks, build scripts)
