import AppKit
import Combine
import SwiftUI

struct MenuBarInstaller: View {
    @ObservedObject var controller: MenuBarController
    @EnvironmentObject private var eventKit: EventKitService
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                controller.configure(eventKit: eventKit, store: store, settings: settings)
            }
    }
}

@MainActor
final class MenuBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var panel: QuickCapturePanel?
    private var cancellable: AnyCancellable?
    private var configured = false

    func configure(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        guard !configured else { return }
        configured = true

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
            panel?.close()
            panel = nil
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

        let panel = QuickCapturePanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 340, height: 180)),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(
            rootView: QuickCaptureView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
        )
        panel.setContentSize(NSSize(width: 340, height: 180))
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        self.panel = panel
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        guard let panel else { return }
        if panel.isVisible {
            panel.close()
        } else {
            position(panel, below: sender)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(sender)
            panel.orderFrontRegardless()
        }
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton) {
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = button.window?.convertToScreen(buttonRect)
        let screen = button.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let panelSize = panel.frame.size

        let anchor = screenRect ?? NSRect(
            x: visibleFrame.maxX - panelSize.width - 12,
            y: visibleFrame.maxY,
            width: panelSize.width,
            height: 0
        )
        let proposedX = anchor.midX - panelSize.width / 2
        let x = min(max(proposedX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        let y = max(visibleFrame.minY + 8, anchor.minY - panelSize.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
