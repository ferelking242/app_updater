import 'dart:io';

import '../models/prepared_update.dart';
import '../models/update_candidate.dart';
import '../services/artifact_downloader.dart';

/// A place builds can be discovered from.
///
/// [fetchLatest] must stay cheap (API calls only): the build itself is only
/// downloaded by [prepareDownload], when the user accepted the update or when
/// auto-update downloads it in the background.
abstract class UpdateSource {
  UpdateSource({ArtifactDownloader? downloader})
      : downloader = downloader ?? ArtifactDownloader.instance;

  /// Downloader used by [prepareDownload]; injectable for tests.
  final ArtifactDownloader downloader;

  /// Stable identifier used in logs and analytics.
  String get id;

  /// Returns the newest published build for [platform], or null when the
  /// source has nothing to offer.
  Future<UpdateCandidate?> fetchLatest({
    required UpdatePlatform platform,
    String? channel,
    String? abi,
  });

  /// Downloads [artifact] and returns an installable file.
  ///
  /// The default implementation performs a plain HTTP GET into [workDir].
  Future<PreparedUpdate> prepareDownload(
    UpdateCandidate candidate,
    UpdateArtifact artifact, {
    required Directory workDir,
    Map<String, String>? headers,
    DownloadProgressCallback? onProgress,
  }) {
    return downloader.downloadPrepared(
      candidate: candidate,
      artifact: artifact,
      workDir: workDir,
      headers: headers,
      onProgress: onProgress,
    );
  }
}
