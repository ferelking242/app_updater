import 'dart:io';

import '../models/prepared_update.dart';
import '../models/update_candidate.dart';
import 'update_source.dart';

/// Tries several sources in order and keeps the newest build.
///
/// Typical setup: CI artifacts for continuous delivery, GitHub Releases as the
/// fallback when no CI build is available.
///
/// ```dart
/// final source = CompositeUpdateSource([
///   GitHubArtifactsSource(owner: 'me', repo: 'app', workflow: 'build.yml'),
///   GitHubReleasesSource(owner: 'me', repo: 'app'),
/// ]);
/// ```
class CompositeUpdateSource extends UpdateSource {
  CompositeUpdateSource(this.sources, {this.versionComparator});

  final List<UpdateSource> sources;

  /// Custom ordering; defaults to numeric version comparison.
  final int Function(String a, String b)? versionComparator;

  @override
  String get id => 'composite:${sources.map((s) => s.id).join('+')}';

  @override
  Future<UpdateCandidate?> fetchLatest({
    required UpdatePlatform platform,
    String? channel,
    String? abi,
  }) async {
    final found = <(UpdateSource, UpdateCandidate)>[];
    for (final source in sources) {
      try {
        final candidate = await source.fetchLatest(
          platform: platform,
          channel: channel,
          abi: abi,
        );
        if (candidate != null) found.add((source, candidate));
      } catch (_) {
        // One broken source must not hide the others.
      }
    }
    if (found.isEmpty) return null;

    found.sort((a, b) {
      final compare = versionComparator?.call(a.$2.version, b.$2.version) ??
          _compareVersions(a.$2, b.$2);
      return compare;
    });
    final best = found.last;
    return best.$2.copyWith(
      metadata: <String, dynamic>{
        ...best.$2.metadata,
        'provider': best.$1.id,
      },
    );
  }

  @override
  Future<PreparedUpdate> prepareDownload(
    UpdateCandidate candidate,
    UpdateArtifact artifact, {
    required Directory workDir,
    Map<String, String>? headers,
    DownloadProgressCallback? onProgress,
  }) {
    final provider = candidate.metadata['provider']?.toString();
    final source = sources.firstWhere(
      (entry) => entry.id == provider,
      orElse: () => sources.first,
    );
    return source.prepareDownload(
      candidate,
      artifact,
      workDir: workDir,
      headers: headers,
      onProgress: onProgress,
    );
  }

  static int _compareVersions(UpdateCandidate a, UpdateCandidate b) {
    final byVersion = _compare(a.version, b.version);
    if (byVersion != 0) return byVersion;
    return (a.buildNumber ?? 0).compareTo(b.buildNumber ?? 0);
  }

  static int _compare(String a, String b) {
    final left = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final right = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }
}
