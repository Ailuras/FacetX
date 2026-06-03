# FacetX

FacetX is a native macOS project lens for Apple Calendar and Reminders.

Your tasks and events still live in Apple's apps and sync through iCloud.
FacetX adds the missing project dimension by gathering calendar and reminder
items whose titles begin with a project prefix, then presenting them as one
project workspace.

## Highlights

- Project workspace for calendar events and reminders in one panel.
- Cross-project Today view.
- Per-project week planning with synced calendar-backed goals.
- Menu bar quick capture for project-prefixed reminders.
- EventKit-first data model with no separate task database.

## Build And Run

```bash
make run      # debug rebuild, codesign, stop the current app, relaunch
make build    # release bundle build
make check    # SwiftPM debug build + FacetXCoreChecks
make dmg      # package app/FacetX-<version>.dmg
make clean    # remove local build and packaging artifacts
make logs     # stream FacetX OS logs
```

FacetX must run as a bundled, signed `.app`; a bare SwiftPM binary is denied
EventKit access by macOS.

Development rebuilds reuse Calendar and Reminders authorization when the bundle
ID and signing identity stay stable. Branch and worktree variants use separate
bundle IDs, so each variant needs Calendar and Reminders authorization once.
If macOS asks for the login keychain password while building, that is `codesign`
requesting access to the local Apple Development private key; choose Always
Allow for `codesign` to avoid repeated build-time prompts.

## Project Prefixes

A project owns items by title prefix:

```text
Regulus: 问题最小化&修复bugs      ->  project "Regulus"
调研: 机器学习+运筹优化            ->  ignored unless a matching project exists
```

Items without a recognized project prefix are ignored and never modified.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Building](docs/BUILDING.md)
- [Release](docs/RELEASE.md)
- [Agent guide](AGENTS.md)

## Status

Native SwiftUI app, v0.3 local beta. The current app includes project
creation/editing, grouped item views, Today and month views, menu bar quick
capture, EventKit live refresh, Settings container selection, week goals, and
GitHub commit integration.
