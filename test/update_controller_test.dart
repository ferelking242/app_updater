import 'dart:io';

import 'package:app_updater/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSource extends UpdateSource {
  _FakeSource(this.candidate);

  UpdateCandidate? candidate;
  int fetchCount = 0;
  bool failDownload = false;

  @override
  String get id => 'fake';

  @override
  Future<UpdateCandidate?> fetchLatest({
    required UpdatePlatform platform,
    String? channel,
    String? abi,
  }) async {
    fetchCount++;
    return candidate;
  }

  @override
  Future<PreparedUpdate> prepareDownload(
    UpdateCandidate candidate,
    UpdateArtifact artifact, {
    required Directory workDir,
    Map<String, String>? headers,
    DownloadProgressCallback? onProgress,
  }) async {
    if (failDownload) throw const FileSystemException('network down');
    onProgress?.call(50, 100);
    onProgress?.call(100, 100);
    final file = File('${workDir.path}/${artifact.fileName}');
    await file.writeAsString('apk');
    return PreparedUpdate(
      file: file,
      version: candidate.version,
      sha256: 'abc',
    );
  }
}

class _RecordingNotifier implements UpdateNotifier {
  final List<UpdatePhase> phases = [];
  int readyCount = 0;
  int progressCount = 0;

  @override
  Future<void> showUpdateAvailable(UpdateState state) async =>
      phases.add(UpdatePhase.available);

  @override
  Future<void> showDownloadProgress(UpdateState state) async => progressCount++;

  @override
  Future<void> showReadyToInstall(UpdateState state) async {
    readyCount++;
    phases.add(UpdatePhase.readyToInstall);
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> showError(UpdateState state) async =>
      phases.add(UpdatePhase.failed);
}

class _RecordingInstaller implements UpdateInstaller {
  _RecordingInstaller({this.silent = false});

  final bool silent;
  int installCount = 0;

  @override
  Future<bool> canInstallInBackground() async => silent;

  @override
  Future<bool> install(PreparedUpdate update) async {
    installCount++;
    return true;
  }
}

void main() {
  late Directory workDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    workDir = await Directory.systemTemp.createTemp('controller_test_');
  });

  tearDown(() async {
    if (await workDir.exists()) await workDir.delete(recursive: true);
  });

  AppUpdateController build(
    _FakeSource source, {
    UpdateNotifier? notifier,
    UpdateInstaller? installer,
    AutoUpdateOptions options = const AutoUpdateOptions(),
    String version = '1.0.0',
    int? buildNumber,
  }) {
    return AppUpdateController(
      source: source,
      notifier: notifier ?? _RecordingNotifier(),
      installer: installer,
      options: options,
      workDir: workDir,
      currentVersionProvider: () async => version,
      currentBuildNumberProvider: () async => buildNumber,
    );
  }

  const candidate = UpdateCandidate(
    version: '1.2.0',
    platform: UpdatePlatform.android,
    releaseNotes: 'New things',
    artifacts: [
      UpdateArtifact(
        fileName: 'app-arm64-v8a.apk',
        url: 'https://example.com/app.apk',
        abi: 'arm64-v8a',
        sizeBytes: 1000,
      ),
    ],
  );

  test('reports an available update and exposes UpdateInfo', () async {
    final notifier = _RecordingNotifier();
    final controller = build(_FakeSource(candidate), notifier: notifier);

    final state = await controller.check();

    expect(state.phase, UpdatePhase.available);
    expect(state.info!.latestVersion, '1.2.0');
    expect(state.info!.releaseNotes, 'New things');
    expect(state.info!.updateSizeBytes, 1000);
    expect(state.info!.updateAvailable, isTrue);
    expect(notifier.phases, [UpdatePhase.available]);
  });

  test('reports up to date when the installed version is newer', () async {
    final controller = build(_FakeSource(candidate), version: '1.3.0');
    final state = await controller.check();
    expect(state.phase, UpdatePhase.upToDate);
    expect(state.updateAvailable, isFalse);
  });

  test('offers a rebuild of the same version with a newer build number',
      () async {
    final controller = build(
      _FakeSource(
        const UpdateCandidate(
          version: '1.2.0',
          buildNumber: 42,
          platform: UpdatePlatform.android,
          artifacts: [
            UpdateArtifact(
              fileName: 'app-arm64-v8a.apk',
              url: 'https://example.com/app.apk',
            ),
          ],
        ),
      ),
      version: '1.2.0',
      buildNumber: 41,
    );

    final state = await controller.check();

    expect(state.phase, UpdatePhase.available);
    expect(state.info!.updateAvailable, isTrue);
  });

  test('ignores the same version when the build number is not newer',
      () async {
    final controller = build(
      _FakeSource(
        const UpdateCandidate(
          version: '1.2.0',
          buildNumber: 41,
          platform: UpdatePlatform.android,
          artifacts: [
            UpdateArtifact(
              fileName: 'app-arm64-v8a.apk',
              url: 'https://example.com/app.apk',
            ),
          ],
        ),
      ),
      version: '1.2.0',
      buildNumber: 41,
    );

    final state = await controller.check();

    expect(state.phase, UpdatePhase.upToDate);
    expect(state.info!.updateAvailable, isFalse);
  });

  test('downloads, reports progress and prepares install', () async {
    final notifier = _RecordingNotifier();
    final installer = _RecordingInstaller(silent: true);
    final controller = build(
      _FakeSource(candidate),
      notifier: notifier,
      installer: installer,
    );

    await controller.check();
    final state = await controller.download(installAfterDownload: true);

    expect(state.phase, UpdatePhase.installed);
    expect(state.prepared!.file.existsSync(), isTrue);
    expect(notifier.progressCount, 2);
    expect(notifier.readyCount, 1);
    expect(installer.installCount, 1);
  });

  test('keeps the download when the install cannot run', () async {
    final installer = _RecordingInstaller(silent: false);
    final controller = build(_FakeSource(candidate), installer: installer);
    await controller.check();
    await controller.download();
    final started = await controller.install();
    expect(started, isTrue);
    expect(installer.installCount, 1);
  });

  test('surfaces download failures without throwing', () async {
    final source = _FakeSource(candidate)..failDownload = true;
    final notifier = _RecordingNotifier();
    final controller = build(source, notifier: notifier);
    await controller.check();
    final state = await controller.download();
    expect(state.phase, UpdatePhase.failed);
    expect(state.error, isA<FileSystemException>());
    expect(notifier.phases.last, UpdatePhase.failed);
  });

  test('auto-update on launch is opt-in and rate limited', () async {
    final source = _FakeSource(candidate);
    final controller = build(source);

    expect(await controller.isAutoUpdateEnabled(), isFalse);
    await controller.checkOnLaunch();
    expect(source.fetchCount, 0);

    await controller.setAutoUpdateEnabled(true);
    await controller.checkOnLaunch();
    expect(source.fetchCount, 1);
    expect(
      controller.state.phase,
      UpdatePhase.available,
      reason: 'a launch check announces the build, it never downloads it',
    );
    expect(controller.state.prepared, isNull);

    await controller.checkOnLaunch();
    expect(source.fetchCount, 1, reason: 'interval not elapsed yet');

    await controller.dispose();
  });

  test('downloadOnLaunch downloads when the host opts in', () async {
    final controller = build(
      _FakeSource(candidate),
      options: const AutoUpdateOptions(downloadOnLaunch: true),
    );
    await controller.setAutoUpdateEnabled(true);

    await controller.checkOnLaunch();

    expect(controller.state.phase, UpdatePhase.readyToInstall);
    expect(controller.state.prepared, isNotNull);
  });

  test('a downloaded build survives a new check and a restart', () async {
    final installer = _RecordingInstaller();
    final first = build(_FakeSource(candidate), installer: installer);
    await first.check();
    await first.download();
    expect(first.state.phase, UpdatePhase.readyToInstall);

    // Same prefs, fresh controller: the app was restarted.
    final second = build(_FakeSource(candidate), installer: installer);
    final state = await second.check();

    expect(state.phase, UpdatePhase.readyToInstall);
    expect(state.prepared, isNotNull);
    expect(state.prepared!.version, '1.2.0');
    expect(state.prepared!.file.existsSync(), isTrue);

    expect(await second.install(), isTrue);
    expect(installer.installCount, 1);
    expect(await second.pendingUpdate(), isNull);
  });

  test('a stale downloaded build is dropped on check', () async {
    final first = build(_FakeSource(candidate));
    await first.check();
    await first.download();
    final staleApk = first.state.prepared!.file;

    final newer = _FakeSource(
      const UpdateCandidate(
        version: '1.3.0',
        platform: UpdatePlatform.android,
        artifacts: [
          UpdateArtifact(
            fileName: 'app-arm64-v8a.apk',
            url: 'https://example.com/app.apk',
          ),
        ],
      ),
    );
    final second = build(newer);
    final state = await second.check();

    expect(state.phase, UpdatePhase.available);
    expect(state.prepared, isNull);
    expect(await second.pendingUpdate(), isNull);
    expect(staleApk.existsSync(), isFalse, reason: 'stale APK is removed');
  });

  test('install without any downloaded build is a no-op', () async {
    final installer = _RecordingInstaller();
    final controller = build(_FakeSource(candidate), installer: installer);
    await controller.check();

    expect(await controller.install(), isFalse);
    expect(installer.installCount, 0);
  });

  test('does not repeat the same notification across restarts', () async {
    final notifier = _RecordingNotifier();
    final first = build(_FakeSource(candidate), notifier: notifier);
    await first.check();
    expect(notifier.phases, [UpdatePhase.available]);

    final second = build(_FakeSource(candidate), notifier: notifier);
    await second.check(manual: false);
    expect(notifier.phases, [UpdatePhase.available]);
  });
}
