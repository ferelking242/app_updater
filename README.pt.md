<a href="https://github.com/ferelking242/app_updater">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,50:22c55e,100:0ea5e9&height=220&section=header&text=app_updater&fontSize=76&fontColor=ffffff&animation=fadeIn&fontAlignY=35&desc=Lojas%20%C2%B7%20Releases%20do%20GitHub%20%C2%B7%20Artefatos%20de%20CI%20%C2%B7%20UI%20pr%C3%B3pria&descSize=18&descAlignY=55&descAlign=50" width="100%" alt="app_updater banner"/>
</a>

<div align="center">

[![CI](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml)
[![Release](https://github.com/ferelking242/app_updater/actions/workflows/release.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart&logoColor=white)](https://dart.dev)

[English](README.md) · [Français](README.fr.md) · [Español](README.es.md) · **Português** · [Deutsch](README.de.md)

</div>

---

`app_updater` é um pacote Flutter que responde a uma pergunta: **existe uma
versão mais nova do meu aplicativo e como instalá-la?** Ele lê a resposta em uma
loja, nas releases do GitHub, nos artefatos do GitHub Actions ou em um servidor
de publicação próprio, e mostra um diálogo nativo — ou um que você desenha por
completo.

Este fork adiciona:

| Recurso | O que entrega |
|---|---|
| **Artefatos do GitHub Actions** | Serve o APK/exe gerado pela CI sem criar uma release. |
| **Endpoint de notificação de CI** | A CI faz um `POST`; todos os apps veem a build na hora. |
| **Atualização automática** | Verificação ao iniciar, download em segundo plano e notificação com botão *Instalar*. |
| **UI por aplicativo** | Cores, cantos, logo, textos ou um widget totalmente próprio. |
| **Downloads verificados** | SHA-256, extração de arquivos e manifesto `app-update.json`. |

---

## ✨ Recursos

- Lojas: App Store, Play Store, Microsoft Store, Snap e Flathub.
- GitHub: releases **e** artefatos do Actions.
- Feed próprio: um `POST` da CI, entrega imediata.
- Auto-update: verificação ao iniciar, download em segundo plano, instalação.
- Integridade: SHA-256, tamanho e manifesto gerado pela CI.
- Localização: todos os textos são substituíveis.

## 🏗️ Arquitetura

```
app_updater/
├── lib/src/version_checker.dart      ← lojas, releases, JSON/XML + diálogos nativos
├── lib/src/update_controller.dart    ← máquina de estados (check → download → install)
├── lib/src/sources/                  ← artefatos GitHub, releases, feed CI, composto
├── lib/src/services/                 ← download HTTP, SHA-256, zip/tar
├── lib/src/ui/                       ← AppUpdaterTheme + diálogo temático
├── ci/app_updater_ci/                ← servidor de CI e CLI de publicação (Dart + shelf)
├── ci/examples/                      ← GitHub Actions, GitLab CI, CircleCI, Jenkins
└── scripts/publish-build.sh          ← publicação universal (curl + sha256sum)
```

| Camada | Tecnologia |
|---|---|
| Pacote | Flutter 3.27+, Dart 3.5+ |
| HTTP | `http` |
| Arquivos | `archive` |
| Integridade | `crypto` |
| Servidor de CI | Dart + `shelf` + `shelf_router` |

---

## 📦 Instalação

```yaml
dependencies:
  app_updater:
    git:
      url: https://github.com/ferelking242/app_updater.git
      ref: main
```

## 🚀 Começo rápido

```dart
final updater = AppUpdater.configure(
  androidPackageName: 'com.example.app',
  githubOwner: 'minha-org',
  githubRepo: 'meu-app',
  theme: const AppUpdaterTheme(accentColor: Color(0xFF22C55E)),
);

await updater.checkAndShowUpdateDialog(context);
```

Com builds de CI e atualização automática:

```dart
final controller = AppUpdateController(
  source: CiFeedSource(
    endpoint: Uri.parse('https://updates.example.com'),
    appId: 'meu-app',
  ),
  notifier: MeuServicoDeNotificacao(),
  installer: MeuInstaladorApk(),
  options: const AutoUpdateOptions(enabledByDefault: true, abi: 'arm64-v8a'),
);

await controller.checkOnLaunch();       // ao iniciar
await controller.check(manual: true);   // em Configurações
```

---

## 🛰️ Publicar de qualquer CI

```
build → app-update.json → POST dos metadados → PUT do artefato → atualização
```

1. Suba o servidor:

```bash
docker run -d -p 8080:8080 -v app_updater_data:/data \
  -e APP_UPDATER_CI_TOKEN=change-me \
  ghcr.io/ferelking242/app-updater-ci:latest
```

2. Adicione um passo na sua CI:

```bash
curl -fsSL https://raw.githubusercontent.com/ferelking242/app_updater/main/scripts/publish-build.sh -o publish-build.sh
chmod +x publish-build.sh

./publish-build.sh \
  --endpoint https://updates.example.com \
  --app meu-app \
  --file build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --version 1.4.2 --build-number "$GITHUB_RUN_NUMBER" \
  --platform android --abi arm64-v8a --write-manifest
```

3. O app consulta
`GET /v1/apps/meu-app/latest?platform=android&channel=stable`.

Exemplos prontos em [`ci/examples/`](ci/examples) e contrato completo em
[docs/CI_INTEGRATION.md](docs/CI_INTEGRATION.md).

### Sem servidor: apenas artefatos do GitHub

Use `--write-manifest` com `actions/upload-artifact`; o
`GitHubArtifactsSource` lê os artefatos pela API do GitHub. Repositórios
privados precisam de um token.

### Releases

No repositório **app_updater**, o workflow
[`Release`](.github/workflows/release.yml) roda a cada tag `v*`: analisa, testa,
valida `dart pub publish --dry-run`, anexa o `.tar.gz` e publica a imagem do
servidor no GHCR.

---

## 🎨 Seu aplicativo, sua UI

```dart
AppUpdater.configure(
  theme: AppUpdaterTheme(
    accentColor: const Color(0xFF22C55E),
    backgroundColor: const Color(0xFF0D1117),
    borderRadius: BorderRadius.circular(24),
    logo: Image.asset('assets/logo.png', height: 56),
    strings: const UpdateStrings(updateButton: 'Instalar', laterButton: 'Depois'),
  ),
);
```

Precisa de mais? Passe um `builder` e controle toda a interface:
[docs/CUSTOM_UI.md](docs/CUSTOM_UI.md).

---

## 🔔 Atualização automática

| Passo | API |
|---|---|
| Ativar | `setAutoUpdateEnabled(true)` |
| Verificar ao iniciar | `checkOnLaunch()` |
| Verificar agora | `check(manual: true)` |
| Baixar | `download()` |
| Instalar | `install()` |
| Observar | `states.listen(...)` |

O app fornece a parte da plataforma (`UpdateNotifier` para a notificação com
botão **Instalar**, `UpdateInstaller` para o intent do APK). O pacote decide
*quando*, o app decide *como*. Guia completo:
[docs/AUTO_UPDATE.md](docs/AUTO_UPDATE.md).

---

## 🖥️ Plataformas

| Plataforma | Lojas | Builds diretas |
|---|---|---|
| Android | Play Store | APK |
| iOS | App Store, TestFlight | IPA |
| macOS | Mac App Store | DMG, PKG |
| Windows | Microsoft Store | EXE, MSIX |
| Linux | Snap, Flathub | AppImage, DEB, RPM, tar.gz |

---

## 📄 Licença

MIT — veja [LICENSE](LICENSE). Pacote original de
[mantreshkhurana](https://github.com/mantreshkhurana/app_updater)

<div align="center">

**Feito com ❤️ para apps que publicam sempre**

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0ea5e9,50:22c55e,100:0d1117&height=80&section=footer" width="100%" alt="Footer"/>

</div>
