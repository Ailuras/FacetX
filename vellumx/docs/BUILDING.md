# Building VellumX

VellumX is built with SwiftPM from `app/`, then wrapped into a signed `.app`
bundle. Use the root Makefile for normal development.

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
scripts/test.sh
```

## Bundle Build

`scripts/build.sh` delegates to `app/build-app.sh`. The bundle builder runs
SwiftPM, assembles the `.app`, patches bundle metadata, writes the variant's
support-directory name into `Info.plist`, copies resources, and signs with
`VellumX.entitlements`.

Signing identity selection:

1. `VELLUMX_SIGN_IDENTITY`
2. first local `Apple Development` codesigning identity
3. ad-hoc signing fallback

If the build output says `signing: ad-hoc`, the app can run locally, but Apple
Development signing was not applied.

## Prompt Model

`codesign` or login-keychain password prompts happen while building. They mean
the signing tool wants to use the Apple Development private key in the login
keychain. Choose Always Allow for `codesign` to avoid repeated build-time
prompts. Do not paste the keychain password into scripts or docs.

VellumX does not use Calendar or Reminders TCC permissions. Its entitlement file
only grants network client access.

## Variants

Canonical `main` and `master` builds use:

```text
VellumX.app
com.ailuras.vellumx
~/Library/Application Support/VellumX
```

Other branches build isolated variants such as:

```text
VellumX-feat-pdf.app
com.ailuras.vellumx.dev.feat-pdf
~/Library/Application Support/VellumX-feat-pdf
```

Override variant values only for local development:

```bash
VELLUMX_VARIANT=myfork make run
VELLUMX_APP_NAME=VellumX-local VELLUMX_BUNDLE_ID=com.ailuras.vellumx.dev.local scripts/build.sh debug
```

## Checks

`make check` runs:

```bash
cd app
swift build -c debug
swift test
```

Use `scripts/test.sh --filter <SuiteName>` for focused XCTest runs.
