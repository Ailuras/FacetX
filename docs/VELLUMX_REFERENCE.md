# VellumX Reference Notes

VellumX is no longer kept as a source copy in this repository. These notes keep
the parts that are still useful for FacetX after reviewing the vendored
`vellumx/` source snapshot.

## Already Absorbed

- Literature workflows should share one service entrypoint. VellumX used
  `PaperWorkflowService` for manual fetch, manual recommendation, menu-bar
  actions, and automation. FacetX already follows this shape for literature
  fetch/recommend operations.
- Automation state should stay local-only in `UserDefaults`. VellumX kept
  `AutomationPreferences` separate from exported settings, while
  `AutomationScheduler` checked on launch and on a timer. FacetX's literature
  automation keeps the same boundary.
- Native macOS chrome wins over custom-drawn toolbar/search surfaces. VellumX's
  stable path was small toolbar icons, native search placement, and minimal
  layout constraints.
- Current-only storage cleanup should delete schema migrations and disposable
  test data together. FacetX now follows this for literature and item note
  stores.

## Still Worth Borrowing

- Keep scheduler timing rules as pure static functions with focused tests:
  daily due checks, monthly due checks, scheduled time boundaries, and
  "past target day runs immediately" behavior. FacetX has the runtime scheduler;
  adding similarly focused checks would make automation safer.
- Preserve native multi-selection behavior when a list needs custom row visuals.
  VellumX let SwiftUI `List(selection:)` own selection, context menus, keyboard
  navigation, and command selection, while customizing only the visual row cue.
  FacetX should prefer that pattern before adding custom selection state.
- Use a settings router for deep links into Settings. VellumX's
  `SettingsRouter` let feature views request a specific Settings tab before
  opening Settings. FacetX can adopt the same idea when literature/project views
  need to jump directly to a configuration pane.
- Keep window-local alert channels for Settings confirmations. VellumX avoided
  pulling focus back to the main window when a Settings tab needed confirmation.
  FacetX should use this pattern if Settings gains destructive or confirm-heavy
  actions.
- Treat citation/export helpers and PDF resolver/storage logic as pure or
  near-pure units with direct tests. VellumX had focused tests for citation
  formatting, PDF metadata extraction, resolver behavior, storage, reading time,
  scoring, and recommendation logic; FacetX should mirror this coverage around
  its literature module.

## Do Not Carry Forward

- Do not restore VellumX collections. FacetX has topic/project/item ownership
  now; collection paths were removed intentionally.
- Do not copy VellumX's old `MenuBarController` timing behavior directly.
  FacetX's current AppKit shell has its own fullscreen/focus rules documented
  in `AGENTS.md`.
- Do not keep VellumX compatibility or migration shims. FacetX remains
  current-only while local beta data is disposable.
