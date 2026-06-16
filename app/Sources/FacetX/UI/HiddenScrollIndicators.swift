import AppKit
import SwiftUI

/// Turns off the scrollers of the enclosing AppKit scroll view.
///
/// SwiftUI's `.scrollIndicators(.hidden)` only reliably hides macOS *overlay*
/// scrollers; the legacy always-visible scroller — shown when the system
/// "Show scroll bars" setting resolves to always-on (e.g. a mouse is
/// connected) — ignores it. Dropping this in a `ScrollView`'s background
/// reaches the backing `NSScrollView` and disables the scrollers for good,
/// while leaving scrolling itself intact.
struct HiddenScrollIndicators: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.disableScrollers(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.disableScrollers(from: nsView) }
    }

    private static func disableScrollers(from view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
    }
}

extension View {
    /// Hides both the SwiftUI overlay indicators and the legacy AppKit
    /// scroller of the enclosing scroll view.
    func hideScrollIndicators() -> some View {
        background(HiddenScrollIndicators())
    }
}
