import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var panel: QuickCapturePanel?
    private var cancellable: AnyCancellable?
    private var configured = false
    private weak var eventKit: EventKitService?
    private weak var store: ProjectStore?
    private weak var settings: AppSettings?

    func configure(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true
        self.eventKit = eventKit
        self.store = store
        self.settings = settings

        cancellable = settings.$menuBarEnabled
            .removeDuplicates()
            .sink { [weak self, weak eventKit, weak store, weak settings] enabled in
                guard let self, let eventKit, let store, let settings else { return }
                self.setVisible(enabled, eventKit: eventKit, store: store, settings: settings)
            }

        setVisible(settings.menuBarEnabled, eventKit: eventKit, store: store, settings: settings)
    }

    private func setVisible(_ visible: Bool,
                            eventKit: EventKitService,
                            store: ProjectStore,
                            settings: AppSettings) {
        if visible {
            install(eventKit: eventKit, store: store, settings: settings)
        } else {
            closePanel()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    private func install(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        if statusItem != nil { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.templateImage()
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        statusItem = item
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let eventKit, let store, let settings, let button = statusItem?.button else { return }
        let panel = QuickCapturePanel()
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
        position(panel, below: button)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func closePanel() {
        guard let panel else { return }
        panel.onClose = nil
        panel.orderOut(nil)
        self.panel = nil
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

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        level = .statusBar
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        hasShadow = true
        backgroundColor = .clear
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onClose?()
    }
}
