<a href="https://github.com/ferelking242/app_updater">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,50:eab308,100:dc2626&height=220&section=header&text=app_updater&fontSize=76&fontColor=ffffff&animation=fadeIn&fontAlignY=35&desc=Stores%20%C2%B7%20GitHub%20Releases%20%C2%B7%20CI-Artefakte%20%C2%B7%20Eigenes%20UI&descSize=18&descAlignY=55&descAlign=50" width="100%" alt="app_updater banner"/>
</a>

<div align="center">

[![CI](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml)
[![Release](https://github.com/ferelking242/app_updater/actions/workflows/release.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart&logoColor=white)](https://dart.dev)

[English](README.md) · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt.md) · **Deutsch**

</div>

---

`app_updater` ist ein Flutter-Paket mit einer einzigen Aufgabe: **Gibt es eine
neuere Version meiner App, und wie installiere ich sie?** Die Antwort kommt aus
einem Store, aus GitHub Releases, aus GitHub-Actions-Artefakten oder aus einem
selbst gehosteten CI-Server. Angezeigt wird ein nativer Dialog — oder eine
Oberfläche, die du komplett selbst gestaltest.

Dieser Fork ergänzt:

| Funktion | Nutzen |
|---|---|
| **GitHub-Actions-Artefakte** | APK/EXE direkt aus dem Workflow ausliefern, ohne Release. |
| **CI-Benachrichtigungs-Endpoint** | Ein `POST` aus der CI, alle Apps sehen den Build sofort. |
| **Auto-Update** | Prüfung beim Start, Download im Hintergrund, Benachrichtigung mit *Installieren*. |
| **UI pro App** | Farben, Radien, Logo, Texte oder ein vollständig eigenes Widget. |
| **Geprüfte Downloads** | SHA-256, Archiv-Entpackung, `app-update.json`-Manifest. |

---

## ✨ Funktionen

- Stores: App Store, Play Store, Microsoft Store, Snap und Flathub.
- GitHub: Releases **und** Actions-Artefakte.
- Eigener Feed: ein `POST` aus der CI, sofort verfügbar.
- Auto-Update: Prüfung beim Start, Hintergrund-Download, Installation.
- Integrität: SHA-256, Größe und von der CI erzeugtes Manifest.
- Lokalisierung: alle Texte ersetzbar.

## 🏗️ Architektur

```
app_updater/
├── lib/src/version_checker.dart      ← Stores, Releases, JSON/XML + native Dialoge
├── lib/src/update_controller.dart    ← Zustandsautomat (check → download → install)
├── lib/src/sources/                  ← GitHub-Artefakte, Releases, CI-Feed, Composite
├── lib/src/services/                 ← HTTP-Download, SHA-256, zip/tar
├── lib/src/ui/                       ← AppUpdaterTheme + thematischer Dialog
├── ci/app_updater_ci/                ← CI-Server und Publish-CLI (Dart + shelf)
├── ci/examples/                      ← GitHub Actions, GitLab CI, CircleCI, Jenkins
└── scripts/publish-build.sh          ← universelles Publishing (curl + sha256sum)
```

| Schicht | Technik |
|---|---|
| Paket | Flutter 3.27+, Dart 3.5+ |
| HTTP | `http` |
| Archive | `archive` |
| Integrität | `crypto` |
| CI-Server | Dart + `shelf` + `shelf_router` |

---

## 📦 Installation

```yaml
dependencies:
  app_updater:
    git:
      url: https://github.com/ferelking242/app_updater.git
      ref: main
```

## 🚀 Schnellstart

```dart
final updater = AppUpdater.configure(
  androidPackageName: 'com.example.app',
  githubOwner: 'meine-org',
  githubRepo: 'meine-app',
  theme: const AppUpdaterTheme(accentColor: Color(0xFFEAB308)),
);

await updater.checkAndShowUpdateDialog(context);
```

Mit CI-Builds und Auto-Update:

```dart
final controller = AppUpdateController(
  source: CiFeedSource(
    endpoint: Uri.parse('https://updates.example.com'),
    appId: 'meine-app',
  ),
  notifier: MeinBenachrichtigungsdienst(),
  installer: MeinApkInstaller(),
  options: const AutoUpdateOptions(enabledByDefault: true, abi: 'arm64-v8a'),
);

await controller.checkOnLaunch();      // beim Start
await controller.check(manual: true);  // in den Einstellungen
```

---

## 🛰️ Aus jeder CI veröffentlichen

```
build → app-update.json → POST der Metadaten → PUT des Artefakts → Update
```

1. Server starten:

```bash
docker run -d -p 8080:8080 -v app_updater_data:/data \
  -e APP_UPDATER_CI_TOKEN=change-me \
  ghcr.io/ferelking242/app-updater-ci:latest
```

2. Einen Schritt in der CI ergänzen:

```bash
curl -fsSL https://raw.githubusercontent.com/ferelking242/app_updater/main/scripts/publish-build.sh -o publish-build.sh
chmod +x publish-build.sh

./publish-build.sh \
  --endpoint https://updates.example.com \
  --app meine-app \
  --file build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --version 1.4.2 --build-number "$GITHUB_RUN_NUMBER" \
  --platform android --abi arm64-v8a --write-manifest
```

3. Die App fragt
`GET /v1/apps/meine-app/latest?platform=android&channel=stable` ab.

Vorlagen in [`ci/examples/`](ci/examples), vollständiger Vertrag in
[docs/CI_INTEGRATION.md](docs/CI_INTEGRATION.md).

### Ohne Server: nur GitHub-Artefakte

`--write-manifest` plus `actions/upload-artifact`; `GitHubArtifactsSource` liest
die Artefakte über die GitHub-API. Private Repositories brauchen ein Token.

### Releases

Im Repository **app_updater** läuft der
[`Release`](.github/workflows/release.yml)-Workflow bei jedem `v*`-Tag: Analyse,
Tests, `dart pub publish --dry-run`, `.tar.gz` an das Release hängen und das
CI-Server-Image nach GHCR veröffentlichen.

---

## 🎨 Deine App, dein Update-UI

```dart
AppUpdater.configure(
  theme: AppUpdaterTheme(
    accentColor: const Color(0xFFEAB308),
    backgroundColor: const Color(0xFF0D1117),
    borderRadius: BorderRadius.circular(24),
    logo: Image.asset('assets/logo.png', height: 56),
    strings: const UpdateStrings(updateButton: 'Installieren', laterButton: 'Später'),
  ),
);
```

Mehr Kontrolle? Ein `builder` ersetzt die komplette Oberfläche:
[docs/CUSTOM_UI.md](docs/CUSTOM_UI.md).

---

## 🔔 Auto-Update

| Schritt | API |
|---|---|
| Aktivieren | `setAutoUpdateEnabled(true)` |
| Beim Start prüfen | `checkOnLaunch()` |
| Jetzt prüfen | `check(manual: true)` |
| Herunterladen | `download()` |
| Installieren | `install()` |
| Beobachten | `states.listen(...)` |

Die App liefert den Plattformteil (`UpdateNotifier` für die Benachrichtigung mit
**Installieren**-Button, `UpdateInstaller` für den APK-Intent). Das Paket
entscheidet *wann*, die App entscheidet *wie*. Komplette Anleitung:
[docs/AUTO_UPDATE.md](docs/AUTO_UPDATE.md).

---

## 🖥️ Plattformen

| Plattform | Stores | Direkte Builds |
|---|---|---|
| Android | Play Store | APK |
| iOS | App Store, TestFlight | IPA |
| macOS | Mac App Store | DMG, PKG |
| Windows | Microsoft Store | EXE, MSIX |
| Linux | Snap, Flathub | AppImage, DEB, RPM, tar.gz |

---

## 📄 Lizenz

MIT — siehe [LICENSE](LICENSE). Originalpaket von
[mantreshkhurana](https://github.com/mantreshkhurana/app_updater)

<div align="center">

**Mit ❤️ für Apps, die oft ausliefern**

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:dc2626,50:eab308,100:0d1117&height=80&section=footer" width="100%" alt="Footer"/>

</div>
