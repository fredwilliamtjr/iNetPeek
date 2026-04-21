import AppKit
import SwiftUI

/// Janela de Preferências — onde o usuário escolhe QUAIS interfaces monitorar e em
/// QUE ORDEM de prioridade. Arrastar pra reordenar; toggle por item para incluir/remover.
final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(
            rootView: PreferencesView()
                .environmentObject(InterfaceRegistry.shared)
                .environmentObject(FailoverStore.shared)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "iNetPeek — Preferências"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 620))
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

struct PreferencesView: View {
    @EnvironmentObject var registry: InterfaceRegistry
    @EnvironmentObject var store: FailoverStore
    @ObservedObject private var launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interfaces monitoradas")
                .font(.headline)
            Text("Arraste para reordenar. A interface no topo é a preferencial; as demais são fallbacks na ordem.")
                .font(.caption)
                .foregroundStyle(.secondary)

            monitoredList

            if !registry.unconfigured.isEmpty {
                Divider()
                availableSection
            }

            Spacer(minLength: 0)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Habilitar failover automático", isOn: $store.autoFailoverEnabled)
                    Spacer()
                    Button("Recarregar interfaces") { registry.refresh() }
                }
                Toggle("Iniciar com o macOS", isOn: $launchAtLogin.isEnabled)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 360)
        .onAppear { launchAtLogin.refresh() }
    }

    /// Altura dinâmica da lista de monitoradas: cada linha ~44px, cabeçalho ~28px.
    /// Mínimo 72 pra não sumir quando está vazia (mostra o placeholder do List).
    private var monitoredListHeight: CGFloat {
        let count = max(registry.monitoredInOrder.count, 1)
        return CGFloat(count) * 44 + 20
    }

    private var monitoredList: some View {
        List {
            ForEach(Array(registry.monitoredInOrder.enumerated()), id: \.element.id) { index, iface in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.monospaced())
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Image(systemName: iface.hardwareType.sfSymbolName)
                    VStack(alignment: .leading) {
                        Text(iface.displayName)
                        if let bsd = iface.bsdName {
                            Text(bsd).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        registry.removeFromMonitored(iface.serviceID)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onMove { source, destination in
                registry.moveMonitored(from: source, to: destination)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(height: monitoredListHeight)
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Disponíveis (ainda não monitoradas)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(registry.unconfigured.enumerated()), id: \.element.id) { index, iface in
                    if index > 0 { Divider() }
                    availableRow(iface)
                }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private func availableRow(_ iface: NetworkInterfaceInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iface.hardwareType.sfSymbolName)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(iface.displayName)
                if let bsd = iface.bsdName {
                    Text(bsd).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                registry.addToMonitored(iface.serviceID)
            } label: {
                Label("Monitorar", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
