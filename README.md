<a href="https://github.com/ferelking242/app_updater">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,50:0ea5e9,100:6366f1&height=220&section=header&text=app_updater&fontSize=76&fontColor=ffffff&animation=fadeIn&fontAlignY=35&desc=Store%20%C2%B7%20GitHub%20Releases%20%C2%B7%20CI%20artifacts%20%C2%B7%20Custom%20UI&descSize=18&descAlignY=55&descAlign=50" width="100%" alt="app_updater banner"/>
</a>

<div align="center">

[![CI](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml)
[![Release](https://github.com/ferelking242/app_updater/actions/workflows/release.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platforms](https://img.shields.io/badge/Android%20%C2%B7%20iOS%20%C2%B7%20Windows%20%C2%B7%20macOS%20%C2%B7%20Linux-lightgrey)](#supported-platforms)

**English** · [Français](README.fr.md) · [Español](README.es.md) · [Português](README.pt.md) · [Deutsch](README.de.md)

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=22&pause=1000&color=0EA5E9&center=true&vCenter=true&multiline=true&repeat=true&width=720&height=100&lines=Ship+updates+from+any+CI;Artifacts%2C+releases+or+stores;Your+app%2C+your+update+UI" alt="Typing SVG" />

</div>

---

`app_updater` is a Flutter package that answers one question: **is there a newer
build of my app, and how do I install it?** It reads the answer from an app
store, GitHub Releases, GitHub Actions artifacts or a self-hosted CI feed, then
shows a native dialog — or a dialog you fully design.

This fork adds what the original package could not do:

| Capability | What it means |
|---|---|
| **GitHub Actions artifacts** | Serve the APK/exe produced by your workflow, without publishing a release. |
| **CI notification endpoint** | Your CI `POST`s one build; every app sees it immediately. |
| **Auto-update** | Check on launch, download in the background, notify with an *Install* action. |
| **Per-app UI** | Colors, radius, logo, strings, or a completely custom widget. |
| **Verifiable downloads** | SHA-256 checks, archive extraction, `app-update.json` manifest. |
| **Localized README** | English, French, Spanish, Portuguese and German docs. |

---

## ✨ Features

<table>
  <tr>
    <td align="center" width="25%">
      <b>🏪 Stores</b><br/>
      <sub>App Store, Play Store, Microsoft Store, Snap, Flathub</sub>
    </td>
    <td align="center" width="25%">
      <b>🐙 GitHub</b><br/>
      <sub>Releases <i>and</i> Actions artifacts</sub>
    </td>
    <td align="center" width="25%">
      <b>🛰️ Self-hosted feed</b><br/>
      <sub>One POST from CI, instant delivery</sub>
    </td>
    <td align="center" width="25%">
      <b>🎨 Custom UI</b><br/>
      <sub>Theme it or replace the whole dialog</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <b>⚡ Auto-update</b><br/>
      <sub>Launch check, resumable download, install action</sub>
    </td>
    <td align="center">
      <b>🔐 Integrity</b><br/>
      <sub>SHA-256, manifest, size checks</sub>
    </td>
    <td align="center">
      <b>🌍 Localization</b><br/>
      <sub>Every string overridable</sub>
    </td>
    <td align="center">
      <b>🧪 Tested</b><br/>
      <sub>Unit, widget and server tests in CI</sub>
    </td>
  </tr>
</table>

---

## 🏗️ Architecture

```
app_updater/
├── lib/src/
│   ├── version_checker.dart        ← store / release / JSON / XML checks + native dialogs
│   ├── update_controller.dart      ← auto-update state machine (check → download → install)
│   ├── models/                     ← UpdateCandidate, UpdateArtifact, PreparedUpdate
│   ├── sources/                    ← GitHub artifacts, GitHub releases, CI feed, composite
│   ├── services/artifact_downloader.dart  ← HTTP download, SHA-256, zip/tar extraction
│   └── ui/                         ← AppUpdaterTheme + themed dialog
│
├── ci/app_updater_ci/              ← the CI ingest server and publisher CLI (Dart + shelf)
│   ├── bin/server.dart             ← POST /v1/apps/<app>/builds …
│   └── bin/publish.dart            ← dart run bin/publish.dart --file app.apk …
│
├── ci/examples/                    ← GitHub Actions, GitLab CI, CircleCI, Jenkins
├── scripts/publish-build.sh        ← CI-agnostic publisher (curl + sha256sum)
└── .github/workflows/              ← CI, reusable publish workflow, release pipeline
```

| Layer | Tech |
|---|---|
| Package | Flutter 3.27+, Dart 3.5+ |
| HTTP | `http` |
| Archives | `archive` (zip, tar, tar.gz, tar.xz) |
| Integrity | `crypto` (SHA-256) |
| Persistence | `shared_preferences` |
| CI server | Dart + `shelf` + `shelf_router` |
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

## 🚀 Quick start

### 1. Stores and GitHub Releases (classic)

```dart
final updater = AppUpdater.configure(
  androidPackageName: 'com.example.app',
  iosAppId: '123456789',
  githubOwner: 'my-org',
  githubRepo: 'my-app',
  checkFrequency: const Duration(days: 1),
  theme: const AppUpdaterTheme(accentColor: Color(0xFF0EA5E9)),
);

final info = await updater.checkAndShowUpdateDialog(context);
```

### 2. CI builds, with auto-update

```dart
final controller = AppUpdateController(
  source: CompositeUpdateSource([
    CiFeedSource(
      endpoint: Uri.parse('https://updates.example.com'),
      appId: 'my-app',
    ),
    GitHubArtifactsSource(
      owner: 'my-org',
      repo: 'my-app',
      workflow: 'publish.yml',
    ),
  ]),
  notifier: MyNotificationService(),
  installer: MyApkInstaller(),
  options: const AutoUpdateOptions(
    enabledByDefault: true,
    interval: Duration(hours: 6),
    downloadOnLaunch: false, // the notifier offers an explicit Download action
    abi: 'arm64-v8a',
  ),
);

// In initState, after the first frame:
await controller.checkOnLaunch();

// In Settings > About:
await controller.check(manual: true);
```

`AppUpdateController` publishes a stream of `UpdateState` values
(`checking`, `available`, `downloading`, `readyToInstall`, `installing`,
`installed`, `failed`) so a badge, a snackbar or a progress bar can follow it.

---

## 🛰️ Publish from any CI

The flow is always the same:

```
build → write app-update.json → POST build metadata → PUT artifact → app updates
```

1. **Run the server** (once, anywhere):

```bash
docker run -d --name app-updater-ci \
  -p 8080:8080 -v app_updater_data:/data \
  -e APP_UPDATER_CI_TOKEN=change-me \
  ghcr.io/ferelking242/app-updater-ci:latest
```

2. **Add one step to your CI.** The script works with any runner that has
`bash`, `curl` and `python3`:

```bash
curl -fsSL https://raw.githubusercontent.com/ferelking242/app_updater/main/scripts/publish-build.sh -o publish-build.sh
chmod +x publish-build.sh

./publish-build.sh \
  --endpoint https://updates.example.com \
  --app my-app \
  --file build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --version 1.4.2 \
  --build-number "$GITHUB_RUN_NUMBER" \
  --platform android \
  --abi arm64-v8a \
  --notes-file CHANGELOG.md \
  --write-manifest
```

Ready-to-copy pipelines:

| CI | File |
|---|---|
| GitHub Actions | [`ci/examples/github-actions.yml`](ci/examples/github-actions.yml) |
| GitHub Actions (artifact only, no server) | [`ci/examples/github-artifacts-only.yml`](ci/examples/github-artifacts-only.yml) |
| GitLab CI | [`ci/examples/gitlab-ci.yml`](ci/examples/gitlab-ci.yml) |
| CircleCI | [`ci/examples/circleci.yml`](ci/examples/circleci.yml) |
| Jenkins | [`ci/examples/Jenkinsfile`](ci/examples/Jenkinsfile) |
| Reusable workflow | [`publish-app-updater.yml`](.github/workflows/publish-app-updater.yml) |

3. **Nothing else.** The app polls
`GET /v1/apps/my-app/latest?platform=android&channel=stable` and receives:

```json
{
  "version": "1.4.2",
  "buildNumber": 168,
  "platform": "android",
  "channel": "stable",
  "releaseNotes": "Fixed the player crash",
  "artifacts": [
    {
      "name": "app-arm64-v8a-release.apk",
      "url": "/v1/apps/my-app/builds/9f2c/artifact",
      "size": 42123456,
      "sha256": "6f1c…",
      "abi": "arm64-v8a"
    }
  ]
}
```

Full contract, retention, private mode and troubleshooting:
[docs/CI_INTEGRATION.md](docs/CI_INTEGRATION.md).

### GitHub Actions artifacts without a server

Set no endpoint: `--write-manifest` writes `app-update.json` next to the build,
`upload-artifact` stores both, and `GitHubArtifactsSource` reads them through
the GitHub API. Private repositories work with a token
(`githubToken: Platform.environment['GH_TOKEN']`).

### Configure releases

Releases stay the stable channel. On the **app_updater** repository the
[`Release`](.github/workflows/release.yml) workflow runs on every `v*` tag and:

1. runs analyze and tests,
2. validates `dart pub publish --dry-run`,
3. attaches `app_updater-<version>.tar.gz` to the GitHub release,
4. publishes the CI server image to GHCR.

For your own app, tag the commit and let the publish workflow push the build:

```bash
git tag v1.4.2 && git push origin v1.4.2
```

### Version comparison, exactly

The app compares the installed `versionName` / `versionCode` with what CI
published:

| Installed | Published | Result |
| --- | --- | --- |
| `8.1.573` (code `573`) | `8.1.573` (code `573`) | up to date |
| `8.1.573` (code `573`) | `8.1.573` (code `574`) | update (same name, newer build) |
| `8.1.573` | `8.1.574` | update |
| `8.1.573` | `v8.1.573-beta.1` | up to date (suffixes ignored) |

`v` prefixes, `+build` metadata and `-beta` suffixes never make a version
newer. A dotted version is always preferred over a lone number, so
`Watchtower-8.1.573-b573-arm64-release` resolves to `8.1.573` and not to `8`.
Write `app-update.json` in CI and upload it with the build: the manifest wins
over any name-based guess. See
[docs/CI_INTEGRATION.md](docs/CI_INTEGRATION.md#5-version-comparison).

---

## 🎨 Your app, your update UI

Every app embedding `app_updater` can look different:

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
      updateButton: 'Install now',
      laterButton: 'Later',
    ),
  ),
);
```

Need more than colors? Pass a builder and own the whole surface:

```dart
theme: AppUpdaterTheme(
  builder: (context, info, actions, theme) => MyUpdateSheet(
    version: info.latestVersion!,
    notes: info.releaseNotes,
    progress: myProgress,
    onInstall: actions.onUpdate,
    onLater: actions.onLater,
  ),
),
```

See [docs/CUSTOM_UI.md](docs/CUSTOM_UI.md) for the full action list and a
complete example.

---

## 🔔 Auto-update and background install

| Step | API |
|---|---|
| Enable the feature | `await controller.setAutoUpdateEnabled(true)` |
| Check at startup | `await controller.checkOnLaunch()` |
| Manual check | `await controller.check(manual: true)` |
| Download | `await controller.download()` |
| Install | `await controller.install()` |
| Observe | `controller.states.listen(...)` |

Your app owns the platform part: `UpdateNotifier` posts the notification with
an **Install** button, `UpdateInstaller` runs the APK intent (or a silent
installer such as Shizuku/Device Owner). The package decides *when* to act, the
host decides *how*.

A complete Flutter integration — settings toggle, launch check, notification
with an install action — lives in [docs/AUTO_UPDATE.md](docs/AUTO_UPDATE.md).

---

## 🖥️ Supported platforms

| Platform | Stores | Direct builds |
|---|---|---|
| Android | Play Store | APK (release, artifact or CI feed) |
| iOS | App Store, TestFlight | IPA (TrollStore / enterprise) |
| macOS | Mac App Store | DMG, PKG |
| Windows | Microsoft Store | EXE, MSIX |
| Linux | Snap, Flathub | AppImage, DEB, RPM, tar.gz |

---

## 🛠️ Build locally

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

## 🤝 Contributing

1. Fork the repository.
2. Create a branch (`git checkout -b feat/my-feature`).
3. Run `dart format lib test` and the tests.
4. Open a pull request describing the behaviour change.

Bug reports and feature requests: [issues](https://github.com/ferelking242/app_updater/issues).

---

## 📄 License

MIT — see [LICENSE](LICENSE). Original package by
[mantreshkhurana](https://github.com/mantreshkhurana/app_updater)

---

<div align="center">

**Made with ❤️ for apps that ship often**

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:6366f1,50:0ea5e9,100:0d1117&height=80&section=footer" width="100%" alt="Footer"/>

</div>
