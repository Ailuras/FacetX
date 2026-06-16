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
///
/// It also forces the overlay scroller style so the scroller never *reserves*
/// layout width: a legacy scroller insets the document view, which shifts
/// fixed-width, centered content sideways when content overflows.
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
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
    }
}

/// Hides the scroller of a `TextEditor`, whose own inner `NSScrollView` the
/// enclosing-scroll-view approach can't reach. Searches the sibling subtree
/// of the background view for the text view's scroll view.
struct HiddenTextEditorScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.disableScrollers(near: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.disableScrollers(near: nsView) }
    }

    private static func disableScrollers(near view: NSView) {
        guard let parent = view.superview else { return }
        for scrollView in parent.descendantScrollViews() {
            scrollView.scrollerStyle = .overlay
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
    }
}

private extension NSView {
    func descendantScrollViews() -> [NSScrollView] {
        subviews.flatMap { sub -> [NSScrollView] in
            let nested = sub.descendantScrollViews()
            return (sub as? NSScrollView).map { [$0] + nested } ?? nested
        }
    }
}

extension View {
    /// Hides both the SwiftUI overlay indicators and the legacy AppKit
    /// scroller of the enclosing scroll view.
    func hideScrollIndicators() -> some View {
        background(HiddenScrollIndicators())
    }

    /// Hides the scroller of a `TextEditor`'s own inner scroll view.
    func hideTextEditorScroller() -> some View {
        background(HiddenTextEditorScroller())
    }
}
