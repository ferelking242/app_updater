<a href="https://github.com/ferelking242/app_updater">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:0d1117,50:f59e0b,100:ef4444&height=220&section=header&text=app_updater&fontSize=76&fontColor=ffffff&animation=fadeIn&fontAlignY=35&desc=Tiendas%20%C2%B7%20Releases%20de%20GitHub%20%C2%B7%20Artefactos%20CI%20%C2%B7%20UI%20propia&descSize=18&descAlignY=55&descAlign=50" width="100%" alt="app_updater banner"/>
</a>

<div align="center">

[![CI](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/ci.yml)
[![Release](https://github.com/ferelking242/app_updater/actions/workflows/release.yml/badge.svg)](https://github.com/ferelking242/app_updater/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?logo=dart&logoColor=white)](https://dart.dev)

[English](README.md) · [Français](README.fr.md) · **Español** · [Português](README.pt.md) · [Deutsch](README.de.md)

</div>

---

`app_updater` es un paquete Flutter que responde a una pregunta: **¿hay una
versión más nueva de mi aplicación y cómo la instalo?** Lee la respuesta de una
tienda, de las releases de GitHub, de los artefactos de GitHub Actions o de un
servidor de publicación propio, y muestra un diálogo nativo — o uno que tú
diseñas por completo.

Este fork añade:

| Capacidad | Qué aporta |
|---|---|
| **Artefactos de GitHub Actions** | Sirve el APK/exe generado por la CI sin crear una release. |
| **Endpoint de notificación CI** | La CI hace un `POST`; todas las apps ven la build al instante. |
| **Auto-actualización** | Comprobación al iniciar, descarga en segundo plano y notificación con botón *Instalar*. |
| **UI por aplicación** | Colores, radios, logo, textos o un widget totalmente propio. |
| **Descargas verificadas** | SHA-256, extracción de archivos y manifiesto `app-update.json`. |

---

## ✨ Funciones

- Stores: App Store, Play Store, Microsoft Store, Snap y Flathub.
- GitHub: releases **y** artefactos de Actions.
- Fuente propia: un `POST` desde la CI, entrega inmediata.
- Auto-update: comprobación al iniciar, descarga en segundo plano, instalación.
- Integridad: SHA-256, tamaño y manifiesto firmado por la CI.
- Localización: todos los textos son sustituibles.

## 🏗️ Arquitectura

```
app_updater/
├── lib/src/version_checker.dart      ← stores, releases, JSON/XML + diálogos nativos
├── lib/src/update_controller.dart    ← máquina de estados (check → download → install)
├── lib/src/sources/                  ← artefactos GitHub, releases, feed CI, compuesto
├── lib/src/services/                 ← descarga HTTP, SHA-256, zip/tar
├── lib/src/ui/                       ← AppUpdaterTheme + diálogo temático
├── ci/app_updater_ci/                ← servidor CI y CLI de publicación (Dart + shelf)
├── ci/examples/                      ← GitHub Actions, GitLab CI, CircleCI, Jenkins
└── scripts/publish-build.sh          ← publicación universal (curl + sha256sum)
```

| Capa | Tecnología |
|---|---|
| Paquete | Flutter 3.27+, Dart 3.5+ |
| HTTP | `http` |
| Archivos | `archive` |
| Integridad | `crypto` |
| Servidor CI | Dart + `shelf` + `shelf_router` |

---

## 📦 Instalación

```yaml
dependencies:
  app_updater:
    git:
      url: https://github.com/ferelking242/app_updater.git
      ref: main
```

## 🚀 Inicio rápido

```dart
final updater = AppUpdater.configure(
  androidPackageName: 'com.example.app',
  githubOwner: 'mi-org',
  githubRepo: 'mi-app',
  theme: const AppUpdaterTheme(accentColor: Color(0xFFF59E0B)),
);

await updater.checkAndShowUpdateDialog(context);
```

Con builds de CI y auto-actualización:

```dart
final controller = AppUpdateController(
  source: CiFeedSource(
    endpoint: Uri.parse('https://updates.example.com'),
    appId: 'mi-app',
  ),
  notifier: MiServicioDeNotificaciones(),
  installer: MiInstaladorApk(),
  options: const AutoUpdateOptions(enabledByDefault: true, abi: 'arm64-v8a'),
);

await controller.checkOnLaunch();          // al iniciar
await controller.check(manual: true);      // desde Ajustes
```

---

## 🛰️ Publicar desde cualquier CI

```
build → app-update.json → POST de metadatos → PUT del artefacto → actualización
```

1. Arranca el servidor:

```bash
docker run -d -p 8080:8080 -v app_updater_data:/data \
  -e APP_UPDATER_CI_TOKEN=change-me \
  ghcr.io/ferelking242/app-updater-ci:latest
```

2. Añade un paso a tu CI:

```bash
curl -fsSL https://raw.githubusercontent.com/ferelking242/app_updater/main/scripts/publish-build.sh -o publish-build.sh
chmod +x publish-build.sh

./publish-build.sh \
  --endpoint https://updates.example.com \
  --app mi-app \
  --file build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --version 1.4.2 --build-number "$GITHUB_RUN_NUMBER" \
  --platform android --abi arm64-v8a --write-manifest
```

3. La app consulta
`GET /v1/apps/mi-app/latest?platform=android&channel=stable`.

Ejemplos listos para copiar en [`ci/examples/`](ci/examples) y contrato completo
en [docs/CI_INTEGRATION.md](docs/CI_INTEGRATION.md).

### Sin servidor: solo artefactos de GitHub

Usa `--write-manifest` y `actions/upload-artifact`; `GitHubArtifactsSource` lee
los artefactos con la API de GitHub. Los repositorios privados necesitan un
token.

### Releases

En el repositorio **app_updater**, el workflow
[`Release`](.github/workflows/release.yml) se ejecuta con cada etiqueta `v*`:
analiza, prueba, valida `dart pub publish --dry-run`, adjunta el `.tar.gz` y
publica la imagen del servidor en GHCR.

---

## 🎨 Tu aplicación, tu UI

```dart
AppUpdater.configure(
  theme: AppUpdaterTheme(
    accentColor: const Color(0xFFF59E0B),
    backgroundColor: const Color(0xFF0D1117),
    borderRadius: BorderRadius.circular(24),
    logo: Image.asset('assets/logo.png', height: 56),
    strings: const UpdateStrings(updateButton: 'Instalar', laterButton: 'Más tarde'),
  ),
);
```

¿Necesitas más? Pasa un `builder` y controla toda la interfaz:
[docs/CUSTOM_UI.md](docs/CUSTOM_UI.md).

---

## 🔔 Auto-actualización

| Paso | API |
|---|---|
| Activar | `setAutoUpdateEnabled(true)` |
| Comprobar al iniciar | `checkOnLaunch()` |
| Comprobar ahora | `check(manual: true)` |
| Descargar | `download()` |
| Instalar | `install()` |
| Observar | `states.listen(...)` |

La app aporta la parte de plataforma (`UpdateNotifier` para la notificación con
botón **Instalar**, `UpdateInstaller` para el intent del APK). El paquete decide
*cuándo*, la app decide *cómo*. Guía completa:
[docs/AUTO_UPDATE.md](docs/AUTO_UPDATE.md).

---

## 🖥️ Plataformas

| Plataforma | Tiendas | Builds directas |
|---|---|---|
| Android | Play Store | APK |
| iOS | App Store, TestFlight | IPA |
| macOS | Mac App Store | DMG, PKG |
| Windows | Microsoft Store | EXE, MSIX |
| Linux | Snap, Flathub | AppImage, DEB, RPM, tar.gz |

---

## 📄 Licencia

MIT — ver [LICENSE](LICENSE). Paquete original de
[mantreshkhurana](https://github.com/mantreshkhurana/app_updater)

<div align="center">

**Hecho con ❤️ para apps que publican a menudo**

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:ef4444,50:f59e0b,100:0d1117&height=80&section=footer" width="100%" alt="Footer"/>

</div>
