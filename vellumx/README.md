# VellumX

VellumX is a native macOS app for building and working through a local academic
paper library. It fetches paper metadata from OpenAlex, scores and surfaces
recommendations, keeps reading state and notes in SQLite, translates abstracts,
and helps attach or resolve PDFs for offline reading.

The app is designed as a desktop workspace, not a hosted service. Your library,
rules, settings, notes, and downloaded PDFs live on your Mac.

![VellumX interface showcase](docs/assets/readme-showcase.png)

## What It Does

- Browse a two-column paper workspace with sidebar views for recommendations,
  reading status, topics, collections, and tags.
- Fetch new papers from OpenAlex using configurable academic topics, venues,
  fields, tiers, and fetch windows.
- Generate daily recommendations from local scoring rules that combine venue
  tier, citation count, recency, and topic metadata.
- Read paper details with abstract, translation, score, venue, citation count,
  tags, collections, notes, recommendation memo, and external links.
- Resolve open-access PDFs, validate real PDF bytes, store downloads locally,
  reveal them in Finder, or attach a PDF manually.
- Export citations as BibTeX, APA, RIS, Markdown, plain text, or CSV.
- Translate abstracts through a configurable API provider and cache translated
  text in the local library.
- Use an optional menu bar popover for today's recommendations and quick paper
  actions without opening the main window.

## Settings

VellumX keeps app-wide configuration in the standard macOS Settings window.

- **General**: language, menu bar visibility, storage location, and settings
  file access.
- **API**: translation provider, model, target language, API key, and connection
  testing.
- **Papers**: daily recommendation count, score thresholds, OpenAlex fetch
  limits, topic filtering, and automation toggles.
- **Rules**: editable topics, venues, tier points, fields, and citation scoring
  curves, with import/export and preset reset.

Translation API keys are stored as local plaintext in the active app variant's
`settings.json`.

## Local Data

Canonical builds store the library under:

```text
~/Library/Application Support/VellumX/
```

The main database is:

```text
~/Library/Application Support/VellumX/vellumx.db
```

Downloaded or manually attached PDFs are stored below the active storage
directory, under `pdfs/`. The storage location can be changed from Settings.

Branch and worktree builds use isolated app identities and support directories,
for example:

```text
VellumX-feat-pdf.app
com.ailuras.vellumx.dev.feat-pdf
~/Library/Application Support/VellumX-feat-pdf
```

## Build And Run

VellumX is a SwiftPM package under `app/`, wrapped into a signed macOS `.app`
bundle by the repository scripts. Use the root `Makefile` for normal
development.

```bash
make run      # test, build debug app, sign, and launch
make build    # build the release app bundle
make check    # SwiftPM debug build + XCTest suite
make dmg      # package app/VellumX-<version>.dmg
make clean    # remove local build and packaging artifacts
make logs     # stream VellumX OS logs
```

Run VellumX as the bundled `.app`; do not use `swift run` as the normal launch
path.

Development builds prefer a local Apple Development signing identity, then fall
back to ad-hoc signing. If macOS asks for the login-keychain password while
building, that is `codesign` requesting access to the private key. Choose Always
Allow for `codesign` to avoid repeated build prompts.

## Requirements

- macOS 14.0 or later
- Swift 6.0 compatible toolchain
- Network access for OpenAlex fetches, PDF resolution, and translation APIs

VellumX intentionally uses SwiftPM plus system frameworks only.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Building](docs/BUILDING.md)
- [Release](docs/RELEASE.md)
- [Agent guide](AGENTS.md)
