import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private let store: FailoverStore
    private let onOpenPreferences: () -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private let onForceInterface: (String?) -> Void

    init(
        store: FailoverStore,
        onOpenPreferences: @escaping () -> Void,
        onForceInterface: @escaping (String?) -> Void
    ) {
        self.store = store
        self.onOpenPreferences = onOpenPreferences
        self.onForceInterface = onForceInterface
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.isMovable = false
        panel.isFloatingPanel = true
        self.panel = panel

        super.init()

        let hosting = NSHostingController(
            rootView: StatusPopoverView(
                onOpenPreferences: onOpenPreferences,
                onForceInterface: onForceInterface
            )
            .environmentObject(store)
            .environmentObject(InterfaceRegistry.shared)
        )
        hosting.view.frame = NSRect(x: 0, y: 0, width: 380, height: 420)
        panel.contentViewController = hosting

        if let button = statusItem.button {
            button.action = #selector(toggle(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        store.objectWillChange
            .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)

        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }

        let symbol: String
        let tooltip: String

        let active = store.activeServiceID
        if let active,
           let iface = InterfaceRegistry.shared.available.first(where: { $0.serviceID == active }) {
            symbol = iface.hardwareType.sfSymbolName
            let h = store.health[active] ?? .unknown
            tooltip = "iNetPeek — \(iface.displayName) · \(h.label)"
        } else if InterfaceRegistry.shared.monitoredOrder.isEmpty {
            symbol = "questionmark.circle"
            tooltip = "iNetPeek — nenhuma interface configurada"
        } else {
            symbol = "exclamationmark.triangle"
            tooltip = "iNetPeek — todas as interfaces com problema"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "iNetPeek")
        image?.isTemplate = true
        button.image = image
        button.toolTip = tooltip
    }

    @objc private func toggle(_ sender: Any?) {
        panel.isVisible ? close() : show()
    }

    private func show() {
        guard let button = statusItem.button,
              let buttonWindow = button.window
        else { return }

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        var origin = NSPoint(
            x: screenRect.midX - panel.frame.width / 2,
            y: screenRect.minY - panel.frame.height - 6
        )
        if let screen = NSScreen.main {
            origin.x = max(8, min(origin.x, screen.visibleFrame.maxX - panel.frame.width - 8))
        }

        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self.panel { self.close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func close() {
        panel.orderOut(nil)
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}
