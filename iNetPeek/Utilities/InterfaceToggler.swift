import Foundation

/// Habilita/desabilita interfaces de rede via `networksetup`.
///
/// Importante: a forma "certa" de desligar depende do tipo de interface:
///
/// - **Wi-Fi**: `-setairportpower <bsd> off/on` — desliga só o rádio, sem mexer em config.
///   Usar `-setnetworkserviceenabled off` no Wi-Fi **pode deixar o serviço em estado
///   "não configurado"**, obrigando o usuário a recriar a config manualmente.
/// - **Ethernet / outras**: `-setnetworkserviceenabled on/off` é seguro.
///
/// O macOS pode pedir senha de admin na primeira vez. Para operação 100% automática
/// sem prompts, o caminho é um helper via SMJobBless — fica como evolução futura.
struct InterfaceToggler {
    enum ToggleError: Error, LocalizedError {
        case commandFailed(exitCode: Int32, output: String)
        case serviceNameUnavailable

        var errorDescription: String? {
            switch self {
            case .commandFailed(let code, let output):
                return "networksetup falhou (exit \(code)): \(output)"
            case .serviceNameUnavailable:
                return "serviço de rede sem nome — não dá pra ativar/desativar"
            }
        }
    }

    /// Liga/desliga uma interface, escolhendo o comando certo para cada tipo.
    static func setEnabled(_ enabled: Bool, for interface: NetworkInterfaceInfo) throws {
        switch interface.hardwareType {
        case .wifi:
            // Pra Wi-Fi, controlar o rádio é o caminho seguro.
            if let bsd = interface.bsdName, !bsd.isEmpty {
                try setAirportPower(enabled, device: bsd)
            } else {
                // Sem BSD name só sobra o caminho do serviço — risco conhecido de
                // "desconfigurar", mas é o que temos.
                try setServiceEnabled(enabled, serviceName: interface.displayName)
            }
        default:
            try setServiceEnabled(enabled, serviceName: interface.displayName)
        }
    }

    /// Controla o rádio Wi-Fi via `-setairportpower`.
    static func setAirportPower(_ enabled: Bool, device: String) throws {
        try runNetworksetup(["-setairportpower", device, enabled ? "on" : "off"])
    }

    /// Habilita/desabilita um serviço de rede pelo nome (Ethernet / outras).
    /// Não usar pra Wi-Fi — pode deixar o serviço em estado "não configurado".
    static func setServiceEnabled(_ enabled: Bool, serviceName: String) throws {
        guard !serviceName.isEmpty else { throw ToggleError.serviceNameUnavailable }
        try runNetworksetup(["-setnetworkserviceenabled", serviceName, enabled ? "on" : "off"])
    }

    private static func runNetworksetup(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ToggleError.commandFailed(
                exitCode: process.terminationStatus,
                output: output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
