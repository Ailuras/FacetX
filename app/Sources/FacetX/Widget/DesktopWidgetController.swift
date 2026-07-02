import AppKit
import Combine
import SwiftUI

/// Borderless glass panel that lives just above the desktop icons, following
/// codexU's widget-window pattern: always visible under normal windows, drag
/// anywhere on its background to move, and a "front" mode that floats it above
/// other apps for interaction.
final class DesktopWidgetPanel: NSPanel {
    private static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        level = Self.desktopLevel
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    func moveToDesktopLayer() {
        level = Self.desktopLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        orderFrontRegardless()
    }

    func moveToFrontLayer() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Rounded glass container for the widget content: Liquid Glass on macOS 26,
/// HUD material below. Dragging any non-control area moves the panel.
private final class GlassWidgetContainer<Content: View>: NSView {
    init(rootView: Content, cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius

        let host = NSHostingView(rootView: rootView)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = cornerRadius
            glass.contentView = host
            addSubview(glass)
        } else {
            let material = NSVisualEffectView(frame: bounds)
            material.autoresizingMask = [.width, .height]
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = cornerRadius
            material.layer?.masksToBounds = true
            material.addSubview(host)
            addSubview(material)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor
final class DesktopWidgetController: NSObject, ObservableObject, NSWindowDelegate {
    static let widgetWidth: CGFloat = 344
    static let widgetDefaultHeight: CGFloat = 560
    static let widgetMinHeight: CGFloat = 380
    static let widgetMaxHeight: CGFloat = 860
    private static let frameKey = "DesktopWidgetFrame"

    @Published private(set) var isFrontMode = false
    @Published private(set) var isVisible = false

    private var panel: DesktopWidgetPanel?
    private var cancellable: AnyCancellable?
    private var configured = false

    func configure(eventKit: EventKitService, store: ProjectStore,
                   settings: AppSettings, model: WidgetDataModel) {
        guard !configured else { return }
        configured = true

        cancellable = settings.$desktopWidgetEnabled
            .removeDuplicates()
            .sink { [weak self, weak eventKit, weak store, weak settings, weak model] enabled in
                guard let self, let eventKit, let store, let settings, let model else { return }
                if enabled {
                    self.install(eventKit: eventKit, store: store, settings: settings, model: model)
                } else {
                    self.uninstall()
                }
            }
    }

    /// codexU-style toggle: desktop layer <-> floating above other windows.
    func toggleLayer() {
        guard let panel else { return }
        if isFrontMode {
            panel.moveToDesktopLayer()
            isFrontMode = false
        } else {
            panel.moveToFrontLayer()
            isFrontMode = true
        }
    }

    /// Bring the widget forward (used right after enabling it from the menu so
    /// the user sees it appear even with windows covering the desktop).
    func revealInFront() {
        guard let panel else { return }
        panel.moveToFrontLayer()
        isFrontMode = true
    }

    private func install(eventKit: EventKitService, store: ProjectStore,
                         settings: AppSettings, model: WidgetDataModel) {
        if panel != nil { return }

        let panel = DesktopWidgetPanel(contentRect: restoredFrame())
        panel.delegate = self
        panel.minSize = CGSize(width: Self.widgetWidth, height: Self.widgetMinHeight)
        panel.maxSize = CGSize(width: Self.widgetWidth, height: Self.widgetMaxHeight)

        let root = DesktopWidgetView(controller: self)
            .environmentObject(eventKit)
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(model)
        panel.contentView = GlassWidgetContainer(rootView: root, cornerRadius: 22)
        panel.moveToDesktopLayer()
        self.panel = panel
        isFrontMode = false
        isVisible = true
        model.scheduleReload()
    }

    private func uninstall() {
        panel?.orderOut(nil)
        panel = nil
        isFrontMode = false
        isVisible = false
    }

    // ── Frame persistence ────────────────────────────────────────────────────

    private func restoredFrame() -> NSRect {
        let size = CGSize(width: Self.widgetWidth, height: Self.widgetDefaultHeight)
        if let stored = UserDefaults.standard.string(forKey: Self.frameKey) {
            let rect = NSRectFromString(stored)
            if !rect.isEmpty, NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
                return NSRect(origin: rect.origin,
                              size: CGSize(width: size.width, height: rect.height))
            }
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(
            x: max(screen.minX + 16, screen.maxX - size.width - 28),
            y: max(screen.minY + 16, screen.maxY - size.height - 40)
        )
        return NSRect(origin: origin, size: size)
    }

    private func persistFrame() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowDidResize(_ notification: Notification) { persistFrame() }
}
