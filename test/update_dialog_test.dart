import 'package:app_updater/app_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final info = UpdateInfo(
    currentVersion: '1.0.0',
    latestVersion: '1.1.0',
    updateAvailable: true,
    releaseNotes: 'Bug fixes',
  );

  testWidgets('renders the themed dialog with versions and notes',
      (tester) async {
    var updated = false;
    var later = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AppUpdaterUpdateDialog(
                    theme: const AppUpdaterTheme(
                      accentColor: Colors.deepOrange,
                    ),
                    info: info,
                    title: 'Mise à jour disponible',
                    message: 'Une nouvelle version est prête.',
                    updateText: 'Installer',
                    laterText: 'Plus tard',
                    onUpdate: () => updated = true,
                    onLater: () => later = true,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Mise à jour disponible'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('1.1.0'), findsOneWidget);
    expect(find.text('Bug fixes'), findsOneWidget);

    await tester.tap(find.text('Installer'));
    await tester.pumpAndSettle();
    expect(updated, isTrue);
    expect(later, isFalse);
  });

  testWidgets('a custom builder replaces the built-in layout', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppUpdaterUpdateDialog(
          theme: AppUpdaterTheme(
            builder: (context, info, actions, theme) => Center(
              child: Text('custom ${info.latestVersion}'),
            ),
          ),
          info: info,
          title: 'title',
          message: 'message',
          updateText: 'update',
          laterText: 'later',
        ),
      ),
    );

    expect(find.text('custom 1.1.0'), findsOneWidget);
  });
}
