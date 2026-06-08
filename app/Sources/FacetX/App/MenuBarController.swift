import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var panel: QuickCapturePanel?
    private var cancellable: AnyCancellable?
    private var configured = false
    private var eventKit: EventKitService?
    private var store: ProjectStore?
    private var settings: AppSettings?
    private var isClosingPanel = false
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func configure(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true
        self.eventKit = eventKit
        self.store = store
        self.settings = settings

        cancellable = settings.$menuBarEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.setVisible(enabled)
            }

        setVisible(settings.menuBarEnabled)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            install()
        } else {
            closePanel()
            removeClickMonitors()
            panel?.onClose = nil
            panel = nil
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    private func install() {
        if statusItem != nil { return }
        guard let eventKit, let store, let settings else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.templateImage()
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        statusItem = item

        let panel = QuickCapturePanel(contentSize: NSSize(width: 380, height: 220))
        panel.onClose = { [weak self] in
            self?.closePanel()
        }
        panel.contentViewController = NSHostingController(
            rootView: QuickCaptureView(
                onDismiss: { [weak self] in self?.closePanel() },
                onOpenMain: { [weak self] in
                    self?.openMainWindow()
                    self?.closePanel()
                }
            )
            .environmentObject(eventKit)
            .environmentObject(store)
            .environmentObject(settings)
        )
        self.panel = panel
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let button = statusItem?.button else { return }
        position(panel, below: button)
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickMonitors()
    }

    private func closePanel() {
        guard let panel, !isClosingPanel else { return }
        isClosingPanel = true
        removeClickMonitors()
        if panel.isVisible {
            panel.orderOut(nil)
        }
        isClosingPanel = false
    }

    private func installClickMonitors() {
        removeClickMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.closePanelIfClickIsOutside(event)
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.closePanelIfClickIsOutside(event)
        }
    }

    private func removeClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func closePanelIfClickIsOutside(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }
        if event.window === panel { return }
        if let buttonWindow = statusItem?.button?.window, event.window === buttonWindow { return }
        closePanel()
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton) {
        let preferredSize = panel.contentViewController?.view.fittingSize ?? NSSize(width: 380, height: 210)
        let screenFrame = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
        let x = min(max(buttonFrame.midX - preferredSize.width / 2, screenFrame.minX + 8), screenFrame.maxX - preferredSize.width - 8)
        let y = buttonFrame.minY - preferredSize.height - 8
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: preferredSize), display: true)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows.filter { $0.canBecomeMain }
        if windows.isEmpty {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        } else {
            for window in windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    static func templateImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        if let url = Bundle.main.url(forResource: "FacetXMenuBarTemplate", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let rep = NSBitmapImageRep(data: data) {
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        if let url = Bundle.main.url(forResource: "FacetXMenuBarTemplate@2x", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let rep = NSBitmapImageRep(data: data) {
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        if image.representations.isEmpty,
           let fallback = NSImage(systemSymbolName: "diamond", accessibilityDescription: "FacetX") {
            fallback.isTemplate = true
            fallback.size = NSSize(width: 18, height: 18)
            return fallback
        }
        image.isTemplate = true
        return image
    }
}

final class QuickCapturePanel: NSPanel {
    var onClose: (() -> Void)?

    init(contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        level = .statusBar
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        isMovable = false
        isMovableByWindowBackground = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        setContentSize(contentSize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
