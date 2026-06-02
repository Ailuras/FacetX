# AGENTS.md

This file provides guidance to Codex agents when working with code in this repository.

## What this is

A native macOS (SwiftUI, macOS 14+) app that layers a **project** dimension over
the user's existing Apple Calendar and Reminders. FacetX stores no item content
of its own — items live in EventKit (synced via iCloud, visible in Apple's apps).
It is a *lens* that gathers the subset of calendar/reminder items belonging to a
project and presents them in one panel (each project = a *facet* of the same
data).

Current status: v0.3 local beta. Implemented: project creation/editing in the
main window, prefix-based aggregation, grouped item view, cross-project Today
view, project search and header controls, complete/create/delete, modern detail
editing, completed-item filtering with soft list transitions, per-project week
view + goal, menu bar quick-capture, live refresh on EventKit changes, container
selection + creation, and a standard Settings window for app-wide container
configuration.

Founding intent: Apple's Calendar and Reminders organize data flatly by calendar
or list. FacetX supplies the missing project aggregation dimension without
owning or mirroring the underlying item content.

App Swift source lives under [app/Sources/FacetX/](app/Sources/FacetX/).
Shared pure logic lives under [app/Sources/FacetXCore/](app/Sources/FacetXCore/),
with lightweight executable checks in [app/Checks/FacetXCoreChecks/](app/Checks/FacetXCoreChecks/).

## Build & run

The app **must run as a bundled, code-signed .app** — a bare SwiftPM binary is
silently denied EventKit access by macOS. Never `swift run`; always build the
bundle:

```bash
scripts/build.sh          # release (default), branch-aware bundle build
scripts/build.sh debug    # debug build
scripts/restart.sh        # debug stop→build→open -n development loop
cd app
./make-dmg.sh             # package FacetX.app into a distributable .dmg
```

`app/build-app.sh` runs `swift build`, wraps the binary into a `.app` bundle with
[Info.plist](app/Info.plist) (EventKit usage strings) +
[FacetX.entitlements](app/FacetX.entitlements), patches branch-specific bundle
metadata, then code-signs it. It prefers `FACETX_SIGN_IDENTITY`, then the first
local `Apple Development` signing identity, and falls back to ad-hoc signing.
For a quick non-UI regression pass, run:

```bash
cd app
swift build -c debug
swift run FacetXCoreChecks
```

EventKit permission state is granted per-bundle by macOS (TCC). `main`/`master`
builds the canonical `FacetX.app` with bundle ID `com.facetx.app`. Other branches
build variants such as `FacetX-feat-calendar.app` with bundle ID
`com.facetx.app.dev.feat-calendar`; each variant has its own support directory
(`Application Support/FacetX-feat-calendar/`) and must be authorized once. Keep
the bundle ID and signing identity stable to reuse that authorization across
rebuilds. Ad-hoc fallback signing may cause macOS to ask again.

### Signing identity for single authorization

To avoid repeated Calendar/Reminders prompts during development, use a stable
local code-signing identity instead of relying on ad-hoc signing. First inspect
available identities:

```bash
security find-identity -v -p codesigning
```

Use the full quoted `Apple Development: ...` identity shown by that command:

```bash
FACETX_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/restart.sh
```

For persistent local use, export it from the shell before building, or add it to
your private shell profile (do not commit machine-specific identities):

```bash
export FACETX_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
scripts/restart.sh
```

Agents should not hard-code a developer identity in repo files. If no identity is
configured, `app/build-app.sh` automatically tries the first local
`Apple Development` identity and then falls back to ad-hoc signing. When the
build output says `signing: ad-hoc`, tell the user that TCC may prompt again.

TCC authorization is still per bundle ID. Each worktree/variant should be opened
and authorized once, then reused with the same variant and signing identity.

Variant build overrides:

```bash
FACETX_VARIANT=myfork scripts/restart.sh
FACETX_SIGN_IDENTITY="Apple Development: Your Name" scripts/restart.sh
FACETX_APP_NAME=FacetX-local FACETX_BUNDLE_ID=com.facetx.app.dev.local scripts/build.sh debug
```

## The core contract (do not break)

An item belongs to a project when its **title starts with `ProjectName:`**. This
is the only association mechanism because EventKit exposes no tag API. All of
[ProjectPrefix.swift](app/Sources/FacetXCore/ProjectPrefix.swift) encodes it:

- **Colon-tolerant on read, ASCII on write.** Accept both ASCII `:` and fullwidth
  `：` when parsing (real calendar data uses `：`); always compose new titles with
  ASCII `:` via `ProjectPrefix.makeTitle`.
- **First-line only.** Real reminder titles contain newlines — the prefix parser
  considers only the first line.
- **Subset semantics.** Items without a recognized prefix are ignored and never
  modified. Daily-life reminders must stay untouched. The app only ever writes
  items it composed with a project prefix.

Always go through `ProjectPrefix` for parsing/composing — never hand-roll prefix
string handling elsewhere.

## Architecture

Three `ObservableObject`s are created in
[FacetXApp.swift](app/Sources/FacetX/FacetXApp.swift) and injected as
environment objects into all three scenes (main `WindowGroup`, `MenuBarExtra`
quick-capture, and the standard `SwiftUI.Settings` window):

- **[EventKitService.swift](app/Sources/FacetX/EventKitService.swift)** — wraps
  `EKEventStore`: auth, fetch, prefix-filter, write-back, container CRUD. This is
  the only file that touches EventKit.
- **`ProjectStore`** ([Models.swift](app/Sources/FacetX/Models.swift)) —
  `@MainActor`; persists saved projects + week goals as JSON under Application
  Support (`FacetX/projects.json`, or the active variant directory). Holds *only* project-side metadata EventKit
  can't represent (name, claimed prefix, tagline, default reminder/calendar
  save locations, week goals, and optional local item presentation order).
  **No item content is stored here** — that's what avoids any two-source sync
  problem.
- **[AppSettings.swift](app/Sources/FacetX/AppSettings.swift)** — `@MainActor`;
  persists which containers are enabled plus the default reminder/calendar save
  locations for new projects (`FacetX/settings.json`, or the active variant directory).

Both JSON stores resolve their directory through
[AppSupport.swift](app/Sources/FacetX/AppSupport.swift). The default is
`Application Support/FacetX/`; development variants read
`FacetXApplicationSupportName` from Info.plist so worktrees do not share local
JSON state.

Project-side persisted shape:

```text
Project
  id                 UUID
  name               String
  prefix             String
  tagline            String
  reminderListName   String?
  calendarName       String?
  createdAt          Date
  archived           Bool
  itemOrder          [String]?
  githubRepo         String?

WeekGoal
  id                 UUID
  weekId             String   // ISO "2026-W22"
  title              String
  body               String
  eventId            String?
```

Items are intentionally absent from this store. They are fetched from EventKit on
demand and matched by the project prefix.

Scene/view split is deliberate: project creation/editing lives in the main
window next to the project list, the menu bar is for reminder quick capture, and
**Settings only holds app-wide container configuration**
([SettingsScene.swift](app/Sources/FacetX/SettingsScene.swift): choose/create
containers). Note the `SwiftUI.Settings` scene must be fully qualified because
our own `ProjectStore`/config naming would otherwise shadow it.

### Concurrency: EventKitService is NOT @MainActor

This is the most error-prone area. `EventKitService` is `nonisolated` and
`@unchecked Sendable` on purpose:

- EventKit's `fetchReminders` callback fires on its own background queue, and
  `EKEventStore`/`EKReminder` are not `Sendable`. A `@MainActor` wrapper triggers
  Swift 6 main-actor isolation assertions (`dispatch_assert_queue_fail` → SIGTRAP)
  — this actually crashed an earlier build.
- **Flatten non-Sendable EKReminder/EKEvent into the Sendable `ProjectItem`
  struct *inside* the EventKit callback** — never let an `EKReminder` cross an
  actor hop. See `reminders(forProject:)` and `fetchReminderProjectNames`.
- Only the `@Published` auth flags are written back via `MainActor.run`.

If you add EventKit calls, preserve this pattern: stay off the main actor, and
map to value types before returning.

### Live refresh

`EventKitService` observes `.EKEventStoreChanged` and bumps `changeToken`. Views
watch it with `.onChange(of: ek.changeToken) { Task { await reload() } }` so the
UI updates when data changes in Apple's apps or via iCloud.

### Containers keyed by title, not identifier

`AppSettings.enabledContainerNames` and all container lookups use the container
**title**, not `calendarIdentifier` — identifiers are device-local (the same
iCloud calendar has a different id per Mac) while titles are stable across
devices/accounts. An **empty** enabled-set means "all containers" (fresh-install
default). `AppSettings.toggle` materializes "all" into an explicit set before the
first removal so unchecking one doesn't re-enable everything.

## Conventions

- Reads/writes are scoped to enabled containers everywhere via the
  `enabled: Set<String>?` parameter (empty/nil = all). When adding fetch/create
  paths, thread `settings.enabledContainerNames` through.
- New item creation writes to the project's saved reminder list / calendar.
  Settings owns only the defaults used when a project is created or when older
  project data has no saved container yet.
- Week identity is ISO-8601, Monday-start, formatted `"2026-W22"` — use
  [ISOWeek.swift](app/Sources/FacetXCore/ISOWeek.swift), don't reimplement week math.
- JSON stores write atomically with `[.prettyPrinted, .sortedKeys]`.
- Keep the dependency surface at zero: pure SwiftPM + system frameworks only
  (this keeps the Command Line Tools build working — no Xcode project required).
- Out of scope for now: Apple Notes integration (no public API; AppleScript
  only) and the retired web/Python implementation.
