# Custom update UI

`app_updater` never forces its own look on your app. Three levels of control
exist, from a color change to a fully hand-written screen.

---

## 1. Theme the built-in dialog

```dart
final updater = AppUpdater.configure(
  githubOwner: 'me',
  githubRepo: 'my-app',
  theme: AppUpdaterTheme(
    accentColor: const Color(0xFFFF6B35),
    backgroundColor: const Color(0xFF0D1117),
    surfaceColor: const Color(0xFF161B22),
    foregroundColor: Colors.white,
    mutedColor: Colors.white70,
    borderColor: Colors.white12,
    borderRadius: BorderRadius.circular(24),
    padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
    maxWidth: 420,
    fontFamily: 'Inter',
    titleStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
    logo: Image.asset('assets/logo.png', height: 56),
    showVersionPills: true,
    showReleaseNotes: true,
    showSize: true,
    strings: const UpdateStrings(
      updateButton: 'Install now',
      laterButton: 'Later',
      skipVersionButton: 'Skip this version',
      doNotAskAgainButton: "Don't remind me",
    ),
  ),
);
```

`UpdateStrings` covers every label: title, message template with
`{currentVersion}` / `{latestVersion}`, buttons, release-notes heading, error
text.

The themed dialog replaces the Material, Cupertino, Fluent and Adwaita dialogs
whenever `theme` is set. Removing it restores the platform-native look.

---

## 2. Use the themed dialog directly

```dart
await showDialog<void>(
  context: context,
  builder: (_) => AppUpdaterUpdateDialog(
    theme: const AppUpdaterTheme(accentColor: Colors.teal),
    info: info,
    title: 'Update ready',
    message: 'Version ${info.latestVersion} is available.',
    updateText: 'Install',
    laterText: 'Later',
    onUpdate: () => controller.download(),
    onLater: () => controller.stopPeriodic(),
    onSkipVersion: () => UpdatePreferences.skipVersion(info.latestVersion!),
  ),
);
```

---

## 3. Replace the whole widget

`AppUpdaterTheme.builder` receives everything the built-in layout uses:

```dart
typedef AppUpdaterDialogBuilder = Widget Function(
  BuildContext context,
  UpdateInfo info,
  AppUpdaterDialogActions actions,
  AppUpdaterTheme theme,
);
```

`AppUpdaterDialogActions`:

| Member | Meaning |
|---|---|
| `onUpdate` | User accepted: open the store, start the download or install. |
| `onLater` | User dismissed: record the dismissal and close. |
| `onSkipVersion` | Remember this version and close (null when not offered). |
| `onDoNotAskAgain` | Disable prompts (null when not offered). |
| `isPersistent` | Hide the dismiss actions (mandatory update). |

Example: a bottom sheet with the app's own design language.

```dart
theme: AppUpdaterTheme(
  builder: (context, info, actions, theme) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Watchtower ${info.latestVersion}',
                style: theme.titleTextStyle()),
            const SizedBox(height: 8),
            Text('Current version: ${info.currentVersion}',
                style: TextStyle(color: theme.mutedColor)),
            if (info.releaseNotes != null) ...[
              const SizedBox(height: 16),
              Text(info.releaseNotes!, style: theme.bodyTextStyle()),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (!actions.isPersistent)
                  TextButton(onPressed: actions.onLater, child: const Text('Later')),
                const Spacer(),
                FilledButton(
                  onPressed: actions.onUpdate,
                  child: const Text('Install'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  },
),
```

---

## 4. Drive the dialog from the controller

When auto-update is enabled the package already knows there is a build. Show
your own surface whenever `UpdatePhase.available` appears:

```dart
controller.states.listen((state) {
  if (state.phase != UpdatePhase.available || !mounted) return;
  showModalBottomSheet(
    context: context,
    builder: (_) => MyUpdateSheet(
      info: state.info!,
      onInstall: () => controller.download(installAfterDownload: true),
    ),
  );
});
```

For an inline badge in Settings > About:

```dart
StreamBuilder<UpdateState>(
  stream: controller.states,
  initialData: controller.state,
  builder: (context, snapshot) {
    final state = snapshot.data!;
    if (state.phase != UpdatePhase.available) return const SizedBox.shrink();
    return Text('v${state.candidate!.version} available');
  },
);
```

---

## 5. Copy and localization

`UpdateStrings` is a plain value object; pass a different instance per locale:

```dart
UpdateStrings stringsFor(Locale locale) {
  switch (locale.languageCode) {
    case 'fr':
      return const UpdateStrings(
        updateAvailableTitle: 'Mise à jour disponible',
        updateButton: 'Mettre à jour',
        laterButton: 'Plus tard',
      );
    case 'de':
      return const UpdateStrings(
        updateAvailableTitle: 'Update verfügbar',
        updateButton: 'Aktualisieren',
        laterButton: 'Später',
      );
    default:
      return UpdateStrings.defaultStrings;
  }
}
```

Rebuild the `AppUpdater` (or its config) when the locale changes; the strings
are read at dialog build time.
