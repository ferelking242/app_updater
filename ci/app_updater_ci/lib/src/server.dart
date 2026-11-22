import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'build_store.dart';

/// HTTP API used by CI jobs to publish builds and by apps to fetch them.
///
/// Routes:
/// * `POST /v1/apps/<app>/builds` — announce a build, returns an upload URL.
/// * `PUT  /v1/apps/<app>/builds/<id>/artifact` — upload the file itself.
/// * `GET  /v1/apps/<app>/latest?platform=&channel=&abi=` — manifest used by
///   `CiFeedSource`.
/// * `GET  /v1/apps/<app>/builds` — published builds (newest last).
/// * `GET  /v1/apps/<app>/builds/<id>/artifact` — the file.
/// * `DELETE /v1/apps/<app>/builds/<id>` — remove a build and its file.
/// * `GET  /healthz` — liveness probe.
///
/// Writes require `Authorization: Bearer <token>`. Reads are public so apps
/// can poll the feed without shipping a credential.
class AppUpdaterCiServer {
  AppUpdaterCiServer({
    required Directory dataDir,
    required this.writeToken,
    this.requireTokenForReads = false,
    this.keepPerChannel = 10,
  }) : store = BuildStore(dataDir);

  final BuildStore store;

  /// Token CI jobs must present. Empty means writes are refused.
  final String writeToken;

  /// Also protect `GET` routes (private distributions).
  final bool requireTokenForReads;

  /// How many builds are kept per app and channel.
  final int keepPerChannel;

  final Random _random = Random.secure();

  Handler get handler => const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors)
      .addHandler(_router.call);

  late final Router _router = Router()
    ..get('/healthz', _health)
    ..post('/v1/apps/<app>/builds', _createBuild)
    ..get('/v1/apps/<app>/builds', _listBuilds)
    ..put('/v1/apps/<app>/builds/<id>/artifact', _uploadArtifact)
    ..get('/v1/apps/<app>/builds/<id>/artifact', _downloadArtifact)
    ..delete('/v1/apps/<app>/builds/<id>', _deleteBuild)
    ..get('/v1/apps/<app>/latest', _latestBuild);

  Future<Response> _health(Request request) async {
    return _json({'status': 'ok', 'time': DateTime.now().toUtc().toIso8601String()});
  }

  Future<Response> _createBuild(Request request) async {
    if (!_authorized(request)) return _unauthorized();
    final appId = request.params['app']!;
    final body = await _readJson(request);
    if (body == null) return _badRequest('Body must be a JSON object');

    final version = body['version']?.toString().trim();
    final platform = body['platform']?.toString().trim();
    if (version == null || version.isEmpty) {
      return _badRequest('"version" is required');
    }
    if (platform == null || platform.isEmpty) {
      return _badRequest('"platform" is required');
    }

    final id = _newId();
    final build = BuildRecord(
      id: id,
      appId: appId,
      version: version,
      buildNumber: _asInt(body['buildNumber']),
      platform: platform,
      channel: body['channel']?.toString() ?? 'stable',
      abi: body['abi']?.toString(),
      fileName: body['fileName']?.toString(),
      url: body['url']?.toString(),
      sizeBytes: _asInt(body['size']),
      sha256: body['sha256']?.toString(),
      releaseNotes: body['releaseNotes']?.toString(),
      releaseUrl: body['releaseUrl']?.toString(),
      minimumVersion: body['minimumVersion']?.toString(),
      urgency: body['urgency']?.toString() ?? 'medium',
      mandatory: body['mandatory'] == true,
      createdAt: DateTime.now().toUtc(),
    );

    await store.add(build, keepPerChannel: keepPerChannel);
    final needsUpload = build.url == null && build.fileName == null;
    return _json(
      {
        'buildId': id,
        'uploadUrl': '/v1/apps/$appId/builds/$id/artifact',
        'awaitingUpload': needsUpload,
      },
      status: 201,
    );
  }

  Future<Response> _listBuilds(Request request) async {
    if (requireTokenForReads && !_authorized(request)) return _unauthorized();
    final appId = request.params['app']!;
    final platform = request.url.queryParameters['platform'];
    final channel = request.url.queryParameters['channel'];
    final builds = (await store.list(appId))
        .where((build) => platform == null || build.platform == platform)
        .where((build) => channel == null || build.channel == channel)
        .toList()
      ..sort(BuildRecord.compare);
    return _json({
      'app': appId,
      'builds': builds.map((build) => build.toJson()).toList(growable: false),
    });
  }

  Future<Response> _latestBuild(Request request) async {
    if (requireTokenForReads && !_authorized(request)) return _unauthorized();
    final appId = request.params['app']!;
    final query = request.url.queryParameters;
    final platform = query['platform'];
    if (platform == null || platform.isEmpty) {
      return _badRequest('"platform" query parameter is required');
    }
    final build = await store.latest(
      appId: appId,
      platform: platform,
      channel: query['channel'] ?? 'stable',
      abi: query['abi'],
    );
    if (build == null) {
      return _json({'error': 'no build published for $platform'}, status: 404);
    }
    return _json(build.toManifest());
  }

  Future<Response> _uploadArtifact(Request request) async {
    if (!_authorized(request)) return _unauthorized();
    final appId = request.params['app']!;
    final buildId = request.params['id']!;
    final builds = await store.list(appId);
    final match = builds.where((entry) => entry.id == buildId).toList();
    if (match.isEmpty) return _json({'error': 'unknown build'}, status: 404);
    final build = match.first;

    final fileName = request.headers['x-file-name'] ?? build.fileName;
    if (fileName == null || fileName.isEmpty) {
      return _badRequest('"x-file-name" header is required');
    }

    final file = store.artifactFile(appId, buildId, fileName);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var size = 0;
    try {
      await for (final chunk in request.read()) {
        sink.add(chunk);
        hasher.add(chunk);
        size += chunk.length;
      }
      await sink.flush();
      await sink.close();
      hasher.close();
    } catch (error) {
      await sink.close();
      if (await file.exists()) await file.delete();
      return _json({'error': 'upload failed: $error'}, status: 500);
    }

    final published = digestSink.value?.toString();
    final expected = request.headers['x-sha256'];
    if (expected != null &&
        published != null &&
        expected.toLowerCase() != published.toLowerCase()) {
      await file.delete();
      return _badRequest('SHA-256 mismatch');
    }

    final updated = build.copyWith(
      fileName: fileName,
      sizeBytes: size,
      sha256: published,
    );
    await store.save(
      appId,
      builds.map((entry) => entry.id == buildId ? updated : entry).toList(),
    );

    return _json(updated.toManifest(), status: 201);
  }

  Future<Response> _downloadArtifact(Request request) async {
    if (requireTokenForReads && !_authorized(request)) return _unauthorized();
    final appId = request.params['app']!;
    final buildId = request.params['id']!;
    final builds = await store.list(appId);
    final match = builds.where((entry) => entry.id == buildId).toList();
    if (match.isEmpty || match.first.fileName == null) {
      return _json({'error': 'unknown build'}, status: 404);
    }
    final build = match.first;
    final file = store.artifactFile(appId, buildId, build.fileName!);
    if (!await file.exists()) {
      return _json({'error': 'artifact missing'}, status: 404);
    }
    return Response.ok(
      file.openRead(),
      headers: {
        HttpHeaders.contentTypeHeader: _contentType(build.fileName!),
        HttpHeaders.contentLengthHeader: '${await file.length()}',
        if (build.sha256 != null) 'x-checksum-sha256': build.sha256!,
        HttpHeaders.etagHeader: '"${build.sha256 ?? build.id}"',
        'content-disposition':
            'attachment; filename="${build.fileName}"',
      },
    );
  }

  Future<Response> _deleteBuild(Request request) async {
    if (!_authorized(request)) return _unauthorized();
    final appId = request.params['app']!;
    final buildId = request.params['id']!;
    final removed = await store.remove(appId, buildId);
    if (!removed) return _json({'error': 'unknown build'}, status: 404);
    return _json({'deleted': buildId});
  }

  bool _authorized(Request request) {
    if (writeToken.isEmpty) return false;
    final header = request.headers[HttpHeaders.authorizationHeader] ?? '';
    const prefix = 'Bearer ';
    if (!header.startsWith(prefix)) return false;
    return _constantTimeEquals(header.substring(prefix.length), writeToken);
  }

  Future<Map<String, dynamic>?> _readJson(Request request) async {
    try {
      final decoded = jsonDecode(await request.readAsString());
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } on FormatException {
      return null;
    }
  }

  Response _json(Object body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );

  Response _badRequest(String message) =>
      _json({'error': message}, status: 400);

  Response _unauthorized() => _json({'error': 'unauthorized'}, status: 401);

  String _newId() {
    final random = List<int>.generate(8, (_) => _random.nextInt(256));
    return '${DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36)}'
        '${random.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _contentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.apk')) {
      return 'application/vnd.android.package-archive';
    }
    if (lower.endsWith('.ipa')) return 'application/octet-stream';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  static Handler _cors(Handler inner) {
    return (request) async {
      final response = await inner(request);
      return response.change(
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'access-control-allow-headers':
              'authorization, content-type, x-file-name, x-sha256',
        },
      );
    };
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
