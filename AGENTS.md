# AGENTS.md

Guidance for AI coding agents working in this repository.

## Default Rule: No Backward Compatibility

FacetX is current-only unless the user explicitly asks for compatibility.
When changing behavior, data shapes, scripts, or docs, delete old logic, old
fields, old paths, and compatibility bridges instead of preserving legacy
entrypoints. Do not keep wrappers, aliases, migration shims, or fallback paths
for removed interfaces unless the user specifically requests them.

Applies to everything: Swift types, JSON keys, file paths, script flags,
build targets, and AppKit/SwiftUI APIs. If the old interface is gone,
remove it completely—no `// removed`, no re-export, no conditional shim.

## Workflow: Commit and Restart After Every Functional Change

After implementing a complete functional unit (feature, fix, or refactor), you
must do **both** of the following before handing off to the user:

1. **Commit** — one commit per functional unit, following the
   [Commit Style](#commit-style) rules below. Each commit must compile and pass
   checks.
2. **Restart the app** — run `make run` so the change is live and ready to
   verify. Never leave a change committed-but-not-running when the user expects
   to test it.

If the user asks you "为什么没有commit/重启", you missed this rule.

## What This Is

FacetX is a native macOS SwiftUI app (macOS 14+) that adds a project dimension
over Apple Calendar and Reminders. EventKit remains the source of truth; FacetX
stores only project-side metadata.

Current status: v0.3 local beta. Implemented features include project
creation/editing, prefix-based aggregation, Today/month/week views, menu bar
quick capture, completed-item filtering, EventKit live refresh, Settings
container selection, week goals backed by calendar events, and GitHub commit
integration.

Read the durable docs before changing architecture or build behavior:

- [Architecture](docs/ARCHITECTURE.md)
- [Building](docs/BUILDING.md)
- [Release](docs/RELEASE.md)

## Build And Run

The app must run as a bundled, code-signed `.app`; a bare SwiftPM executable is
denied EventKit access by macOS. Never use `swift run` to launch the app.

```bash
make run      # debug stop -> build -> open -n
make build    # release bundle build
make check    # SwiftPM debug build + FacetXCoreChecks
make dmg      # package app/FacetX-<version>.dmg
make clean    # remove local build artifacts
make logs     # stream FacetX OS logs
```

`scripts/build.sh` delegates to `app/build-app.sh`, which wraps the SwiftPM
binary into a signed app bundle with `Info.plist`, `FacetX.entitlements`,
resources, variant metadata, and codesigning. It prefers
`FACETX_SIGN_IDENTITY`, then the first local `Apple Development` identity, then
ad-hoc signing.

When build output says `signing: ad-hoc`, tell the user Calendar/Reminders may
ask for authorization again after rebuilds.

Distinguish the two common prompt families:

- `codesign` or login-keychain password prompts happen during build/signing.
  Tell the user to choose Always Allow for `codesign` if they want repeated
  rebuilds to avoid private-key access prompts.
- FacetX Calendar/Reminders prompts are macOS TCC prompts. Rebuilding changed
  code does not require a new TCC grant when bundle ID and signing identity stay
  stable. Branch/worktree variants use distinct bundle IDs and each variant
  needs Calendar/Reminders authorization once.

## Core Contract

An item belongs to a project when its title starts with `ProjectName:`.
Always use `ProjectPrefix` for parsing and composing titles.

- Accept ASCII `:` and fullwidth `：` on read.
- Always write ASCII `:`.
- Parse only the first line.
- Ignore and never modify items without a recognized project prefix.

`FacetAssociation` is the single classifier for regular project items, week
goal events, and unrelated EventKit items. Week goal events must never appear
in ordinary item lists.

## Architecture Rules

- `EventKitService` is the only file that touches EventKit.
- `EventKitService` is intentionally not `@MainActor`; flatten non-Sendable
  `EKReminder`/`EKEvent` values into `ProjectItem` inside EventKit callbacks
  before actor hops.
- `ProjectStore` persists only project metadata. It must not store reminder or
  calendar item content.
- `AppSettings` owns app-wide container filters and default save targets.
- Containers are keyed by title, not identifier.
- Week IDs are ISO-8601 Monday-start strings such as `2026-W22`; use `ISOWeek`.
- `FacetXCore` must remain pure SwiftPM logic with no SwiftUI or EventKit
  dependency.

## AppKit Conventions

**NSPopover delegate lifecycle**

- Use `popoverDidShow` (not `popoverWillShow`) when accessing the popover's
  underlying window via `contentViewController?.view.window`. During
  `popoverWillShow` the hosting window has not yet been attached to the view
  hierarchy, so `view.window` is `nil` and any window-level configuration
  (e.g. `collectionBehavior`, `level`) is silently skipped.
- Call `NSApp.activate(ignoringOtherApps: true)` **before** `popover.show()`
  whenever keyboard focus is expected immediately after the popover appears.
  Activating after show can leave the popover window non-key, causing
  `@FocusState` bindings set in `onAppear` to have no effect.

## Source Layout

App source lives under [app/Sources/FacetX](app/Sources/FacetX):

- `App/` — app entry, support paths, menu bar controller
- `Services/` — EventKit and GitHub boundaries
- `Stores/` — persisted app/project state
- `Views/` — SwiftUI screens and feature views
- `UI/` — shared visual components and theme
- `Utilities/` — small local helpers

Shared pure logic lives under [app/Sources/FacetXCore](app/Sources/FacetXCore).
Lightweight executable checks live under
[app/Checks/FacetXCoreChecks](app/Checks/FacetXCoreChecks).

## Conventions

- Thread `settings.effectiveReminderListNames` and
  `settings.effectiveCalendarNames` through fetch/create paths.
- Save-target selection should go through `AppSettings.reminderSaveTarget` and
  `AppSettings.calendarSaveTarget`.
- JSON stores write atomically with `[.prettyPrinted, .sortedKeys]`.
- Keep dependency surface at zero: SwiftPM plus system frameworks only.
- Do not hand-edit generated artifacts such as `app/.build`, `app/*.app`, or
  `app/*.dmg`; regenerate them through scripts.

## Commit Style

One commit per functional unit. Each commit must compile, pass checks, and be
coherent on its own. Do not combine a bug fix with a refactor, or a feature
with style polish—split them into separate commits. Do not stage partial
implementations or TODO placeholders.

- `feat(...)` — new capability
- `fix(...)` — bug fix
- `style(...)` — UI-only polish
- `refactor(...)` — restructuring with no behavior change

Format: `prefix(scope): imperative description`.

## Design Principles

- Efficiency first: every view should load in one pass where possible.
- Native macOS: follow Apple HIG, system materials, and first-party utility
  conventions.
- Aesthetic consistency: cards, sheets, and editors share the `FacetTheme`
  vocabulary; avoid mixing default Form styles with custom card layouts.
- Keep workflow actions in the main UI and app-wide configuration in Settings.
