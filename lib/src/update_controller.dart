import 'dart:async';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/prepared_update.dart';
import 'models/update_candidate.dart';
import 'sources/update_source.dart';
import 'utils/version_utils.dart';
import 'version_checker.dart' show UpdateInfo, UpdateUrgency;

/// Lifecycle of an update handled by [AppUpdateController].
enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  installing,
  installed,
  failed,
}

/// Immutable snapshot published by [AppUpdateController.states].
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.info,
    this.candidate,
    this.prepared,
    this.progress,
    this.error,
  });

  final UpdatePhase phase;
  final UpdateInfo? info;
  final UpdateCandidate? candidate;
  final PreparedUpdate? prepared;

  /// 0..1 while downloading, null when the total size is unknown.
  final double? progress;
  final Object? error;

  bool get updateAvailable =>
      phase == UpdatePhase.available ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.readyToInstall ||
      phase == UpdatePhase.installing ||
      phase == UpdatePhase.installed;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateInfo? info,
    UpdateCandidate? candidate,
    PreparedUpdate? prepared,
    double? progress,
    Object? error,
    bool clearError = false,
  }) {
    return UpdateState(
      phase: phase ?? this.phase,
      info: info ?? this.info,
      candidate: candidate ?? this.candidate,
      prepared: prepared ?? this.prepared,
      progress: progress ?? this.progress,
      error: clearError ? null : error ?? this.error,
    );
  }

  @override
  String toString() =>
      'UpdateState(${phase.name}, version: ${candidate?.version}, '
      'progress: $progress)';
}

/// Policy applied by [AppUpdateController.checkOnLaunch] and the periodic timer.
class AutoUpdateOptions {
  const AutoUpdateOptions({
    this.enabledByDefault = false,
    this.interval = const Duration(hours: 6),
    this.downloadOnLaunch = true,
    this.installWhenReady = false,
    this.notifyWhenUpToDate = false,
    this.channel = 'stable',
    this.abi,
  });

  /// Value used until the user flips the switch in the app settings.
  final bool enabledByDefault;

  /// Minimum delay between two automatic checks.
  final Duration interval;

  /// Download the build right after an automatic check finds one.
  final bool downloadOnLaunch;

  /// Install without user interaction when the platform allows it (silent
  /// installer / MDM). Otherwise the notifier shows an "Install" action.
  final bool installWhenReady;

  /// Emit a state when the app is already up to date.
  final bool notifyWhenUpToDate;

  /// Channel requested from the source.
  final String channel;

  /// ABI of the current device (`arm64-v8a`), used to pick the right artifact.
  final String? abi;
}

/// Host-app hook used to surface updates (notification, snackbar, ...).
///
/// `app_updater` ships [NoopUpdateNotifier] so the package stays free of any
/// notification dependency; apps plug their own implementation in.
abstract class UpdateNotifier {
  Future<void> showUpdateAvailable(UpdateState state);

  Future<void> showDownloadProgress(UpdateState state);

  Future<void> showReadyToInstall(UpdateState state);

  Future<void> cancel();

  Future<void> showError(UpdateState state) async {}
}

/// Notifier that ignores every event.
class NoopUpdateNotifier implements UpdateNotifier {
  const NoopUpdateNotifier();

  @override
  Future<void> showUpdateAvailable(UpdateState state) async {}

  @override
  Future<void> showDownloadProgress(UpdateState state) async {}

  @override
  Future<void> showReadyToInstall(UpdateState state) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> showError(UpdateState state) async {}
}

/// Installs a prepared build.
///
/// Android needs a native intent (or a privileged installer), iOS needs a
/// store/TrollStore URL: the host app owns that logic.
abstract class UpdateInstaller {
  /// True when [install] can run without showing a system prompt.
  Future<bool> canInstallInBackground();

  /// Installs [update]. Returns true when the install was started.
  Future<bool> install(PreparedUpdate update);
}

/// Installer that simply opens a URL (store page, release page, ...).
class UrlUpdateInstaller implements UpdateInstaller {
  UrlUpdateInstaller(this.openUrl);

  final Future<void> Function(Uri url) openUrl;

  @override
  Future<bool> canInstallInBackground() async => false;

  @override
  Future<bool> install(PreparedUpdate update) async {
    final url = update.manifest['installUrl']?.toString();
    if (url == null || url.isEmpty) return false;
    await openUrl(Uri.parse(url));
    return true;
  }
}

/// Orchestrates check → download → install, including auto-update on launch.
class AppUpdateController {
  AppUpdateController({
    required this.source,
    UpdateNotifier notifier = const NoopUpdateNotifier(),
    UpdateInstaller? installer,
    this.options = const AutoUpdateOptions(),
    this.preferencesPrefix = 'app_updater',
    Directory? workDir,
    Future<String> Function()? currentVersionProvider,
  })  : _notifier = notifier,
        _installer = installer,
        _workDir = workDir,
        _currentVersionProvider = currentVersionProvider;

  final UpdateSource source;
  final AutoUpdateOptions options;
  final String preferencesPrefix;
  final UpdateNotifier _notifier;
  final UpdateInstaller? _installer;
  final Directory? _workDir;
  final Future<String> Function()? _currentVersionProvider;

  final StreamController<UpdateState> _states =
      StreamController<UpdateState>.broadcast();
  UpdateState _state = const UpdateState();
  Timer? _timer;
  bool _busy = false;

  /// Every state transition, for UI badges and debug overlays.
  Stream<UpdateState> get states => _states.stream;

  /// Latest known state.
  UpdateState get state => _state;

  /// Current installed version (`1.4.2`).
  Future<String> currentVersion() async {
    if (_currentVersionProvider != null) return _currentVersionProvider();
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// True when the user enabled auto-update.
  Future<bool> isAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${preferencesPrefix}_auto_update') ??
        options.enabledByDefault;
  }

  /// Persists the auto-update switch.
  Future<void> setAutoUpdateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${preferencesPrefix}_auto_update', enabled);
    if (enabled) {
      startPeriodic();
    } else {
      stopPeriodic();
    }
  }

  /// Last automatic check time.
  Future<DateTime?> lastAutoCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt('${preferencesPrefix}_last_auto_check');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Checks for an update.
  ///
  /// [manual] bypasses the auto-update switch and the interval; [force]
  /// ignores the "already notified" cache.
  Future<UpdateState> check({bool manual = true, bool force = false}) async {
    if (_busy) return _state;
    _busy = true;
    _emit(_state.copyWith(phase: UpdatePhase.checking, clearError: true));

    try {
      final current = await currentVersion();
      final candidate = await source.fetchLatest(
        platform: UpdatePlatform.current(),
        channel: options.channel,
        abi: options.abi,
      );

      if (candidate == null) {
        return _emit(
          UpdateState(
            phase: UpdatePhase.upToDate,
            info: UpdateInfo(
              currentVersion: current,
              updateAvailable: false,
            ),
          ),
        );
      }

      final available = VersionUtils.isNewer(current, candidate.version);
      final info = _toUpdateInfo(current, candidate, available);
      if (!available) {
        return _emit(
          UpdateState(
              phase: UpdatePhase.upToDate, info: info, candidate: candidate),
        );
      }

      final state = UpdateState(
        phase: UpdatePhase.available,
        info: info,
        candidate: candidate,
      );
      _emit(state);
      if (manual || await _shouldNotify(candidate.version, force: force)) {
        await _notifier.showUpdateAvailable(state);
        await _markNotified(candidate.version);
      }
      return state;
    } catch (error) {
      final state = _state.copyWith(phase: UpdatePhase.failed, error: error);
      _emit(state);
      await _notifier.showError(state);
      return state;
    } finally {
      _busy = false;
      await _markChecked();
    }
  }

  /// Downloads the artifact of the current candidate.
  Future<UpdateState> download({bool installAfterDownload = false}) async {
    final candidate = _state.candidate;
    if (candidate == null) return _state;
    if (_busy) return _state;

    final artifact = candidate.artifactFor(abi: options.abi);
    if (artifact == null) {
      final error =
          StateError('No artifact published for ${candidate.version}');
      _emit(_state.copyWith(phase: UpdatePhase.failed, error: error));
      return _state;
    }

    _busy = true;
    _emit(_state.copyWith(phase: UpdatePhase.downloading, progress: 0));
    try {
      final dir = await _resolveWorkDir();
      final prepared = await source.prepareDownload(
        candidate,
        artifact,
        workDir: dir,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : null;
          _emit(_state.copyWith(progress: progress));
          unawaited(_notifier.showDownloadProgress(_state));
        },
      );

      final ready = _state.copyWith(
        phase: UpdatePhase.readyToInstall,
        prepared: prepared,
        progress: 1,
      );
      _emit(ready);
      await _notifier.showReadyToInstall(ready);

      if (installAfterDownload) await install();
      return _state;
    } catch (error) {
      final state = _state.copyWith(phase: UpdatePhase.failed, error: error);
      _emit(state);
      await _notifier.showError(state);
      return state;
    } finally {
      _busy = false;
    }
  }

  /// Installs the downloaded build.
  Future<bool> install() async {
    final prepared = _state.prepared;
    final installer = _installer;
    if (prepared == null || installer == null) return false;

    _emit(_state.copyWith(phase: UpdatePhase.installing));
    try {
      final started = await installer.install(prepared);
      _emit(
        _state.copyWith(
          phase: started ? UpdatePhase.installed : UpdatePhase.readyToInstall,
        ),
      );
      if (started) await _notifier.cancel();
      return started;
    } catch (error) {
      _emit(_state.copyWith(phase: UpdatePhase.failed, error: error));
      return false;
    }
  }

  /// Check + download, used by the "install in background" flow.
  Future<UpdateState> checkAndDownload({bool manual = true}) async {
    final state = await check(manual: manual);
    if (state.phase != UpdatePhase.available) return state;
    return download(installAfterDownload: options.installWhenReady);
  }

  /// Entry point to call once at app startup.
  ///
  /// Does nothing when auto-update is disabled or when the last automatic
  /// check is younger than [AutoUpdateOptions.interval].
  Future<UpdateState> checkOnLaunch() async {
    if (!await isAutoUpdateEnabled()) return _state;
    final last = await lastAutoCheck();
    if (last != null && DateTime.now().difference(last) < options.interval) {
      return _state;
    }
    final state = await check(manual: false);
    if (state.phase != UpdatePhase.available) {
      if (state.phase == UpdatePhase.upToDate && options.notifyWhenUpToDate) {
        await _notifier.showUpdateAvailable(state);
      }
      return state;
    }
    if (!options.downloadOnLaunch) return state;
    return download(installAfterDownload: options.installWhenReady);
  }

  /// Starts the periodic background check (idempotent).
  void startPeriodic([Duration? interval]) {
    _timer?.cancel();
    final delay = interval ?? options.interval;
    _timer = Timer.periodic(delay, (_) => unawaited(checkOnLaunch()));
  }

  void stopPeriodic() {
    _timer?.cancel();
    _timer = null;
  }

  /// Releases timers and streams.
  Future<void> dispose() async {
    stopPeriodic();
    await _states.close();
  }

  UpdateState _emit(UpdateState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
    return state;
  }

  UpdateInfo _toUpdateInfo(
    String current,
    UpdateCandidate candidate,
    bool available,
  ) {
    final artifact = candidate.artifactFor(abi: options.abi);
    return UpdateInfo(
      currentVersion: current,
      latestVersion: candidate.version,
      updateUrl: artifact?.url ?? candidate.releaseUrl,
      updateAvailable: available,
      releaseNotes: candidate.releaseNotes,
      urgency: candidate.urgency,
      minimumVersion: candidate.minimumVersion,
      isMandatory: candidate.mandatory ||
          (candidate.minimumVersion != null &&
              VersionUtils.isNewer(current, candidate.minimumVersion!)),
      releaseDate: candidate.publishedAt,
      updateSizeBytes: artifact?.sizeBytes,
    );
  }

  Future<bool> _shouldNotify(String version, {required bool force}) async {
    if (force) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${preferencesPrefix}_notified_version') != version;
  }

  Future<void> _markNotified(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${preferencesPrefix}_notified_version', version);
  }

  Future<void> _markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '${preferencesPrefix}_last_auto_check',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<Directory> _resolveWorkDir() async {
    final base = _workDir ??
        Directory('${(await getTemporaryDirectory()).path}/app_updater');
    await base.create(recursive: true);
    return base;
  }

  /// Convenience for UI code: urgency of the pending update.
  UpdateUrgency get pendingUrgency =>
      _state.info?.urgency ?? UpdateUrgency.medium;
}
