import AppKit
import Combine
import SwiftUI

/// Menu bar presence: left-click opens the quick-capture popover, right-click
/// opens a control menu (main window, desktop widget layer/visibility, quit),
/// and a live badge next to the icon counts what still needs attention today
/// (open reminders due today + overdue).
@MainActor
final class MenuBarController: NSObject, ObservableObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    private var configured = false

    private weak var settings: AppSettings?
    private weak var model: WidgetDataModel?
    private weak var widgetController: DesktopWidgetController?

    func configure(eventKit: EventKitService, store: ProjectStore, settings: AppSettings,
                   model: WidgetDataModel, widgetController: DesktopWidgetController) {
        guard !configured else { return }
        configured = true
        self.settings = settings
        self.model = model
        self.widgetController = widgetController

        settings.$menuBarEnabled
            .removeDuplicates()
            .sink { [weak self, weak eventKit, weak store, weak settings] enabled in
                guard let self, let eventKit, let store, let settings else { return }
                self.setVisible(enabled, eventKit: eventKit, store: store, settings: settings)
            }
            .store(in: &cancellables)

        model.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)
    }

    private func setVisible(_ visible: Bool,
                            eventKit: EventKitService,
                            store: ProjectStore,
                            settings: AppSettings) {
        if visible {
            install(eventKit: eventKit, store: store, settings: settings)
        } else {
            popover?.close()
            popover = nil
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    private func install(eventKit: EventKitService, store: ProjectStore, settings: AppSettings) {
        if statusItem != nil { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.templateImage()
        item.button?.imagePosition = .imageLeft
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = L10n.pick("FacetX — click to capture, right-click for controls",
                                         "FacetX — 点按快速添加，右键打开控制菜单")
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let hostingController = NSHostingController(
            rootView: QuickCaptureView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
        )
        popover.contentViewController = hostingController
        self.popover = popover
        updateBadge()
    }

    /// Show "how much is left today" next to the icon; hide the number when
    /// everything is done so the bar stays quiet.
    private func updateBadge() {
        guard let button = statusItem?.button, let model else { return }
        let count = model.menuBarBadgeCount
        button.title = count > 0 ? " \(count)" : ""
    }

    // ── Click handling ───────────────────────────────────────────────────────

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showControlMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.close()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showControlMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let open = NSMenuItem(title: L10n.pick("Open FacetX", "打开 FacetX"),
                              action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let widgetVisible = settings?.desktopWidgetEnabled == true
        let toggleWidget = NSMenuItem(
            title: widgetVisible ? L10n.pick("Hide Desktop Widget", "隐藏桌面小组件")
                                 : L10n.pick("Show Desktop Widget", "显示桌面小组件"),
            action: #selector(toggleWidgetVisibility), keyEquivalent: "")
        toggleWidget.target = self
        menu.addItem(toggleWidget)

        if widgetVisible {
            let front = widgetController?.isFrontMode == true
            let layer = NSMenuItem(
                title: front ? L10n.pick("Send Widget to Desktop", "小组件沉到桌面")
                             : L10n.pick("Bring Widget to Front", "小组件悬浮置顶"),
                action: #selector(toggleWidgetLayer), keyEquivalent: "")
            layer.target = self
            menu.addItem(layer)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.pick("Quit FacetX", "退出 FacetX"),
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attach transiently: a permanent statusItem.menu would swallow left
        // clicks and break the quick-capture popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows.filter { $0.canBecomeMain }
        if windows.isEmpty {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        } else {
            for w in windows { w.makeKeyAndOrderFront(nil) }
        }
    }

    @objc private func toggleWidgetVisibility() {
        guard let settings else { return }
        settings.desktopWidgetEnabled.toggle()
        if settings.desktopWidgetEnabled {
            widgetController?.revealInFront()
        }
    }

    @objc private func toggleWidgetLayer() {
        widgetController?.toggleLayer()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // ── Popover window behavior ──────────────────────────────────────────────

    func popoverDidShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              let popoverWindow = popover.contentViewController?.view.window else { return }
        popoverWindow.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        popoverWindow.level = .popUpMenu
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
