import Foundation
import ServiceManagement

/// Wrapper sobre `SMAppService.mainApp` pra ligar/desligar o "iniciar com o macOS"
/// e expor o estado atual como `@Published` pra UI.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            apply(isEnabled)
        }
    }

    private init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Re-lê o estado real do sistema (ex.: usuário desativou em System Settings → General → Login Items).
    func refresh() {
        let actual = SMAppService.mainApp.status == .enabled
        if actual != isEnabled { isEnabled = actual }
    }

    private func apply(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("[iNetPeek] LaunchAtLogin falhou: %@", error.localizedDescription)
            // Reverte o toggle pra refletir o estado real
            let actual = SMAppService.mainApp.status == .enabled
            if actual != isEnabled { isEnabled = actual }
        }
    }
}
