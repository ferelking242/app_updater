import 'dart:io';

/// Called while a file is downloaded. [total] is -1 when the size is unknown.
typedef DownloadProgressCallback = void Function(int received, int total);

/// Result of downloading a build artifact.
class PreparedUpdate {
  /// Downloaded, installable file (APK, IPA, EXE, AppImage, ...).
  final File file;

  /// Version read from the build itself, with the candidate value as fallback.
  final String version;

  /// Release notes read from the build manifest, with the candidate value as
  /// fallback.
  final String? releaseNotes;

  /// SHA-256 of [file] when computed or published.
  final String? sha256;

  /// Manifest embedded in the build (`app-update.json`), when present.
  final Map<String, dynamic> manifest;

  const PreparedUpdate({
    required this.file,
    required this.version,
    this.releaseNotes,
    this.sha256,
    this.manifest = const <String, dynamic>{},
  });

  @override
  String toString() => 'PreparedUpdate(${file.path}, version: $version)';
}
