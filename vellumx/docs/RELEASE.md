# Releasing VellumX

VellumX release artifacts are built from the repository root with the canonical
app identity.

## Build

```bash
make clean
make check
make build
```

Confirm the canonical bundle metadata:

```bash
plutil -p app/VellumX.app/Contents/Info.plist | grep -E "CFBundleIdentifier|VellumXApplicationSupportName"
```

Expected values:

```text
CFBundleIdentifier = com.ailuras.vellumx
VellumXApplicationSupportName = VellumX
```

## Sign

Verify the app bundle:

```bash
codesign --verify --deep --strict --verbose=2 app/VellumX.app
codesign -dv --verbose=4 app/VellumX.app 2>&1 | grep -E "Authority|TeamIdentifier|Identifier"
```

The preferred local signing authority is `Apple Development`. If the bundle is
ad-hoc signed, local development can continue, but it is not a signed release
candidate.

## Package

```bash
make dmg
```

The DMG is written under `app/` as:

```text
app/VellumX-<version>.dmg
```

Generated artifacts are ignored and should be regenerated through scripts:

```text
app/.build/
app/*.app/
app/*.dmg
app/dmg-staging/
```
