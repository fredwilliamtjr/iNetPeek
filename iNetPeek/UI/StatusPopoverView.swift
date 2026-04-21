import SwiftUI

struct StatusPopoverView: View {
    @EnvironmentObject var store: FailoverStore
    @EnvironmentObject var registry: InterfaceRegistry

    let onOpenPreferences: () -> Void
    let onForceInterface: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.manualOverrideServiceID != nil {
                manualBanner
            }
            Divider()
            interfaceList
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    private var manualBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Modo manual ativo")
                    .font(.callout.weight(.medium))
                Text("O failover automático está pausado")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Voltar ao automático") {
                onForceInterface(nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack {
            Text("iNetPeek")
                .font(.headline)
            Spacer()
            // Evito .toggleStyle(.switch) aqui porque ele crasha dentro de NSPanel no
            // macOS 26 Tahoe (Metal getCStringForCFString recebe NSNumber). O checkbox
            // funciona sem problema; o .switch fica reservado para a janela de Preferências,
            // que é uma NSWindow normal.
            Toggle("Failover automático", isOn: $store.autoFailoverEnabled)
                .toggleStyle(.checkbox)
                .help("Desativar para só observar, sem mexer nas interfaces")
        }
    }

    private var interfaceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if registry.monitoredInOrder.isEmpty {
                Text("Nenhuma interface configurada.\nAbra as Preferências para escolher quais monitorar.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(Array(registry.monitoredInOrder.enumerated()), id: \.element.id) { index, iface in
                    row(index: index, iface: iface)
                }
            }
        }
    }

    private func row(index: Int, iface: NetworkInterfaceInfo) -> some View {
        let health = store.health[iface.serviceID] ?? .unknown
        let isActive = store.activeServiceID == iface.serviceID
        let isOverridden = store.manualOverrideServiceID == iface.serviceID

        return HStack(spacing: 10) {
            Image(systemName: iface.hardwareType.sfSymbolName)
                .frame(width: 22)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(iface.displayName)
                        .font(.system(.body, design: .default).weight(isActive ? .semibold : .regular))
                    if index == 0 {
                        Text("preferencial")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if isOverridden {
                        Text("manual")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(health.label)
                    .font(.caption)
                    .foregroundStyle(color(for: health))
            }
            Spacer()
            // Botão "Usar esta" aparece quando a interface NÃO é a ativa atual.
            // Clicar força o modo manual nela.
            if !isActive {
                Button {
                    onForceInterface(iface.serviceID)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Usar esta conexão agora (modo manual)")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func color(for health: InterfaceHealth) -> Color {
        switch health {
        case .healthy: return .green
        case .degraded: return .orange
        case .down, .disabled: return .red
        case .unknown: return .secondary
        }
    }

    private var footer: some View {
        HStack {
            if let event = store.lastEvent {
                Text(event)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Preferências…") { onOpenPreferences() }
                .keyboardShortcut(",", modifiers: .command)
            Button("Sair") { NSApp.terminate(nil) }
        }
    }
}
