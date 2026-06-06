import AppKit
import SwiftUI

/// Shows a given `NSCursor` while the pointer is over the modified view.
///
/// Implemented with AppKit cursor rects (rather than `onHover` + `push/pop`)
/// so the cursor is managed by the window and never gets stuck if a hover-exit
/// event is missed.
private struct CursorAreaView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> NSView {
        CursorTrackingView(cursor: cursor)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CursorTrackingView else { return }
        view.cursor = cursor
    }

    private final class CursorTrackingView: NSView {
        var cursor: NSCursor {
            didSet { window?.invalidateCursorRects(for: self) }
        }

        init(cursor: NSCursor) {
            self.cursor = cursor
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }
    }
}

extension View {
    /// Displays `cursor` whenever the pointer hovers this view, without
    /// intercepting clicks or drags (the overlay disables hit testing).
    func hoverCursor(_ cursor: NSCursor) -> some View {
        overlay(CursorAreaView(cursor: cursor).allowsHitTesting(false))
    }
}
