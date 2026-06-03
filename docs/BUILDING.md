# Building FacetX

FacetX must run as a bundled, code-signed `.app`. Do not use `swift run` for
the app itself; macOS silently denies EventKit access to the bare executable.

## Commands

```bash
make run      # debug rebuild, codesign, stop, relaunch
make build
make check
make dmg
make clean
make logs
```

Equivalent scripts are kept under `scripts/` for automation:

```bash
scripts/restart.sh
scripts/build.sh
scripts/check.sh
scripts/package-dmg.sh
scripts/clean.sh
scripts/log.sh
```

## Bundle Build

`scripts/build.sh` delegates to `app/build-app.sh`. The bundle builder runs
SwiftPM, assembles `FacetX.app`, patches branch-specific bundle metadata,
copies resources, and signs with EventKit entitlements.

Signing identity selection:

1. `FACETX_SIGN_IDENTITY`
2. first local `Apple Development` codesigning identity
3. ad-hoc signing fallback

If the build output says `signing: ad-hoc`, Calendar/Reminders may ask for
authorization again after rebuilds.

## Prompt Model

Two different macOS prompt families can appear during development:

1. `codesign` or login-keychain password prompts happen while building. They
   mean the signing tool wants to use the Apple Development private key in the
   login keychain. Choose Always Allow for `codesign` to avoid repeated
   build-time prompts. Do not paste the keychain password into scripts or docs.
2. FacetX Calendar/Reminders prompts happen when the app asks EventKit for
   access. This is macOS TCC authorization and is independent from keychain
   private-key access.

Changing source code and rebuilding does not require a new Calendar/Reminders
grant as long as the bundle ID and signing identity stay stable.

## Stable TCC Authorization

Calendar and Reminders authorization is granted per bundle ID and signing
identity. `main` and `master` build the canonical app:

```text
FacetX.app
com.facetx.app
~/Library/Application Support/FacetX
```

Other branches build variants such as:

```text
FacetX-feat-calendar.app
com.facetx.app.dev.feat-calendar
~/Library/Application Support/FacetX-feat-calendar
```

Each variant needs Calendar/Reminders authorization once. Keep the same bundle
ID and signing identity to reuse authorization across rebuilds.

For multiple worktrees, decide whether you want shared or isolated local state:

- Use the branch-derived default variant when worktrees should be isolated.
  Each variant gets its own app name, bundle ID, support directory, and one-time
  Calendar/Reminders grant.
- Set `FACETX_VARIANT=dev` when several worktrees should share one development
  authorization and support directory.

## Local Signing

Inspect local identities:

```bash
security find-identity -v -p codesigning
```

Use a stable identity for development:

```bash
FACETX_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make run
```

Do not commit a machine-specific signing identity.

Variant overrides:

```bash
FACETX_VARIANT=myfork make run
FACETX_APP_NAME=FacetX-local FACETX_BUNDLE_ID=com.facetx.app.dev.local scripts/build.sh debug
```

## Checks

`make check` runs:

```bash
cd app
swift build -c debug
swift run FacetXCoreChecks
```
