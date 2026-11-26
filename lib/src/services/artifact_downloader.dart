import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/update_candidate.dart';
import '../models/prepared_update.dart';

/// Downloads build artifacts and turns archives into installable files.
class ArtifactDownloader {
  ArtifactDownloader({http.Client? client}) : _client = client ?? http.Client();

  /// Shared instance used by the built-in update sources.
  static final ArtifactDownloader instance = ArtifactDownloader();

  final http.Client _client;

  /// Name of the manifest the CI publisher writes next to the build.
  static const String manifestFileName = 'app-update.json';

  /// Streams [url] into [destination] and verifies [expectedSha256].
  ///
  /// An interrupted transfer leaves `<destination>.part` behind and the next
  /// call resumes from its length with a `Range` request, so a 50 MB APK on a
  /// flaky network does not start over. The partial file is dropped when the
  /// checksum fails, so a retry never installs a truncated build.
  Future<File> download(
    Uri url, {
    required File destination,
    Map<String, String>? headers,
    DownloadProgressCallback? onProgress,
    String? expectedSha256,
    bool resume = true,
  }) async {
    await destination.parent.create(recursive: true);
    final partial = File('${destination.path}.part');
    var have = 0;
    if (resume && await partial.exists()) {
      have = await partial.length();
    }
    if (have > 0 && await destination.exists()) {
      // A previous run already finished: nothing to fetch.
      final digest = await sha256Of(destination);
      if (expectedSha256 == null ||
          expectedSha256.isEmpty ||
          digest.toLowerCase() == expectedSha256.toLowerCase()) {
        final size = await destination.length();
        onProgress?.call(size, size);
        return destination;
      }
      await destination.delete();
    }
    if (have > 0 && have == await _remoteLength(url, headers)) {
      // The server answers with the same length: the partial is complete.
      await partial.rename(destination.path);
      onProgress?.call(have, have);
      return destination;
    }

    Future<http.StreamedResponse> send() {
      final request = http.Request('GET', url);
      if (headers != null) request.headers.addAll(headers);
      if (have > 0) request.headers['Range'] = 'bytes=$have-';
      return _client.send(request);
    }

    var response = await send();
    if (have > 0 &&
        (response.statusCode == 200 || response.statusCode == 416)) {
      // The range was ignored (or the partial is stale): start over cleanly.
      await response.stream.drain<void>();
      if (await partial.exists()) await partial.delete();
      have = 0;
      response = await send();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw HttpException(
        'Download failed with HTTP ${response.statusCode}',
        uri: url,
      );
    }

    final resumed = response.statusCode == 206 && have > 0;
    if (!resumed && have > 0) have = 0;
    final total = response.contentLength == null
        ? -1
        : response.contentLength! + (resumed ? have : 0);
    var received = have;
    if (have > 0) onProgress?.call(have, total);

    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    if (have > 0) {
      await for (final chunk in partial.openRead()) {
        hasher.add(chunk);
      }
    }
    final sink = partial.openWrite(
      mode: have > 0 ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      hasher.close();
    } catch (_) {
      await sink.close();
      // Keep the partial file: the next attempt resumes from it.
      rethrow;
    }

    final actual = digestSink.value?.toString();
    if (expectedSha256 != null &&
        expectedSha256.isNotEmpty &&
        actual != null &&
        actual.toLowerCase() != expectedSha256.toLowerCase()) {
      await partial.delete();
      throw const FileSystemException(
        'Downloaded file does not match the published SHA-256',
      );
    }

    if (await destination.exists()) await destination.delete();
    return partial.rename(destination.path);
  }

  /// Size announced by the server, or -1 when it is unknown.
  Future<int> _remoteLength(Uri url, Map<String, String>? headers) async {
    try {
      final request = http.Request('HEAD', url);
      if (headers != null) request.headers.addAll(headers);
      final response = await _client.send(request);
      await response.stream.drain<void>();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.contentLength ?? -1;
      }
    } catch (_) {}
    return -1;
  }

  /// Extracts [archiveFile] into [target] and returns every extracted file.
  Future<List<File>> extract(File archiveFile, Directory target) async {
    await target.create(recursive: true);
    final bytes = await archiveFile.readAsBytes();
    final archive = _decode(bytes, archiveFile.path);
    final files = <File>[];

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.split('/').contains('..')) continue;
      final out = File(p.join(target.path, name));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content as List<int>, flush: true);
      files.add(out);
    }
    return files;
  }

  /// Downloads [artifact], extracts it when it is an archive, and reads the
  /// embedded [manifestFileName].
  Future<PreparedUpdate> downloadPrepared({
    required UpdateCandidate candidate,
    required UpdateArtifact artifact,
    required Directory workDir,
    Map<String, String>? headers,
    DownloadProgressCallback? onProgress,
  }) async {
    final url = artifact.url;
    if (url == null || url.isEmpty) {
      throw ArgumentError('Artifact ${artifact.fileName} has no download URL');
    }

    final target = File(p.join(workDir.path, artifact.fileName));
    final downloaded = await download(
      Uri.parse(url),
      destination: target,
      headers: headers,
      onProgress: onProgress,
      expectedSha256: artifact.sha256,
    );

    final manifest = <String, dynamic>{};
    var installable = downloaded;
    var releaseNotes = candidate.releaseNotes;

    if (_looksLikeArchive(downloaded.path)) {
      final extracted = await extract(
        downloaded,
        Directory(p.join(workDir.path, 'extracted')),
      );
      final manifestFile = extracted.firstWhere(
        (file) => p.basename(file.path) == manifestFileName,
        orElse: () => File(''),
      );
      if (await manifestFile.exists()) {
        manifest.addAll(_readManifest(await manifestFile.readAsString()));
        releaseNotes = manifest['releaseNotes']?.toString() ?? releaseNotes;
      }
      final abi = artifact.abi;
      installable =
          _pickInstallable(extracted, candidate.platform, abi) ?? downloaded;
    }

    final version = _manifestVersion(manifest) ?? candidate.version;
    final digest = artifact.sha256 ?? await sha256Of(installable);
    return PreparedUpdate(
      file: installable,
      version: version,
      releaseNotes: releaseNotes,
      sha256: digest,
      manifest: manifest,
    );
  }

  /// Lowercase hex SHA-256 of [file].
  Future<String> sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  void close() => _client.close();

  static Archive _decode(Uint8List bytes, String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
      return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    }
    if (lower.endsWith('.tar')) return TarDecoder().decodeBytes(bytes);
    if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
      return TarDecoder().decodeBytes(XZDecoder().decodeBytes(bytes));
    }
    return ZipDecoder().decodeBytes(bytes);
  }

  static bool _looksLikeArchive(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz') ||
        lower.endsWith('.tar.xz') ||
        lower.endsWith('.txz');
  }

  static File? _pickInstallable(
    List<File> files,
    UpdatePlatform platform,
    String? abi,
  ) {
    final candidates = files
        .where((file) => p.basename(file.path) != manifestFileName)
        .where((file) => !file.path.toLowerCase().endsWith('.sha256'))
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    final artifact = UpdateArtifact(
      fileName: candidates.first.path,
      abi: abi,
    );
    for (final file in candidates) {
      final probe = UpdateArtifact(
        fileName: p.basename(file.path),
        abi: artifact.abi,
      );
      if (probe.matches(platform: platform, abi: abi)) return file;
    }
    return candidates.first;
  }

  static String? _manifestVersion(Map<String, dynamic> manifest) {
    final value = manifest['version']?.toString();
    return (value == null || value.isEmpty) ? null : value;
  }

  static Map<String, dynamic> _readManifest(String content) {
    try {
      final decoded = jsonDecode(content);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
