import Foundation
import Network

/// Motor principal do iNetPeek. A cada X segundos:
///   1. Lê a lista de interfaces monitoradas (em ordem de prioridade) do `InterfaceRegistry`.
///   2. Para cada uma, roda um `Pinger.ping(boundInterface:)` para medir saúde real.
///   3. Decide qual deveria estar ativa (a de maior prioridade com saúde ok).
///   4. Se o usuário habilitou auto-failover e a escolha mudou, desativa as de prioridade
///      maior que falharam e garante que a escolhida esteja ativa.
///
/// A lógica de "desligar a interface ruim" força o macOS a usar a próxima na ordem de
/// serviços — é o truque que resolve o problema do "link físico ok mas internet caiu".
final class FailoverMonitor {
    private let store: FailoverStore
    private var timer: DispatchSourceTimer?
    private var probationTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.smartfull.inetpeek.monitor", qos: .utility)
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "com.smartfull.inetpeek.path")

    /// Conjunto de serviceIDs que o PRÓPRIO iNetPeek desativou (por causa de failover).
    /// Serve pra:
    ///   1. Sabermos quais religar na reavaliação periódica.
    ///   2. NÃO mexer em interfaces que o usuário desativou manualmente (fora do app) —
    ///      se não está no set, a gente não toca.
    /// Acessado só pela `queue` do monitor.
    private var disabledByUs: Set<String> = []

    /// Intervalo entre verificações. 10s é um bom começo — não sobrecarrega e reage rápido.
    var checkInterval: TimeInterval = 10

    /// Intervalo da reavaliação periódica: religa temporariamente as interfaces que o
    /// iNetPeek desativou, pra o tick normal poder re-medir a saúde delas. Se a preferencial
    /// tiver voltado, o failover vai trocar de volta automaticamente. Se ainda estiverem
    /// ruins, o próximo tick as desativa de novo.
    var probationInterval: TimeInterval = 60

    init(store: FailoverStore) {
        self.store = store
    }

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            // Sempre que o macOS notifica mudança de caminho, força uma verificação imediata.
            self?.queue.async { self?.tick() }
        }
        pathMonitor.start(queue: pathQueue)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: checkInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer

        // Reavaliação periódica: religa interfaces que nós desativamos pra re-medir saúde.
        let probation = DispatchSource.makeTimerSource(queue: queue)
        probation.schedule(deadline: .now() + probationInterval, repeating: probationInterval)
        probation.setEventHandler { [weak self] in self?.probationTick() }
        probation.resume()
        self.probationTimer = probation
    }

    func stop() {
        pathMonitor.cancel()
        timer?.cancel()
        probationTimer?.cancel()
        timer = nil
        probationTimer = nil
    }

    /// Força uma interface específica como ativa (ou libera, passando `nil`).
    /// Quando um override está ativo, o auto-failover pausa — o monitor só observa.
    ///
    /// - Passar `nil` limpa o override e reativa todas as interfaces monitoradas que
    ///   estavam desligadas (pra voltar ao comportamento automático).
    /// - Passar um serviceID: habilita essa interface e desabilita as demais monitoradas,
    ///   pra forçar o macOS a rotear por ela.
    func forceInterface(_ serviceID: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            let monitored = DispatchQueue.main.sync {
                InterfaceRegistry.shared.monitoredInOrder
            }
            if let serviceID, let target = monitored.first(where: { $0.serviceID == serviceID }) {
                // Desliga todas as outras e liga o target
                for iface in monitored where iface.serviceID != serviceID {
                    try? InterfaceToggler.setEnabled(false, for: iface)
                }
                try? InterfaceToggler.setEnabled(true, for: target)
                DispatchQueue.main.async {
                    self.store.manualOverrideServiceID = serviceID
                    self.store.setActive(serviceID)
                    self.store.logEvent("Modo manual → \(target.displayName)")
                }
            } else {
                // Limpa override: religa TODAS as monitoradas pra o auto-failover poder
                // escolher livremente na próxima passagem.
                for iface in monitored {
                    try? InterfaceToggler.setEnabled(true, for: iface)
                }
                self.disabledByUs.removeAll()
                DispatchQueue.main.async {
                    self.store.manualOverrideServiceID = nil
                    self.store.logEvent("Modo automático restaurado")
                }
                // Força uma verificação imediata pra redecidir
                self.queue.async { self.tick() }
            }
        }
    }

    // MARK: - Loop principal

    private func tick() {
        let monitored = DispatchQueue.main.sync {
            InterfaceRegistry.shared.monitoredInOrder
        }

        guard !monitored.isEmpty else {
            DispatchQueue.main.async {
                self.store.updateHealth([:])
                self.store.setActive(nil)
            }
            return
        }

        // Mede saúde de cada interface em paralelo (mas esperamos todas antes de decidir).
        var newHealth: [String: InterfaceHealth] = [:]
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "inetpeek.health.sync")

        for iface in monitored {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let result = Pinger.ping(boundInterface: iface.bsdName)
                let health = Self.translate(pingResult: result)
                syncQueue.sync {
                    newHealth[iface.serviceID] = health
                }
                group.leave()
            }
        }
        group.wait()

        // Decide quem deveria estar ativa: primeira da lista cuja saúde é .healthy.
        let preferred = monitored.first(where: { newHealth[$0.serviceID]?.isUsable == true })

        let (autoEnabled, currentlyActive, override) = DispatchQueue.main.sync {
            (store.autoFailoverEnabled, store.activeServiceID, store.manualOverrideServiceID)
        }

        DispatchQueue.main.async {
            self.store.updateHealth(newHealth)
        }

        // Se o usuário forçou uma interface manualmente, só observamos — não mexemos em nada.
        // A interface ativa exibida continua sendo o override.
        if let override {
            DispatchQueue.main.async { self.store.setActive(override) }
            return
        }

        if autoEnabled, let preferred, preferred.serviceID != currentlyActive {
            applyFailover(to: preferred, among: monitored, health: newHealth)
        } else if preferred == nil {
            DispatchQueue.main.async {
                self.store.logEvent("Nenhuma interface monitorada está saudável")
            }
        }
    }

    /// Garante que `target` seja a interface em uso: desliga as de prioridade maior que estão
    /// com problema e liga o target (caso tenha sido desligado antes).
    private func applyFailover(
        to target: NetworkInterfaceInfo,
        among all: [NetworkInterfaceInfo],
        health: [String: InterfaceHealth]
    ) {
        // Quem está "acima" do target na prioridade e com saúde ruim → desligar.
        let higherPriority = all.prefix(while: { $0.serviceID != target.serviceID })
        for iface in higherPriority {
            let status = health[iface.serviceID] ?? .unknown
            if status.isUsable == false {
                do {
                    try InterfaceToggler.setEnabled(false, for: iface)
                    disabledByUs.insert(iface.serviceID)
                    DispatchQueue.main.async {
                        self.store.logEvent("Desativei \(iface.displayName) — \(status.label)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.store.logEvent("Falha ao desativar \(iface.displayName): \(error.localizedDescription)")
                    }
                }
            }
        }

        // Garante que o target está ligado. Como ele vai ser usado, remove do set "desligadas por nós".
        do {
            try InterfaceToggler.setEnabled(true, for: target)
            disabledByUs.remove(target.serviceID)
        } catch {
            DispatchQueue.main.async {
                self.store.logEvent("Falha ao ativar \(target.displayName): \(error.localizedDescription)")
            }
        }

        DispatchQueue.main.async {
            self.store.setActive(target.serviceID)
            self.store.logEvent("Failover → \(target.displayName)")
        }
    }

    /// Reativa interfaces que nós desativamos, pra o tick regular poder re-testar saúde.
    /// Se elas voltaram (ping passa), o `applyFailover` no próximo tick vai escolher a
    /// preferencial de novo. Se ainda estão ruins, o tick desativa novamente — o set
    /// `disabledByUs` fica igual e a gente tenta outra vez daqui a `probationInterval`.
    private func probationTick() {
        // Respeita o modo manual: não faz reavaliação enquanto o usuário está no comando.
        let (autoEnabled, override) = DispatchQueue.main.sync {
            (store.autoFailoverEnabled, store.manualOverrideServiceID)
        }
        guard autoEnabled, override == nil else { return }
        guard !disabledByUs.isEmpty else { return }

        let monitored = DispatchQueue.main.sync {
            InterfaceRegistry.shared.monitoredInOrder
        }
        let toReenable = monitored.filter { disabledByUs.contains($0.serviceID) }
        guard !toReenable.isEmpty else {
            // Limpa IDs no set que não existem mais (ex.: interface removida pelo usuário)
            let validIDs = Set(monitored.map(\.serviceID))
            disabledByUs = disabledByUs.intersection(validIDs)
            return
        }

        for iface in toReenable {
            do {
                try InterfaceToggler.setEnabled(true, for: iface)
                DispatchQueue.main.async {
                    self.store.logEvent("Reavaliando \(iface.displayName)…")
                }
            } catch {
                DispatchQueue.main.async {
                    self.store.logEvent("Falha ao religar \(iface.displayName): \(error.localizedDescription)")
                }
            }
        }
        // Esvazia o set — o próximo tick vai re-popular com as que ainda estiverem ruins.
        disabledByUs.removeAll()

        // Dá um tempinho pra interface adquirir link/DHCP antes de medir.
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.tick()
        }
    }

    private static func translate(pingResult: PingResult) -> InterfaceHealth {
        switch pingResult {
        case .ok(let ms):
            return .healthy(latencyMs: ms)
        case .partial(let loss, let ms):
            return .degraded(reason: String(format: "perda %.0f%%, %.0f ms", loss, ms))
        case .failed(let reason):
            return .down(reason: reason)
        }
    }
}
