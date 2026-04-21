import Foundation

/// Dispara pings ICMP via `/sbin/ping`, amarrado em uma interface específica (flag `-b`)
/// para medir a conectividade real de cada link — independente do que o macOS achar
/// que é a interface "default" no momento.
///
/// Resultado possíveis:
///   - `.ok(averageMs)` — todos os pings responderam, com latência média em ms
///   - `.partial(loss, averageMs)` — alguns pings caíram; `loss` em %
///   - `.failed(reason)` — nenhum eco voltou ou o comando falhou
enum PingResult: Equatable {
    case ok(averageMs: Double)
    case partial(lossPercent: Double, averageMs: Double)
    case failed(reason: String)
}

struct Pinger {
    /// Host de referência. Usar IP numérico evita tropeçar em DNS.
    /// `1.1.1.1` (Cloudflare) e `8.8.8.8` (Google) são os padrões clássicos.
    static let defaultHost = "1.1.1.1"

    /// Executa ping e devolve o resultado. Bloqueante — chame em background queue.
    /// - Parameters:
    ///   - host: IP/hostname alvo
    ///   - count: quantos pings (padrão 3)
    ///   - timeoutSeconds: timeout por ping em segundos (padrão 2)
    ///   - boundInterface: BSD name da interface (ex.: "en0"). Se `nil`, usa a rota default.
    static func ping(
        host: String = defaultHost,
        count: Int = 3,
        timeoutSeconds: Int = 2,
        boundInterface: String? = nil
    ) -> PingResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")

        var args = ["-c", "\(count)", "-W", "\(timeoutSeconds * 1000)", "-q"]
        if let bsd = boundInterface, !bsd.isEmpty {
            args.append(contentsOf: ["-b", bsd])
        }
        args.append(host)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failed(reason: "falha ao executar ping: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && output.isEmpty {
            let reason = errOutput.isEmpty ? "exit \(process.terminationStatus)" : errOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(reason: reason)
        }

        // Parse das linhas finais do ping:
        //   "3 packets transmitted, 3 packets received, 0.0% packet loss"
        //   "round-trip min/avg/max/stddev = 8.123/9.456/10.789/1.234 ms"
        guard let loss = parseLossPercent(output),
              let avg = parseAverageLatency(output)
        else {
            // Sem nenhuma resposta recebida — totalmente caído
            if output.contains("100.0% packet loss") || output.contains("100% packet loss") {
                return .failed(reason: "100% de perda")
            }
            return .failed(reason: "saída de ping inesperada")
        }

        if loss <= 0.01 {
            return .ok(averageMs: avg)
        } else if loss < 100 {
            return .partial(lossPercent: loss, averageMs: avg)
        } else {
            return .failed(reason: "100% de perda")
        }
    }

    private static func parseLossPercent(_ output: String) -> Double? {
        // "X packets transmitted, Y packets received, Z.Z% packet loss"
        guard let range = output.range(of: #"(\d+(?:\.\d+)?)% packet loss"#, options: .regularExpression) else { return nil }
        let match = output[range]
        let number = match.prefix(while: { $0.isNumber || $0 == "." })
        return Double(number)
    }

    private static func parseAverageLatency(_ output: String) -> Double? {
        // "round-trip min/avg/max/stddev = 8.123/9.456/10.789/1.234 ms"
        guard let eqRange = output.range(of: "= ") else { return nil }
        let after = output[eqRange.upperBound...]
        let parts = after.split(separator: "/", maxSplits: 4)
        guard parts.count >= 2 else { return nil }
        return Double(parts[1])
    }
}
