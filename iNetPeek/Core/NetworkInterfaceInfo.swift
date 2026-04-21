import Foundation

/// Representa uma interface de rede do sistema (Ethernet, Wi-Fi, dock station, Thunderbolt etc.).
/// O `serviceID` é o identificador persistente da Service no SystemConfiguration;
/// o `bsdName` (ex.: "en0") pode mudar com o tempo, então não é usado como chave.
struct NetworkInterfaceInfo: Identifiable, Hashable, Codable {
    /// ID estável da Service de rede (ex.: UUID retornado pelo SystemConfiguration).
    let serviceID: String

    /// Nome amigável mostrado ao usuário (ex.: "Wi-Fi", "DOCK STATION DELL", "Ethernet USB").
    let displayName: String

    /// Nome BSD atual (ex.: "en0", "en7"). Pode variar entre reinicializações.
    let bsdName: String?

    /// Tipo de hardware (ethernet, wifi, thunderbolt, usb, etc.).
    let hardwareType: HardwareType

    var id: String { serviceID }

    enum HardwareType: String, Codable {
        case ethernet
        case wifi
        case thunderbolt
        case usb
        case bluetooth
        case bridge
        case vpn
        case other

        var sfSymbolName: String {
            switch self {
            case .ethernet:    return "cable.connector"
            case .wifi:        return "wifi"
            case .thunderbolt: return "bolt.horizontal"
            case .usb:         return "cable.connector.horizontal"
            case .bluetooth:   return "wave.3.right"
            case .bridge:      return "arrow.triangle.branch"
            case .vpn:         return "lock.shield"
            case .other:       return "network"
            }
        }
    }
}

/// Estado em tempo real de uma interface monitorada.
enum InterfaceHealth: Equatable {
    case unknown
    case healthy(latencyMs: Double)
    case degraded(reason: String)
    case down(reason: String)
    case disabled

    var isUsable: Bool {
        if case .healthy = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .unknown:              return "verificando…"
        case .healthy(let ms):      return String(format: "ok (%.0f ms)", ms)
        case .degraded(let reason): return "instável — \(reason)"
        case .down(let reason):     return "offline — \(reason)"
        case .disabled:             return "desativada"
        }
    }
}
