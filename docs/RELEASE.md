# Release Checklist

FacetX release packaging is local and unsigned-for-distribution: the app is
code-signed for development but not notarized.

## Package

```bash
make build
make dmg
```

The DMG is written to `app/FacetX-<version>.dmg` and contains `FacetX.app` plus
an `/Applications` shortcut.

## Verify

Run the local validation suite:

```bash
make check
scripts/build.sh debug
codesign --verify --deep --strict --verbose=2 app/FacetX.app
git diff --check HEAD
```

Inspect the signed bundle when signing behavior matters:

```bash
codesign -dv --verbose=4 app/FacetX.app 2>&1 | grep -E "Authority|TeamIdentifier|Identifier"
```

The canonical build should keep bundle ID `com.facetx.app`. Development signing
should prefer the local Apple Development identity when available.

## Version

Version metadata lives in `app/Info.plist`.

Update `CFBundleShortVersionString` and `CFBundleVersion` with release changes.
Keep release notes in README or docs when the user asks for a version bump.
