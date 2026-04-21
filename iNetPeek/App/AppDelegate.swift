import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = FailoverStore.shared
    private lazy var monitor = FailoverMonitor(store: store)
    private var menuBarController: MenuBarController?
    private var preferencesWindow: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Primeira execução: enumerar interfaces e popular o registro
        InterfaceRegistry.shared.refresh()

        menuBarController = MenuBarController(
            store: store,
            onOpenPreferences: { [weak self] in
                self?.openPreferences()
            },
            onForceInterface: { [weak self] serviceID in
                self?.monitor.forceInterface(serviceID)
            }
        )

        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController()
        }
        preferencesWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
