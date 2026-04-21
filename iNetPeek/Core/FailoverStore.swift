import Foundation
import Combine

/// Estado observável compartilhado entre o monitor, o menu bar e a UI de preferências.
@MainActor
final class FailoverStore: ObservableObject {
    static let shared = FailoverStore()

    /// Saúde atual por serviceID.
    @Published private(set) var health: [String: InterfaceHealth] = [:]

    /// ServiceID da interface ativa no momento (a que está roteando tráfego).
    @Published private(set) var activeServiceID: String?

    /// Última mensagem relevante (ex.: "Failover → Wi-Fi às 04:12").
    @Published private(set) var lastEvent: String?

    /// Histórico curto de eventos (últimos ~20).
    @Published private(set) var recentEvents: [Event] = []

    /// Se o failover automático está habilitado. Quando desligado, o monitor só observa.
    @Published var autoFailoverEnabled: Bool {
        didSet { UserDefaults.standard.set(autoFailoverEnabled, forKey: "iNetPeek.autoFailover") }
    }

    /// Se o usuário forçou manualmente uma interface específica, aqui fica o serviceID dela.
    /// Enquanto esse valor estiver setado, o monitor NÃO faz failover automático —
    /// só observa e reporta. Clicar em "Voltar ao automático" zera isso.
    @Published var manualOverrideServiceID: String? {
        didSet {
            if let v = manualOverrideServiceID {
                UserDefaults.standard.set(v, forKey: "iNetPeek.manualOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "iNetPeek.manualOverride")
            }
        }
    }

    private let maxEvents = 20

    init() {
        self.autoFailoverEnabled = UserDefaults.standard.object(forKey: "iNetPeek.autoFailover") as? Bool ?? true
        self.manualOverrideServiceID = UserDefaults.standard.string(forKey: "iNetPeek.manualOverride")
    }

    func updateHealth(_ newHealth: [String: InterfaceHealth]) {
        health = newHealth
    }

    func setHealth(_ value: InterfaceHealth, for serviceID: String) {
        health[serviceID] = value
    }

    func setActive(_ serviceID: String?) {
        guard activeServiceID != serviceID else { return }
        activeServiceID = serviceID
    }

    func logEvent(_ message: String) {
        let event = Event(timestamp: Date(), message: message)
        lastEvent = message
        let combined = [event] + recentEvents
        recentEvents = Array(combined.prefix(maxEvents))
        NSLog("[iNetPeek] %@", message)
    }

    struct Event: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }
}
