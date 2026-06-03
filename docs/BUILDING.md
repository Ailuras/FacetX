# Building FacetX

FacetX must run as a bundled, code-signed `.app`. Do not use `swift run` for
the app itself; macOS silently denies EventKit access to the bare executable.

## Commands

```bash
make run
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

Each variant needs authorization once. Keep the same bundle ID and signing
identity to reuse authorization across rebuilds.

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
