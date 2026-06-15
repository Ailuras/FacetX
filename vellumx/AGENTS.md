# AGENTS.md

Guidance for Codex agents working in this repository.

## Default Rule: Current Only

VellumX is current-only unless the user explicitly asks for compatibility.
When changing behavior, data shapes, scripts, or docs, delete old logic, old
fields, old paths, and compatibility bridges instead of preserving legacy
entrypoints. Do not keep wrappers, aliases, migration shims, or fallback paths
for removed interfaces unless the user specifically requests them.

## Code Cleanness

Implementations should be minimal and precise. Do not write forward-compatible
layering, speculative abstractions, or unused parameters “just in case.” When a
feature is removed, delete its code, its tests, and its documentation; do not
leave dead code or commented-out blocks behind. Prefer small, single-purpose
units over generalised helpers that accumulate optional behaviour over time.

## After Implementation

When you finish a code change, always do these two things before handing off:

1. **Commit by feature point.** Each commit must be a single, complete,
   reviewable unit. If a change touches multiple concerns, split it into
   separate commits. Follow the prefix format in Commit Style below.
2. **Restart the app.** Run `make run` to rebuild, re-test, re-sign, and
   launch. The user verifies UI changes manually — do not claim a change
   works until the app launches without error.

## What This Is

VellumX is a native macOS SwiftUI app (macOS 14+) for academic paper discovery,
recommendation, translation, PDF resolution, and reading workflow management.
It uses SwiftPM with zero external dependencies and stores library data in a
local SQLite database.

Read the durable docs before changing architecture or build behavior:

- [Architecture](docs/ARCHITECTURE.md)
- [Building](docs/BUILDING.md)
- [Release](docs/RELEASE.md)

## Build And Run

The app should run as a bundled, code-signed `.app`; do not use `swift run` as
the normal app launch path.

```bash
make run      # swift test -> debug build -> codesign -> open -n
make build    # release bundle build
make check    # SwiftPM debug build + XCTest suite
make dmg      # package app/VellumX-<version>.dmg
make clean    # remove local build artifacts
make logs     # stream VellumX OS logs
```

`scripts/build.sh` delegates to `app/build-app.sh`, which wraps the SwiftPM
binary into a signed app bundle with `Info.plist`, `VellumX.entitlements`,
resources, variant metadata, support-directory metadata, and codesigning. It
prefers `VELLUMX_SIGN_IDENTITY`, then the first local `Apple Development`
identity, then ad-hoc signing.

When build output says `signing: ad-hoc`, tell the user the app can still run
locally, but Apple Development signing was not applied.

Distinguish the common prompt family:

- `codesign` or login-keychain password prompts happen during build/signing.
  Tell the user to choose Always Allow for `codesign` if they want repeated
  rebuilds to avoid private-key access prompts.

## UI Verification

Do not screenshot or attempt to interact with the running app to verify UI
changes. Build and launch with `make run`, report the build result, then stop.
The user tests the UI directly.

## Core Contract

- `PaperStore` owns the SQLite paper library and is `@MainActor`.
- `MetadataStore` owns taxonomy and scoring metadata in the same SQLite file.
- `AppSettings` owns app-wide preferences and the active storage directory.
- Translation API keys are stored in `settings.json` as local plaintext.
- Keep dependency surface at zero: SwiftPM plus system frameworks only.
- Do not hand-edit generated artifacts such as `app/.build`, `app/*.app`, or
  `app/*.dmg`; regenerate them through scripts.

## Variant Builds

Canonical builds use:

```text
VellumX.app
com.ailuras.vellumx
~/Library/Application Support/VellumX
```

Branch/worktree variants use:

```text
VellumX-<variant>.app
com.ailuras.vellumx.dev.<variant>
~/Library/Application Support/VellumX-<variant>
```

Use `VELLUMX_VARIANT`, `VELLUMX_APP_NAME`, `VELLUMX_BUNDLE_ID`, and
`VELLUMX_SUPPORT_NAME` only for local overrides. Do not commit machine-specific
values.

## Commit Style

Commit by feature point; each commit should be a single, complete, and
reviewable unit. Do not stack unrelated changes in one commit.

- `feat(...)` - new capability
- `fix(...)` - bug fix
- `style(...)` - UI-only polish
- `refactor(...)` - restructuring with no behavior change
- `docs(...)` - documentation-only change

Format: `prefix(scope): imperative description`.

Keep every commit small and focused so that `git revert` and `git bisect` remain
useful. If a change touches multiple concerns, split it into separate commits.

## Design Principles

- Native macOS: follow system toolbar, sidebar, menu bar, and settings patterns.
- Efficiency first: paper lists and details should load with minimal redundant
  database or network work.
- Keep workflow actions in the main UI and app-wide configuration in Settings.
- Prefer restrained, system-like UI polish over decorative chrome.
