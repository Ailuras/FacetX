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

/// Forces the enclosing scroll view to use thin *overlay* scrollers instead of
/// the chunky legacy scrollers shown when the system "Show scroll bars" setting
/// resolves to always-on (e.g. a mouse is attached). Scrolling and the scroller
/// itself stay intact — only the appearance is slimmed.
struct ThinScrollIndicators: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(from: nsView) }
    }

    private static func apply(from view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScroller?.controlSize = .small
    }
}

/// Hides the scroller of a `TextEditor`, whose own inner `NSScrollView` the
/// enclosing-scroll-view approach can't reach. SwiftUI hosts the background
/// marker and the text view in separate containers, so this walks up the
/// ancestor chain until it reaches a common ancestor whose subtree contains
/// the text view's scroll view, and retries since that scroll view may not be
/// in the hierarchy on the first layout pass.
struct HiddenTextEditorScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Self.scheduleDisable(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.scheduleDisable(for: nsView)
    }

    private static func scheduleDisable(for view: NSView, attempt: Int = 0) {
        DispatchQueue.main.async {
            if disableScrollers(near: view) || attempt >= 6 { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                scheduleDisable(for: view, attempt: attempt + 1)
            }
        }
    }

    /// Returns true once a text-view scroll view was found and hidden.
    @discardableResult
    private static func disableScrollers(near view: NSView) -> Bool {
        var node = view.superview
        var hops = 0
        while let current = node, hops < 8 {
            let textScrollViews = current.descendantScrollViews()
                .filter { $0.documentView is NSTextView }
            if !textScrollViews.isEmpty {
                for scrollView in textScrollViews {
                    scrollView.scrollerStyle = .overlay
                    scrollView.hasVerticalScroller = false
                    scrollView.hasHorizontalScroller = false
                }
                return true
            }
            node = current.superview
            hops += 1
        }
        return false
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

    /// Forces thin overlay scrollers on the enclosing scroll view.
    func thinScrollIndicators() -> some View {
        background(ThinScrollIndicators())
    }
}
