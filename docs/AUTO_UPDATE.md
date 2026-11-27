# Auto-update, notifications and background install

`AppUpdateController` owns the *when*. Your app owns the *how*: the notification
and the installation are two small interfaces.

---

## Wiring

```dart
late final AppUpdateController updateController;

@override
void initState() {
  super.initState();
  updateController = AppUpdateController(
    source: CompositeUpdateSource([
      CiFeedSource(
        endpoint: Uri.parse(AppConfig.updateEndpoint),
        appId: 'my-app',
      ),
      GitHubReleasesSource(owner: 'me', repo: 'my-app'),
    ]),
    notifier: AppUpdateNotifier(),
    installer: ApkUpdateInstaller(),
    options: const AutoUpdateOptions(
      enabledByDefault: false,
      interval: Duration(hours: 6),
      downloadOnLaunch: false, // the notifier offers an explicit Download action
      installWhenReady: false,
      abi: 'arm64-v8a',
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await updateController.checkOnLaunch();
  });
}
```

`checkOnLaunch` does nothing when the user disabled auto-update, and skips the
network when the last automatic check is younger than `interval`. It announces
the build through `UpdateNotifier.showUpdateAvailable`; nothing is downloaded
unless `downloadOnLaunch` is explicitly enabled or the user accepts the update.

The download folder comes from `workDir` or, when it has to be resolved at
runtime, from `workDirProvider`. A build downloaded earlier is remembered:
`pendingUpdate()` returns it, `install()` falls back to it after a restart, and
the next check keeps the state at `readyToInstall` instead of offering the
download again. `clearPrepared()` forgets it (the file stays on disk).

---

## The notifier

```dart
class AppUpdateNotifier implements UpdateNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<void> showUpdateAvailable(UpdateState state) => _show(
    'Update available',
    'Version ${state.candidate!.version} is ready to download.',
  );

  @override
  Future<void> showDownloadProgress(UpdateState state) => _show(
    'Downloading update',
    '${((state.progress ?? 0) * 100).round()} %',
    progress: state.progress,
  );

  @override
  Future<void> showReadyToInstall(UpdateState state) => _show(
    'Ready to install',
    'Tap Install to apply version ${state.prepared!.version}.',
    action: const AndroidNotificationAction(
      'install',
      'Install',
      showsUserInterface: true,
    ),
  );

  @override
  Future<void> cancel() => _plugin.cancel(42);

  @override
  Future<void> showError(UpdateState state) => _show(
    'Update failed',
    '${state.error}',
  );
}
```

Handle the action id in `onDidReceiveNotificationResponse`: call
`updateController.install()`. `install()` reports `installing`, then `installed`
or `failed`, and calls `notifier.cancel()` on success.

---

## The installer

Android needs a real intent, and it must run from the app process:

```dart
class ApkUpdateInstaller implements UpdateInstaller {
  @override
  Future<bool> canInstallInBackground() async {
    // True with a device-owner app, Shizuku or an MDM grant.
    return SilentInstallerService.instance.checkStatus() ==
        SilentInstallStatus.active;
  }

  @override
  Future<bool> install(PreparedUpdate update) async {
    if (await canInstallInBackground()) {
      return SilentInstallerService.instance.installFile(update.file.path);
    }
    await ApkInstaller.installApk(update.file.path); // system prompt
    return true;
  }
}
```

On iOS, install means opening the App Store, TestFlight or a TrollStore URL; use
`UrlUpdateInstaller` and put the URL in the manifest (`installUrl`).

---

## Settings > About

```dart
class AutoUpdateTile extends StatefulWidget {
  @override
  State<AutoUpdateTile> createState() => _AutoUpdateTileState();
}

class _AutoUpdateTileState extends State<AutoUpdateTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    updateController.isAutoUpdateEnabled().then((value) {
      if (mounted) setState(() => _enabled = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Automatic updates'),
      subtitle: const Text('Download new versions in the background'),
      value: _enabled ?? false,
      onChanged: _enabled == null
          ? null
          : (value) async {
              setState(() => _enabled = value);
              await updateController.setAutoUpdateEnabled(value);
            },
    );
  }
}
```

A "Check now" tile calls `updateController.check(manual: true)` and then
`download(installAfterDownload: true)` when the state is `available`.

---

## States

| Phase | Meaning | UI suggestion |
|---|---|---|
| `idle` | Nothing done yet | – |
| `checking` | Source queried | Spinner in the tile |
| `upToDate` | No newer build | “You are up to date” toast |
| `available` | Newer build found | Badge / banner / dialog |
| `downloading` | Download running | Progress bar (`state.progress`) |
| `readyToInstall` | File on disk | Notification with **Install** |
| `installing` | Installer started | Disable the button |
| `installed` | Installer returned true | Close the UI |
| `failed` | Network, checksum or IO error | Show `state.error` |

## Persisted keys

The controller stores its state in `SharedPreferences` under
`<preferencesPrefix>_…`:

| Key | Content |
|---|---|
| `app_updater_auto_update` | User switch |
| `app_updater_last_auto_check` | Timestamp of the last automatic check |
| `app_updater_notified_version` | Last version announced |

Pass `preferencesPrefix` to isolate several apps or several channels in the
same process.

## Security notes

* Always verify `sha256` (the downloader does it when the source publishes one).
* Prefer HTTPS endpoints and a read token for private feeds.
* An APK is code: only install files coming from your own CI or release channel.
* Silent install requires an explicit user or administrator grant; never try to
  bypass the system prompt.
