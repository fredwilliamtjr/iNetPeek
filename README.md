<div align="center">
  <img src="docs/icon.png" width="160" alt="iNetPeek icon">

  <h1>iNetPeek</h1>

  <p><strong>Failover automático entre Ethernet e Wi-Fi no macOS.</strong></p>
  <p>Quando a cabeada cai — mesmo com o cabo ainda plugado — o Mac troca sozinho pra uma interface que realmente funciona.</p>

  <p>
    <img src="https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+">
    <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9">
    <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-555555?style=flat-square" alt="Apple Silicon">
    <img src="https://img.shields.io/badge/status-alpha-orange?style=flat-square" alt="alpha">
  </p>
</div>

---

## 🧭 O problema

O macOS só troca de interface de rede quando **perde link físico**. Se o cabo continua plugado mas a internet da operadora caiu, o Mac fica preso na interface ruim, recusando-se a usar o Wi-Fi que está ali, saudável, do lado. Você abre o navegador, nada carrega, e fica sem entender por quê — até desplugar o cabo manualmente.

## ✨ A solução

iNetPeek é um app de barra de menu que **pinga cada interface pelo link específico dela** (via `ping -b en0`, `ping -b en7`, etc.) pra medir a saúde *real* — independente do que o macOS acha que está funcionando. Quando a interface preferencial cai, o app desativa o serviço de rede dela, forçando o macOS a rotear tráfego pela próxima da lista. Quando a preferencial volta, o app reativa e o tráfego migra de volta.

## 🎯 Features

- 🧩 **Detecção automática** de todas as interfaces de rede (Ethernet, Wi-Fi, dock station, Thunderbolt, USB-C)
- 🎚️ **Prioridade por arrastar-e-soltar** — topo é a preferencial, os demais são fallbacks em ordem
- 💓 **Monitoramento contínuo** — ping a cada 10s em cada interface, com reavaliação automática a cada 60s das que foram desativadas
- 🖱️ **Modo manual** — forçar uma interface específica com um clique no popover (pausa o failover automático)
- 🚀 **Iniciar com o macOS** — opção nativa via `SMAppService`
- 🪶 **Discreto** — vive só na barra de menu, sem ícone no Dock
- 🔍 **Transparente** — log dos eventos visível no popover ("Failover → Wi-Fi", "Desativei Ethernet — perda 100%")

## 📦 Instalação

1. Baixe o `.dmg` da página de [Releases](https://github.com/fredwilliamtjr/iNetPeek/releases)
2. Monte o DMG e arraste o `iNetPeek.app` pra pasta **Applications**
3. Primeira abertura: clique com **botão direito → Abrir** (o Gatekeeper reclama porque o app não é assinado com Developer ID)
4. Se o macOS insistir que "o app está danificado":
   ```bash
   xattr -dr com.apple.quarantine /Applications/iNetPeek.app
   ```

> **Primeira vez que o failover disparar**, o macOS vai pedir sua senha de admin — é o `networksetup` pedindo pra ativar/desativar um serviço de rede. Autorize uma vez e ele não pede de novo enquanto a sessão estiver aberta.

## ⚙️ Como usar

1. Clique no ícone da barra de menu
2. Abra **Preferências…**
3. Escolha quais interfaces monitorar e arraste pra definir a prioridade (topo = preferencial)
4. Pronto — o failover automático já está rodando

Pra pausar o failover em algum momento (ex.: você *quer* ficar no Wi-Fi mesmo com a Ethernet disponível), clique no botão ao lado da interface no popover. Isso entra em **modo manual**. Volte ao automático clicando em "Voltar ao automático" na barra laranja.

## 🧱 Arquitetura

```
iNetPeek/
├── App/                  # Ponto de entrada + AppDelegate
├── Core/                 # Modelo de interface, registry, store, monitor de failover
├── UI/                   # Barra de menu, popover, janela de preferências
├── Utilities/            # Wrappers de ping e networksetup
└── Resources/            # Assets (ícone)
```

| Componente | Responsabilidade |
|---|---|
| `InterfaceRegistry` | Enumera interfaces via `SystemConfiguration`, persiste a escolha do usuário em `UserDefaults` |
| `FailoverMonitor` | Loop de 10s: mede cada interface com `Pinger` e aciona `InterfaceToggler` quando necessário |
| `FailoverStore` | `ObservableObject` com estado em tempo real (saúde, interface ativa, eventos recentes) |
| `Pinger` | Executa `/sbin/ping -b <bsd>` pra amarrar o ping numa interface específica |
| `InterfaceToggler` | Wrapper sobre `networksetup` — usa `-setairportpower` pra Wi-Fi, `-setnetworkserviceenabled` pros outros |
| `LaunchAtLogin` | Toggle do início automático via `SMAppService.mainApp` |

## 🔨 Build a partir do código

Requisitos:
- macOS 14.0+
- Xcode 15+
- Swift 5.9
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
git clone https://github.com/fredwilliamtjr/iNetPeek.git
cd iNetPeek
xcodegen generate
open iNetPeek.xcodeproj
```

Ou via linha de comando:

```bash
xcodebuild -project iNetPeek.xcodeproj -scheme iNetPeek -configuration Release \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

### Gerar um DMG distribuível

```bash
./scripts/create_dmg.sh    # monta dist/iNetPeek.dmg com layout "arraste pra Applications"
```

### Regerar o ícone

```bash
swift scripts/generate_icon.swift
```

## 🔒 Segurança / sandboxing

- **App Sandbox**: desligado. Necessário pra invocar `/usr/sbin/networksetup` e `/sbin/ping`.
- **Entitlement**: apenas `com.apple.security.network.client`.
- **Assinatura**: ad-hoc por padrão. Pra distribuição sem fricção de Gatekeeper, precisaria de Developer ID + notarização da Apple.
- **Privilégios**: `networksetup` pede senha de admin na primeira vez que altera um serviço de rede. Uma versão futura pode mover isso pra um helper `SMJobBless` e operar sem prompt.

## 🗺️ Roadmap

- [ ] Histórico visual de saúde por interface (gráfico simples dos últimos pings)
- [ ] Configurar host de ping por interface (hoje é só `1.1.1.1` global)
- [ ] Privileged helper via `SMJobBless` pra zerar o prompt de senha
- [ ] Notificações no Centro de Notificações a cada failover
- [ ] Localização em inglês

## 📄 Licença

TBD

---

<div align="center">
  <sub>Feito com ☕ por <a href="https://github.com/fredwilliamtjr">@fredwilliamtjr</a></sub>
</div>
