# DocsBot

A **native macOS app** that gives a **project-oriented view** over your existing
Apple Calendar and Reminders.

Your tasks and events already live in Reminders and Calendar (synced via iCloud,
visible in Apple's own apps). Those apps organize them flatly — by list, by
calendar — with no notion of a *project*. DocsBot adds that missing dimension:
declare a project, and DocsBot gathers the subset of your calendar/reminder
items that belong to it into one panel.

## How items map to projects

A project owns items by a **title prefix**:

```
Regulus: 问题最小化&修复bugs      →  project "Regulus"
调研: 机器学习+运筹优化            →  ignored (no declared project)
```

Items without a recognized project prefix are never touched — your day-to-day
reminders stay exactly as they are. (EventKit exposes no tag API, so a title
prefix is the only reliable association mechanism — see `REBUILD.md`.)

## Status

Being rebuilt from scratch as a native SwiftUI app. See **[REBUILD.md](REBUILD.md)**
for the design. The previous Python/web version is archived under
[`legacy/`](legacy/).

## Layout

- `REBUILD.md` — v2 design / blueprint
- `experiments/` — EventKit probes used to validate the approach
- `legacy/` — frozen v1 (Python + web + SQLite + MCP + CLI)
