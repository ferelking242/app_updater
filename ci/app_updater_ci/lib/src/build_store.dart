import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One build published by a CI job.
class BuildRecord {
  BuildRecord({
    required this.id,
    required this.appId,
    required this.version,
    required this.platform,
    required this.channel,
    this.buildNumber,
    this.abi,
    this.fileName,
    this.url,
    this.sizeBytes,
    this.sha256,
    this.releaseNotes,
    this.releaseUrl,
    this.minimumVersion,
    this.urgency = 'medium',
    this.mandatory = false,
    required this.createdAt,
  });

  final String id;
  final String appId;
  final String version;
  final int? buildNumber;
  final String platform;
  final String channel;
  final String? abi;
  final String? fileName;

  /// Set when the artifact is hosted elsewhere (S3, GitHub, ...).
  final String? url;

  final int? sizeBytes;
  final String? sha256;
  final String? releaseNotes;
  final String? releaseUrl;
  final String? minimumVersion;
  final String urgency;
  final bool mandatory;
  final DateTime createdAt;

  /// True when the server stores the file itself.
  bool get hasLocalArtifact => url == null && fileName != null;

  String? get artifactUrl =>
      hasLocalArtifact ? '/v1/apps/$appId/builds/$id/artifact' : url;

  BuildRecord copyWith({
    String? fileName,
    int? sizeBytes,
    String? sha256,
    String? url,
  }) {
    return BuildRecord(
      id: id,
      appId: appId,
      version: version,
      buildNumber: buildNumber,
      platform: platform,
      channel: channel,
      abi: abi,
      fileName: fileName ?? this.fileName,
      url: url ?? this.url,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      releaseNotes: releaseNotes,
      releaseUrl: releaseUrl,
      minimumVersion: minimumVersion,
      urgency: urgency,
      mandatory: mandatory,
      createdAt: createdAt,
    );
  }

  factory BuildRecord.fromJson(Map<String, dynamic> json) {
    return BuildRecord(
      id: json['id'].toString(),
      appId: json['appId'].toString(),
      version: json['version'].toString(),
      buildNumber: _asInt(json['buildNumber']),
      platform: json['platform']?.toString() ?? 'android',
      channel: json['channel']?.toString() ?? 'stable',
      abi: json['abi']?.toString(),
      fileName: json['fileName']?.toString(),
      url: json['url']?.toString(),
      sizeBytes: _asInt(json['size']),
      sha256: json['sha256']?.toString(),
      releaseNotes: json['releaseNotes']?.toString(),
      releaseUrl: json['releaseUrl']?.toString(),
      minimumVersion: json['minimumVersion']?.toString(),
      urgency: json['urgency']?.toString() ?? 'medium',
      mandatory: json['mandatory'] == true,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
              DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'appId': appId,
    'version': version,
    if (buildNumber != null) 'buildNumber': buildNumber,
    'platform': platform,
    'channel': channel,
    if (abi != null) 'abi': abi,
    if (fileName != null) 'fileName': fileName,
    if (url != null) 'url': url,
    if (sizeBytes != null) 'size': sizeBytes,
    if (sha256 != null) 'sha256': sha256,
    if (releaseNotes != null) 'releaseNotes': releaseNotes,
    if (releaseUrl != null) 'releaseUrl': releaseUrl,
    if (minimumVersion != null) 'minimumVersion': minimumVersion,
    'urgency': urgency,
    'mandatory': mandatory,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Shape consumed by `CiFeedSource` / `UpdateCandidate.fromJson`.
  Map<String, dynamic> toManifest() => <String, dynamic>{
    'version': version,
    if (buildNumber != null) 'buildNumber': buildNumber,
    'platform': platform,
    'channel': channel,
    if (releaseNotes != null) 'releaseNotes': releaseNotes,
    'publishedAt': createdAt.toIso8601String(),
    'urgency': urgency,
    'mandatory': mandatory,
    if (minimumVersion != null) 'minimumVersion': minimumVersion,
    if (releaseUrl != null) 'releaseUrl': releaseUrl,
    'artifacts': [
      if (artifactUrl != null)
        {
          'name': fileName ?? p.basename(Uri.parse(artifactUrl!).path),
          'url': artifactUrl,
          if (sizeBytes != null) 'size': sizeBytes,
          if (sha256 != null) 'sha256': sha256,
          if (abi != null) 'abi': abi,
        },
    ],
  };

  /// Orders builds: version first, then build number, then publication date.
  static int compare(BuildRecord a, BuildRecord b) {
    final byVersion = _compareVersions(a.version, b.version);
    if (byVersion != 0) return byVersion;
    final byBuild = (a.buildNumber ?? 0).compareTo(b.buildNumber ?? 0);
    if (byBuild != 0) return byBuild;
    return a.createdAt.compareTo(b.createdAt);
  }

  static int _compareVersions(String a, String b) {
    final left = a.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final right = b.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// Filesystem-backed store for builds and their artifacts.
class BuildStore {
  BuildStore(this.dataDir);

  final Directory dataDir;

  Directory appDir(String appId) => Directory(p.join(dataDir.path, _safe(appId)));

  File _indexFile(String appId) =>
      File(p.join(appDir(appId).path, 'builds.json'));

  File artifactFile(String appId, String buildId, String fileName) => File(
        p.join(appDir(appId).path, 'artifacts', '$buildId-${_safe(fileName)}'),
      );

  Future<List<BuildRecord>> list(String appId) async {
    final file = _indexFile(appId);
    if (!await file.exists()) return <BuildRecord>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <BuildRecord>[];
      return decoded
          .whereType<Map>()
          .map((entry) => BuildRecord.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false);
    } on FormatException {
      return <BuildRecord>[];
    }
  }

  Future<void> save(String appId, List<BuildRecord> builds) async {
    final file = _indexFile(appId);
    await file.parent.create(recursive: true);
    final content = const JsonEncoder.withIndent('  ').convert(
      builds.map((build) => build.toJson()).toList(growable: false),
    );
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
  }

  /// Inserts [build] and applies the retention policy.
  Future<List<BuildRecord>> add(
    BuildRecord build, {
    int keepPerChannel = 10,
  }) async {
    final builds = [...await list(build.appId), build];
    final pruned = _prune(builds, keepPerChannel);
    await save(build.appId, pruned.kept);
    for (final removed in pruned.removed) {
      await _deleteArtifact(removed);
    }
    return pruned.kept;
  }

  Future<bool> remove(String appId, String buildId) async {
    final builds = await list(appId);
    final target = builds.where((build) => build.id == buildId).toList();
    if (target.isEmpty) return false;
    await save(appId, builds.where((build) => build.id != buildId).toList());
    for (final build in target) {
      await _deleteArtifact(build);
    }
    return true;
  }

  /// Newest build for [platform] and [channel].
  Future<BuildRecord?> latest({
    required String appId,
    required String platform,
    String channel = 'stable',
    String? abi,
  }) async {
    final builds = (await list(appId))
        .where((build) => build.artifactUrl != null)
        .where((build) => build.platform == platform)
        .where((build) => build.channel == channel)
        .where((build) => abi == null || build.abi == null || build.abi == abi)
        .toList()
      ..sort(BuildRecord.compare);
    return builds.isEmpty ? null : builds.last;
  }

  Future<void> _deleteArtifact(BuildRecord build) async {
    if (build.fileName == null) return;
    final file = artifactFile(build.appId, build.id, build.fileName!);
    if (await file.exists()) await file.delete();
  }

  _PruneResult _prune(List<BuildRecord> builds, int keepPerChannel) {
    if (keepPerChannel <= 0) return _PruneResult(builds, const []);
    final kept = <BuildRecord>[];
    final removed = <BuildRecord>[];
    final byChannel = <String, List<BuildRecord>>{};
    for (final build in builds) {
      byChannel.putIfAbsent(build.channel, () => <BuildRecord>[]).add(build);
    }
    for (final entry in byChannel.entries) {
      final sorted = [...entry.value]..sort(BuildRecord.compare);
      final overflow = sorted.length > keepPerChannel
          ? sorted.sublist(0, sorted.length - keepPerChannel)
          : const <BuildRecord>[];
      removed.addAll(overflow);
      kept.addAll(sorted.where((build) => !overflow.contains(build)));
    }
    return _PruneResult(kept, removed);
  }

  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

class _PruneResult {
  const _PruneResult(this.kept, this.removed);

  final List<BuildRecord> kept;
  final List<BuildRecord> removed;
}
