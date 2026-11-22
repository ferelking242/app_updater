<a href="https://github.com/ferelking242/app_updater">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,50:ff6b35,100:ff2e63&height=220&section=header&text=app_updater&fontSize=76&fontColor=ffffff&animation=fadeIn&fontAlignY=35&desc=Stores%20%C2%B7%20Releases%20GitHub%20%C2%B7%20Artefacts%20CI%20%C2%B7%20UI%20sur%20mesure&descSize=18&descAlignY=55&descAlign=50" width="100%" alt="app_updater banner"/>
</a>

<div align="center">

[![CI](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml)
[![Release](https://github.com/ferelking242/app_updater/actions/workflows/release.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart&logoColor=white)](https://dart.dev)

[English](README.md) · **Français** · [Español](README.es.md) · [Português](README.pt.md) · [Deutsch](README.de.md)

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=22&pause=1000&color=FF6B35&center=true&vCenter=true&multiline=true&repeat=true&width=720&height=100&lines=Des+mises+%C3%A0+jour+depuis+n%27importe+quelle+CI;Artefacts%2C+releases+ou+stores;Ton+app%2C+ton+UI+de+mise+%C3%A0+jour" alt="Typing SVG" />

</div>

---

`app_updater` est un paquet Flutter qui répond à une question : **existe-t-il une
version plus récente de mon application, et comment l'installer ?** Il lit la
réponse dans un store, dans les releases GitHub, dans les artefacts GitHub
Actions ou dans un serveur de publication auto-hébergé, puis affiche une boîte
de dialogue native — ou une interface que tu dessines entièrement.

Cette version (fork de `mantreshkhurana/app_updater`) ajoute :

| Capacité | Ce que ça change |
|---|---|
| **Artefacts GitHub Actions** | Servir l'APK/exe produit par la CI, sans créer de release. |
| **Endpoint de notification CI** | La CI envoie un `POST` ; toutes les apps voient la build immédiatement. |
| **Mise à jour automatique** | Vérification au lancement, téléchargement en arrière-plan, notification avec bouton *Installer*. |
| **UI par application** | Couleurs, arrondis, logo, textes — ou un widget entièrement personnalisé. |
| **Téléchargements vérifiés** | SHA-256, extraction d'archive, manifeste `app-update.json`. |
| **README localisé** | Anglais, français, espagnol, portugais et allemand. |

---

## ✨ Fonctionnalités

<table>
  <tr>
    <td align="center" width="25%">
      <b>🏪 Stores</b><br/>
      <sub>App Store, Play Store, Microsoft Store, Snap, Flathub</sub>
    </td>
    <td align="center" width="25%">
      <b>🐙 GitHub</b><br/>
      <sub>Releases <i>et</i> artefacts Actions</sub>
    </td>
    <td align="center" width="25%">
      <b>🛰️ Flux auto-hébergé</b><br/>
      <sub>Un POST depuis la CI, diffusion immédiate</sub>
    </td>
    <td align="center" width="25%">
      <b>🎨 UI sur mesure</b><br/>
      <sub>Thème ou dialogue complet</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <b>⚡ Auto-update</b><br/>
      <sub>Vérification au lancement, téléchargement, installation</sub>
    </td>
    <td align="center">
      <b>🔐 Intégrité</b><br/>
      <sub>SHA-256, manifeste, taille</sub>
    </td>
    <td align="center">
      <b>🌍 Localisation</b><br/>
      <sub>Tous les textes remplaçables</sub>
    </td>
    <td align="center">
      <b>🧪 Testé</b><br/>
      <sub>Tests unitaires, widgets et serveur</sub>
    </td>
  </tr>
</table>

---

## 🏗️ Architecture

```
app_updater/
├── lib/src/
│   ├── version_checker.dart        ← stores, releases, JSON/XML + dialogues natifs
│   ├── update_controller.dart      ← machine à états auto-update (check → download → install)
│   ├── models/                     ← UpdateCandidate, UpdateArtifact, PreparedUpdate
│   ├── sources/                    ← artefacts GitHub, releases, flux CI, composite
│   ├── services/artifact_downloader.dart  ← HTTP, SHA-256, extraction zip/tar
│   └── ui/                         ← AppUpdaterTheme + dialogue thématisé
│
├── ci/app_updater_ci/              ← serveur d'ingestion CI et CLI de publication (Dart + shelf)
├── ci/examples/                    ← GitHub Actions, GitLab CI, CircleCI, Jenkins
├── scripts/publish-build.sh        ← publication universelle (curl + sha256sum)
└── .github/workflows/              ← CI, workflow réutilisable, pipeline de release
```

| Couche | Techno |
|---|---|
| Paquet | Flutter 3.27+, Dart 3.5+ |
| HTTP | `http` |
| Archives | `archive` (zip, tar, tar.gz, tar.xz) |
| Intégrité | `crypto` (SHA-256) |
| Persistance | `shared_preferences` |
| Serveur CI | Dart + `shelf` + `shelf_router` |
| CI | GitHub Actions |

---

## 📦 Installation

```yaml
dependencies:
  app_updater:
    git:
      url: https://github.com/ferelking242/app_updater.git
      ref: main
```

```dart
import 'package:app_updater/app_updater.dart';
```

## 🚀 Démarrage rapide

### 1. Stores et releases GitHub

```dart
final updater = AppUpdater.configure(
  androidPackageName: 'com.example.app',
  iosAppId: '123456789',
  githubOwner: 'mon-org',
  githubRepo: 'mon-app',
  checkFrequency: const Duration(days: 1),
  theme: const AppUpdaterTheme(accentColor: Color(0xFFFF6B35)),
);

final info = await updater.checkAndShowUpdateDialog(context);
```

### 2. Builds de CI avec mise à jour automatique

```dart
final controller = AppUpdateController(
  source: CompositeUpdateSource([
    CiFeedSource(
      endpoint: Uri.parse('https://updates.example.com'),
      appId: 'mon-app',
    ),
    GitHubArtifactsSource(
      owner: 'mon-org',
      repo: 'mon-app',
      workflow: 'publish.yml',
    ),
  ]),
  notifier: MonServiceDeNotification(),
  installer: MonInstallateurApk(),
  options: const AutoUpdateOptions(
    enabledByDefault: true,
    interval: Duration(hours: 6),
    downloadOnLaunch: true,
    abi: 'arm64-v8a',
  ),
);

// Dans initState, après la première frame :
await controller.checkOnLaunch();

// Dans Réglages > À propos :
await controller.check(manual: true);
```

`AppUpdateController` expose un flux d'états (`checking`, `available`,
`downloading`, `readyToInstall`, `installing`, `installed`, `failed`) : badge,
snackbar ou barre de progression peuvent le suivre.

---

## 🛰️ Publier depuis n'importe quelle CI

Le principe est toujours le même :

```
build → écrire app-update.json → POST des métadonnées → PUT de l'artefact → mise à jour
```

1. **Lancer le serveur** (une seule fois, n'importe où) :

```bash
docker run -d --name app-updater-ci \
  -p 8080:8080 -v app_updater_data:/data \
  -e APP_UPDATER_CI_TOKEN=change-me \
  ghcr.io/ferelking242/app-updater-ci:latest
```

2. **Ajouter une étape à ta CI.** Le script fonctionne partout où `bash`,
`curl` et `python3` sont disponibles :

```bash
curl -fsSL https://raw.githubusercontent.com/ferelking242/app_updater/main/scripts/publish-build.sh -o publish-build.sh
chmod +x publish-build.sh

./publish-build.sh \
  --endpoint https://updates.example.com \
  --app mon-app \
  --file build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --version 1.4.2 \
  --build-number "$GITHUB_RUN_NUMBER" \
  --platform android \
  --abi arm64-v8a \
  --notes-file CHANGELOG.md \
  --write-manifest
```

Pipelines prêtes à copier :

| CI | Fichier |
|---|---|
| GitHub Actions | [`ci/examples/github-actions.yml`](ci/examples/github-actions.yml) |
| GitHub Actions (artefacts seuls, sans serveur) | [`ci/examples/github-artifacts-only.yml`](ci/examples/github-artifacts-only.yml) |
| GitLab CI | [`ci/examples/gitlab-ci.yml`](ci/examples/gitlab-ci.yml) |
| CircleCI | [`ci/examples/circleci.yml`](ci/examples/circleci.yml) |
| Jenkins | [`ci/examples/Jenkinsfile`](ci/examples/Jenkinsfile) |
| Workflow réutilisable | [`publish-app-updater.yml`](.github/workflows/publish-app-updater.yml) |

3. **Rien d'autre.** L'application interroge
`GET /v1/apps/mon-app/latest?platform=android&channel=stable` et reçoit :

```json
{
  "version": "1.4.2",
  "buildNumber": 168,
  "platform": "android",
  "channel": "stable",
  "releaseNotes": "Correction du plantage du lecteur",
  "artifacts": [
    {
      "name": "app-arm64-v8a-release.apk",
      "url": "/v1/apps/mon-app/builds/9f2c/artifact",
      "size": 42123456,
      "sha256": "6f1c…",
      "abi": "arm64-v8a"
    }
  ]
}
```

Contrat complet, rétention, mode privé et dépannage :
[docs/CI_INTEGRATION.md](docs/CI_INTEGRATION.md).

### Artefacts GitHub Actions sans serveur

Sans `--endpoint`, `--write-manifest` écrit `app-update.json` à côté du fichier,
`upload-artifact` stocke les deux, et `GitHubArtifactsSource` les lit via l'API
GitHub. Les dépôts privés fonctionnent avec un token
(`githubToken: Platform.environment['GH_TOKEN']`).

### Configurer les releases

Les releases restent le canal stable. Sur le dépôt **app_updater**, le workflow
[`Release`](.github/workflows/release.yml) s'exécute à chaque tag `v*` et :

1. lance l'analyse et les tests,
2. valide `dart pub publish --dry-run`,
3. attache `app_updater-<version>.tar.gz` à la release GitHub,
4. publie l'image du serveur CI sur GHCR.

Pour ton application, tague le commit et laisse le workflow publier la build :

```bash
git tag v1.4.2 && git push origin v1.4.2
```

### Comparaison des versions, au détail près

L'app compare le `versionName` / `versionCode` installé avec ce que la CI a
publié :

| Installé | Publié | Résultat |
| --- | --- | --- |
| `8.1.573` (code `573`) | `8.1.573` (code `573`) | à jour |
| `8.1.573` (code `573`) | `8.1.573` (code `574`) | mise à jour (même nom, build plus récent) |
| `8.1.573` | `8.1.574` | mise à jour |
| `8.1.573` | `v8.1.573-beta.1` | à jour (suffixes ignorés) |

Le préfixe `v`, les métadonnées `+build` et les suffixes `-beta` ne rendent
jamais une version plus récente. Une version pointée est toujours préférée à un
nombre isolé : `Watchtower-8.1.573-b573-arm64-release` donne `8.1.573`, pas `8`.
Écrivez `app-update.json` dans la CI et envoyez-le avec la build : le manifeste
prime sur toute déduction depuis le nom. Voir
[docs/CI_INTEGRATION.md](docs/CI_INTEGRATION.md#5-version-comparison).

---

## 🎨 Ton application, ton UI

Chaque application qui utilise `app_updater` peut avoir sa propre identité :

```dart
AppUpdater.configure(
  theme: AppUpdaterTheme(
    accentColor: const Color(0xFFFF6B35),
    backgroundColor: const Color(0xFF0D1117),
    surfaceColor: const Color(0xFF161B22),
    foregroundColor: Colors.white,
    borderRadius: BorderRadius.circular(24),
    logo: Image.asset('assets/logo.png', height: 56),
    strings: const UpdateStrings(
      updateButton: 'Installer',
      laterButton: 'Plus tard',
    ),
  ),
);
```

Besoin de plus que des couleurs ? Fournis un builder et garde le contrôle total :

```dart
theme: AppUpdaterTheme(
  builder: (context, info, actions, theme) => MaFeuilleDeMiseAJour(
    version: info.latestVersion!,
    notes: info.releaseNotes,
    progress: maProgression,
    onInstall: actions.onUpdate,
    onLater: actions.onLater,
  ),
),
```

Voir [docs/CUSTOM_UI.md](docs/CUSTOM_UI.md) pour la liste complète des actions.

---

## 🔔 Auto-update et installation en arrière-plan

| Étape | API |
|---|---|
| Activer | `await controller.setAutoUpdateEnabled(true)` |
| Vérifier au lancement | `await controller.checkOnLaunch()` |
| Vérifier manuellement | `await controller.check(manual: true)` |
| Télécharger | `await controller.download()` |
| Installer | `await controller.install()` |
| Observer | `controller.states.listen(...)` |

L'application fournit la partie plateforme : `UpdateNotifier` affiche la
notification avec le bouton **Installer**, `UpdateInstaller` lance l'intent APK
(ou un installateur silencieux type Shizuku/Device Owner). Le paquet décide
*quand* agir, l'application décide *comment*.

Intégration Flutter complète — réglage, vérification au lancement, notification
avec action d'installation : [docs/AUTO_UPDATE.md](docs/AUTO_UPDATE.md).

---

## 🖥️ Plateformes

| Plateforme | Stores | Builds directes |
|---|---|---|
| Android | Play Store | APK (release, artefact ou flux CI) |
| iOS | App Store, TestFlight | IPA (TrollStore / entreprise) |
| macOS | Mac App Store | DMG, PKG |
| Windows | Microsoft Store | EXE, MSIX |
| Linux | Snap, Flathub | AppImage, DEB, RPM, tar.gz |

---

## 🛠️ Compiler en local

```bash
git clone https://github.com/ferelking242/app_updater.git
cd app_updater

flutter pub get
flutter test
flutter analyze

cd ci/app_updater_ci
dart pub get
dart test
dart run bin/server.dart --port 8080 --token dev
```

---

## 🤝 Contribuer

1. Forke le dépôt.
2. Crée une branche (`git checkout -b feat/ma-fonctionnalite`).
3. Lance `dart format lib test` et les tests.
4. Ouvre une pull request qui décrit le changement de comportement.

Rapports de bug et idées : [issues](https://github.com/ferelking242/app_updater/issues).

---

## 📄 Licence

MIT — voir [LICENSE](LICENSE). Paquet original par
[mantreshkhurana](https://github.com/mantreshkhurana/app_updater)

---

<div align="center">

**Fait avec ❤️ pour les applications qui livrent souvent**

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:ff2e63,50:ff6b35,100:0d1117&height=80&section=footer" width="100%" alt="Footer"/>

</div>
