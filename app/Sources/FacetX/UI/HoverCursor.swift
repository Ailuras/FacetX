import AppKit
import SwiftUI

/// Shows `cursor` while the pointer hovers the modified view, restoring the
/// previous cursor on exit.
///
/// Pure SwiftUI (`onHover` + the `NSCursor` stack) so it never competes with an
/// attached `.onDrag`/tap gesture for hit testing. The `isInside` guard keeps
/// pushes and pops balanced, and `onDisappear` pops a dangling cursor if the
/// view is removed while still hovered (e.g. the row scrolls away).
private struct HoverCursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isInside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isInside else { return }
                isInside = hovering
                if hovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isInside {
                    NSCursor.pop()
                    isInside = false
                }
            }
    }
}

extension View {
    /// Displays `cursor` whenever the pointer hovers this view.
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(HoverCursorModifier(cursor: cursor))
    }
}
