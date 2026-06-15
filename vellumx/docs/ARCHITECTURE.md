# VellumX Architecture

VellumX is a native macOS SwiftUI app that manages a local academic paper
library. It fetches papers from OpenAlex, scores recommendations, translates
abstracts, resolves open-access PDFs, and stores reading workflow state in
SQLite.

## Runtime Shape

- `VellumXApp` creates the main window and AppKit menu bar controller.
- `AutomationScheduler` checks local task timing while the app is running and
  calls shared paper workflows when monthly fetch or daily recommendation is
  due.
- `ContentView` hosts the two-column workspace: filters and collections on the
  left, paper detail and reading workflow on the right.
- `PaperStore` is the main `@MainActor` SQLite-backed observable store for
  papers, states, collections, notes, cached scores, and recommendations.
- `MetadataStore` opens the same SQLite file for academic taxonomy and scoring
  metadata: tracks, fields, tiers, venues, and citation scoring rules.
- `AppSettings` persists app preferences and resolves the active database
  directory.

## Data Model

The default canonical database is:

```text
~/Library/Application Support/VellumX/vellumx.db
```

Branch/worktree variants use their own Application Support directory, such as:

```text
~/Library/Application Support/VellumX-feat-pdf/vellumx.db
```

Users can still relocate the database from Settings. Relocation updates
`AppSettings.storageDirectory`, reopens `PaperStore`, and repoints
`MetadataStore` at the same file.

Translation API keys are stored as local plaintext in the active variant's
`settings.json`.

## Services

- `OpenAlexFetcher` fetches paper metadata.
- `RecommendEngine` and `VenueScorer` select and score recommendations.
- `PaperWorkflowService` is the shared entrypoint for fetch and recommendation
  runs used by buttons, menu bar actions, and automation.
- `TranslationService` handles provider-backed abstract translation.
- `PdfResolver` resolves open-access PDF URLs across multiple sources.
- `CitationExporter` formats citations and BibTeX output.

## Build Variants

`main` and `master` build the canonical app:

```text
VellumX.app
com.ailuras.vellumx
~/Library/Application Support/VellumX
```

Other branches build isolated variants:

```text
VellumX-<variant>.app
com.ailuras.vellumx.dev.<variant>
~/Library/Application Support/VellumX-<variant>
```

The support-directory name is written into the app bundle as
`VellumXApplicationSupportName`; `AppSettings` reads that value at runtime.

## Tests

Unit tests live under `app/Tests/VellumXTests` and cover pure business logic and
SQLite helper behavior. UI behavior, network requests, and bundled app behavior
are verified manually.
