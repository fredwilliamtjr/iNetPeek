import Foundation
import SystemConfiguration
import Combine

/// Fonte única da verdade sobre quais interfaces existem no sistema e quais o usuário escolheu
/// monitorar (em que ordem de prioridade). Persiste a escolha em UserDefaults.
@MainActor
final class InterfaceRegistry: ObservableObject {
    static let shared = InterfaceRegistry()

    /// Todas as interfaces detectadas no sistema (atualizadas via `refresh()`).
    @Published private(set) var available: [NetworkInterfaceInfo] = []

    /// ServiceIDs selecionados pelo usuário, em ordem de prioridade (topo = preferencial).
    @Published private(set) var monitoredOrder: [String] = []

    private let defaults: UserDefaults
    private let monitoredKey = "iNetPeek.monitoredOrder"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.monitoredOrder = defaults.stringArray(forKey: monitoredKey) ?? []
    }

    /// Lista as interfaces monitoradas na ordem de prioridade salva.
    /// Ignora serviceIDs que não existem mais no sistema (ex.: dock removida).
    var monitoredInOrder: [NetworkInterfaceInfo] {
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.serviceID, $0) })
        return monitoredOrder.compactMap { byID[$0] }
    }

    /// Interfaces que o usuário ainda não configurou (nem incluiu, nem excluiu explicitamente).
    var unconfigured: [NetworkInterfaceInfo] {
        let monitored = Set(monitoredOrder)
        return available.filter { !monitored.contains($0.serviceID) }
    }

    // MARK: - Persistência

    func setMonitored(_ serviceIDs: [String]) {
        monitoredOrder = serviceIDs
        defaults.set(serviceIDs, forKey: monitoredKey)
    }

    func addToMonitored(_ serviceID: String) {
        guard !monitoredOrder.contains(serviceID) else { return }
        setMonitored(monitoredOrder + [serviceID])
    }

    func removeFromMonitored(_ serviceID: String) {
        setMonitored(monitoredOrder.filter { $0 != serviceID })
    }

    func moveMonitored(from source: IndexSet, to destination: Int) {
        var copy = monitoredOrder
        copy.move(fromOffsets: source, toOffset: destination)
        setMonitored(copy)
    }

    // MARK: - Enumeração de interfaces do sistema

    /// Recarrega a lista de interfaces disponíveis via SystemConfiguration.
    /// Deve ser chamado na partida do app e quando uma interface nova aparece.
    func refresh() {
        available = Self.enumerateInterfaces()
    }

    private static func enumerateInterfaces() -> [NetworkInterfaceInfo] {
        guard let prefs = SCPreferencesCreate(nil, "iNetPeek" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService]
        else {
            return []
        }

        var result: [NetworkInterfaceInfo] = []
        for service in services {
            guard let interface = SCNetworkServiceGetInterface(service) else { continue }

            let serviceID = (SCNetworkServiceGetServiceID(service) as String?) ?? ""
            let displayName = (SCNetworkServiceGetName(service) as String?)
                ?? (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?)
                ?? "Interface \(serviceID.prefix(8))"
            let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?
            let typeString = (SCNetworkInterfaceGetInterfaceType(interface) as String?) ?? ""

            guard !serviceID.isEmpty else { continue }

            result.append(NetworkInterfaceInfo(
                serviceID: serviceID,
                displayName: displayName,
                bsdName: bsdName,
                hardwareType: Self.mapHardwareType(typeString)
            ))
        }
        return result
    }

    private static func mapHardwareType(_ raw: String) -> NetworkInterfaceInfo.HardwareType {
        // Converte as constantes CFString do SystemConfiguration pra String uma única vez,
        // pra podermos usar == em vez de pattern matching (que tem atrito com CFString).
        // Não uso `kSCNetworkInterfaceTypeBridge` / `VPN` porque nem sempre estão no SDK público —
        // comparo pelo valor literal quando faz sentido.
        let ethernet  = kSCNetworkInterfaceTypeEthernet as String
        let wifi      = kSCNetworkInterfaceTypeIEEE80211 as String
        let fireWire  = kSCNetworkInterfaceTypeFireWire as String
        let bluetooth = kSCNetworkInterfaceTypeBluetooth as String
        let bond      = kSCNetworkInterfaceTypeBond as String
        let ipsec     = kSCNetworkInterfaceTypeIPSec as String
        let l2tp      = kSCNetworkInterfaceTypeL2TP as String
        let ppp       = kSCNetworkInterfaceTypePPP as String

        if raw == ethernet  { return .ethernet }
        if raw == wifi      { return .wifi }
        if raw == fireWire  { return .thunderbolt }
        if raw == bluetooth { return .bluetooth }
        if raw == bond || raw == "Bridge" { return .bridge }
        if raw == ipsec || raw == l2tp || raw == ppp || raw == "VPN" { return .vpn }
        // Thunderbolt / USB aparecem como ethernet em muitos casos
        return .other
    }
}
