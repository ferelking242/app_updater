import 'dart:io' show Platform;

import '../version_checker.dart' show UpdateUrgency;

/// Parses [value] as an int, accepting numbers and numeric strings.
int? parseIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

/// Platform an update artifact targets.
enum UpdatePlatform {
  android,
  ios,
  macos,
  windows,
  linux,
  web,
  unknown;

  /// Identifier used in manifests and CI requests (`android`, `windows`, ...).
  String get id => name;

  /// Parses a platform identifier, accepting common aliases.
  static UpdatePlatform parse(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'android':
      case 'apk':
        return UpdatePlatform.android;
      case 'ios':
      case 'ipa':
        return UpdatePlatform.ios;
      case 'macos':
      case 'mac':
      case 'darwin':
        return UpdatePlatform.macos;
      case 'windows':
      case 'win':
      case 'win32':
        return UpdatePlatform.windows;
      case 'linux':
        return UpdatePlatform.linux;
      case 'web':
        return UpdatePlatform.web;
      default:
        return UpdatePlatform.unknown;
    }
  }

  /// Platform of the running app.
  static UpdatePlatform current() {
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isIOS) return UpdatePlatform.ios;
    if (Platform.isMacOS) return UpdatePlatform.macos;
    if (Platform.isWindows) return UpdatePlatform.windows;
    if (Platform.isLinux) return UpdatePlatform.linux;
    return UpdatePlatform.unknown;
  }
}

/// A single downloadable file belonging to an [UpdateCandidate].
class UpdateArtifact {
  /// File name as published by the build (`watchtower-1.4.2-arm64-v8a.apk`).
  final String fileName;

  /// Absolute or endpoint-relative URL of the file.
  final String? url;

  /// Size in bytes, when known.
  final int? sizeBytes;

  /// Lowercase hex SHA-256 of the file, when published.
  final String? sha256;

  /// Target ABI (`arm64-v8a`, `x86_64`, ...), when the build is split per ABI.
  final String? abi;

  const UpdateArtifact({
    required this.fileName,
    this.url,
    this.sizeBytes,
    this.sha256,
    this.abi,
  });

  factory UpdateArtifact.fromJson(Map<String, dynamic> json) {
    return UpdateArtifact(
      fileName: (json['name'] ?? json['fileName'] ?? '').toString(),
      url: json['url']?.toString(),
      sizeBytes: parseIntOrNull(json['size'] ?? json['sizeBytes']),
      sha256: json['sha256']?.toString(),
      abi: json['abi']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': fileName,
        if (url != null) 'url': url,
        if (sizeBytes != null) 'size': sizeBytes,
        if (sha256 != null) 'sha256': sha256,
        if (abi != null) 'abi': abi,
      };

  /// True when the file name matches the current platform and [abi].
  bool matches({UpdatePlatform? platform, String? abi}) {
    final name = fileName.toLowerCase();
    if (platform != null && !_matchesPlatform(name, platform)) return false;
    if (abi != null && abi.isNotEmpty) {
      final normalized = abi.toLowerCase();
      return name.contains(normalized) ||
          _abiAliases(normalized).any(name.contains);
    }
    return true;
  }

  static bool _matchesPlatform(String name, UpdatePlatform platform) {
    const tokens = <UpdatePlatform, List<String>>{
      UpdatePlatform.android: ['.apk', 'android'],
      UpdatePlatform.ios: ['.ipa', 'ios'],
      UpdatePlatform.macos: ['.dmg', '.pkg', 'macos', 'darwin'],
      UpdatePlatform.windows: ['.exe', '.msix', 'windows', 'win64'],
      UpdatePlatform.linux: ['.deb', '.rpm', '.appimage', '.tar.gz', 'linux'],
    };
    final expected = tokens[platform];
    if (expected == null) return true;
    return expected.any(name.contains);
  }

  static List<String> _abiAliases(String abi) {
    switch (abi) {
      case 'arm64-v8a':
        return const ['arm64', 'aarch64'];
      case 'armeabi-v7a':
        return const ['armv7', 'armeabi'];
      case 'x86_64':
        return const ['x64', 'amd64'];
      case 'x86':
        return const ['i686', 'i386'];
      default:
        return const [];
    }
  }

  @override
  String toString() => 'UpdateArtifact($fileName, abi: $abi, url: $url)';
}

/// A build published by CI, independent from the delivery channel.
///
/// It is produced by [UpdateSource] implementations (GitHub Actions
/// artifacts, an app_updater CI server, a custom JSON endpoint, ...) and
/// consumed by `AppUpdateController`.
class UpdateCandidate {
  /// Version of the build (`1.4.2`).
  final String version;

  /// Monotonic build number (`42`), used to break version ties.
  final int? buildNumber;

  /// Platform this build targets.
  final UpdatePlatform platform;

  /// Release channel (`stable`, `beta`, `nightly`).
  final String channel;

  /// Release notes shown in the update UI.
  final String? releaseNotes;

  /// Publication time.
  final DateTime? publishedAt;

  /// Urgency used by the built-in dialogs.
  final UpdateUrgency urgency;

  /// Whether the update cannot be skipped.
  final bool mandatory;

  /// Minimum version still supported by the backend.
  final String? minimumVersion;

  /// Web page describing the release.
  final String? releaseUrl;

  /// Files offered by this build.
  final List<UpdateArtifact> artifacts;

  /// Source-specific data (workflow run id, commit sha, ...).
  final Map<String, dynamic> metadata;

  const UpdateCandidate({
    required this.version,
    required this.platform,
    this.buildNumber,
    this.channel = 'stable',
    this.releaseNotes,
    this.publishedAt,
    this.urgency = UpdateUrgency.medium,
    this.mandatory = false,
    this.minimumVersion,
    this.releaseUrl,
    this.artifacts = const <UpdateArtifact>[],
    this.metadata = const <String, dynamic>{},
  });

  factory UpdateCandidate.fromJson(
    Map<String, dynamic> json, {
    Uri? baseUri,
  }) {
    final platform = UpdatePlatform.parse(json['platform']?.toString());
    final rawArtifacts = (json['artifacts'] as List?) ?? const [];
    final artifacts = rawArtifacts
        .whereType<Map>()
        .map((entry) => UpdateArtifact.fromJson(entry.cast<String, dynamic>()))
        .map((artifact) => baseUri == null
            ? artifact
            : UpdateArtifact(
                fileName: artifact.fileName,
                url: _resolve(baseUri, artifact.url),
                sizeBytes: artifact.sizeBytes,
                sha256: artifact.sha256,
                abi: artifact.abi,
              ))
        .toList(growable: false);

    return UpdateCandidate(
      version: VersionNormalizer.of(json['version']),
      buildNumber: parseIntOrNull(json['buildNumber'] ?? json['build']),
      platform: platform,
      channel: (json['channel'] ?? 'stable').toString(),
      releaseNotes: json['releaseNotes']?.toString() ??
          json['notes']?.toString() ??
          json['changelog']?.toString(),
      publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      urgency: parseUrgency(json['urgency']?.toString()),
      mandatory: json['mandatory'] == true,
      minimumVersion: json['minimumVersion']?.toString(),
      releaseUrl: _resolve(baseUri, json['releaseUrl']?.toString()),
      artifacts: artifacts,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        if (buildNumber != null) 'buildNumber': buildNumber,
        'platform': platform.id,
        'channel': channel,
        if (releaseNotes != null) 'releaseNotes': releaseNotes,
        if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
        'urgency': urgency.name,
        'mandatory': mandatory,
        if (minimumVersion != null) 'minimumVersion': minimumVersion,
        if (releaseUrl != null) 'releaseUrl': releaseUrl,
        'artifacts': artifacts.map((a) => a.toJson()).toList(growable: false),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  /// Picks the best artifact for [abi], falling back to the first compatible
  /// file and then to the first published file.
  UpdateArtifact? artifactFor({String? abi, UpdatePlatform? platform}) {
    final targetPlatform = platform ?? this.platform;
    final candidates = artifacts
        .where((a) => a.matches(platform: targetPlatform, abi: abi))
        .toList(growable: false);
    if (candidates.isNotEmpty) return candidates.first;
    final platformOnly = artifacts
        .where((a) => a.matches(platform: targetPlatform))
        .toList(growable: false);
    if (platformOnly.isNotEmpty) return platformOnly.first;
    return artifacts.isEmpty ? null : artifacts.first;
  }

  UpdateCandidate copyWith({
    String? version,
    int? buildNumber,
    String? releaseNotes,
    DateTime? publishedAt,
    UpdateUrgency? urgency,
    bool? mandatory,
    String? minimumVersion,
    String? releaseUrl,
    List<UpdateArtifact>? artifacts,
    Map<String, dynamic>? metadata,
  }) {
    return UpdateCandidate(
      version: version ?? this.version,
      buildNumber: buildNumber ?? this.buildNumber,
      platform: platform,
      channel: channel,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      publishedAt: publishedAt ?? this.publishedAt,
      urgency: urgency ?? this.urgency,
      mandatory: mandatory ?? this.mandatory,
      minimumVersion: minimumVersion ?? this.minimumVersion,
      releaseUrl: releaseUrl ?? this.releaseUrl,
      artifacts: artifacts ?? this.artifacts,
      metadata: metadata ?? this.metadata,
    );
  }

  static UpdateUrgency parseUrgency(String? value) {
    switch (value?.toLowerCase().trim()) {
      case 'low':
        return UpdateUrgency.low;
      case 'high':
        return UpdateUrgency.high;
      case 'critical':
        return UpdateUrgency.critical;
      default:
        return UpdateUrgency.medium;
    }
  }

  static String? _resolve(Uri? base, String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    if (uri.hasScheme || base == null) return uri.toString();
    return base.resolveUri(uri).toString();
  }

  @override
  String toString() =>
      'UpdateCandidate($version+${buildNumber ?? 0}, ${platform.id}, '
      'channel: $channel, artifacts: ${artifacts.length})';
}

/// Normalizes version strings coming from CI (tags, file names, manifests).
class VersionNormalizer {
  VersionNormalizer._();

  static final RegExp _semver = RegExp(r'(\d+\.\d+(?:\.\d+)*)');

  /// Returns `x.y.z` when [value] contains a version, otherwise the trimmed
  /// input so callers never lose information.
  static String of(Object? value) {
    final raw = value?.toString().trim() ?? '';
    final match = _semver.firstMatch(raw);
    return match?.group(1) ?? raw;
  }
}
