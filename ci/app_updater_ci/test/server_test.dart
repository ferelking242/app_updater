import 'dart:convert';
import 'dart:io';

import 'package:app_updater_ci/app_updater_ci.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory dataDir;
  late AppUpdaterCiServer server;

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('ci_server_test_');
    server = AppUpdaterCiServer(dataDir: dataDir, writeToken: 'secret');
  });

  tearDown(() async {
    if (await dataDir.exists()) await dataDir.delete(recursive: true);
  });

  Future<Response> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    List<int>? bytes,
    Map<String, String>? headers,
  }) async {
    return server.handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: bytes ?? (body == null ? null : jsonEncode(body)),
        headers: {
          if (body != null) 'content-type': 'application/json',
          ...?headers,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> jsonOf(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  test('rejects a build without a token', () async {
    final response = await send(
      'POST',
      '/v1/apps/watchtower/builds',
      body: {'version': '1.0.0', 'platform': 'android'},
    );
    expect(response.statusCode, 401);
  });

  test('publishes, uploads and serves the latest build', () async {
    final created = await send(
      'POST',
      '/v1/apps/watchtower/builds',
      body: {
        'version': '8.1.168',
        'buildNumber': 168,
        'platform': 'android',
        'abi': 'arm64-v8a',
        'releaseNotes': 'Player fix',
      },
      headers: {'authorization': 'Bearer secret'},
    );
    expect(created.statusCode, 201);
    final createdBody = await jsonOf(created);
    final buildId = createdBody['buildId'] as String;
    expect(createdBody['awaitingUpload'], isTrue);

    final uploaded = await send(
      'PUT',
      '/v1/apps/watchtower/builds/$buildId/artifact',
      bytes: utf8.encode('fake apk'),
      headers: {
        'authorization': 'Bearer secret',
        'x-file-name': 'watchtower-arm64-v8a.apk',
      },
    );
    expect(uploaded.statusCode, 201);

    final latest = await send(
      'GET',
      '/v1/apps/watchtower/latest?platform=android&abi=arm64-v8a',
    );
    expect(latest.statusCode, 200);
    final manifest = await jsonOf(latest);
    expect(manifest['version'], '8.1.168');
    expect(manifest['releaseNotes'], 'Player fix');
    final artifact = (manifest['artifacts'] as List).single as Map;
    expect(artifact['name'], 'watchtower-arm64-v8a.apk');
    expect(artifact['size'], 8);
    expect(artifact['sha256'], hasLength(64));

    final download = await send(
      'GET',
      '/v1/apps/watchtower/builds/$buildId/artifact',
    );
    expect(download.statusCode, 200);
    expect(await download.readAsString(), 'fake apk');
    expect(download.headers['x-checksum-sha256'], artifact['sha256']);
  });

  test('returns 404 when a platform has no build', () async {
    final response = await send(
      'GET',
      '/v1/apps/watchtower/latest?platform=windows',
    );
    expect(response.statusCode, 404);
  });

  test('keeps the newest version per channel and prunes old files', () async {
    Future<String> publish(String version) async {
      final created = await send(
        'POST',
        '/v1/apps/app/builds',
        body: {'version': version, 'platform': 'android'},
        headers: {'authorization': 'Bearer secret'},
      );
      final id = (await jsonOf(created))['buildId'] as String;
      await send(
        'PUT',
        '/v1/apps/app/builds/$id/artifact',
        bytes: utf8.encode('apk $version'),
        headers: {
          'authorization': 'Bearer secret',
          'x-file-name': 'app-$version.apk',
        },
      );
      return id;
    }

    final pruned = AppUpdaterCiServer(
      dataDir: dataDir,
      writeToken: 'secret',
      keepPerChannel: 2,
    );
    server = pruned;
    await publish('1.0.0');
    await publish('1.1.0');
    await publish('1.2.0');

    final list = await jsonOf(
      await send('GET', '/v1/apps/app/builds'),
    );
    final builds = list['builds'] as List;
    expect(builds, hasLength(2));
    expect((builds.last as Map)['version'], '1.2.0');
  });

  test('rejects a checksum mismatch and removes the partial file', () async {
    final created = await send(
      'POST',
      '/v1/apps/app/builds',
      body: {'version': '1.0.0', 'platform': 'android'},
      headers: {'authorization': 'Bearer secret'},
    );
    final id = (await jsonOf(created))['buildId'] as String;
    final response = await send(
      'PUT',
      '/v1/apps/app/builds/$id/artifact',
      bytes: utf8.encode('payload'),
      headers: {
        'authorization': 'Bearer secret',
        'x-file-name': 'app.apk',
        'x-sha256': 'deadbeef',
      },
    );
    expect(response.statusCode, 400);
    final latest = await send(
      'GET',
      '/v1/apps/app/latest?platform=android',
    );
    expect(latest.statusCode, 404);
  });

  test('deletes a build', () async {
    final created = await send(
      'POST',
      '/v1/apps/app/builds',
      body: {'version': '1.0.0', 'platform': 'android'},
      headers: {'authorization': 'Bearer secret'},
    );
    final id = (await jsonOf(created))['buildId'] as String;
    final deleted = await send(
      'DELETE',
      '/v1/apps/app/builds/$id',
      headers: {'authorization': 'Bearer secret'},
    );
    expect(deleted.statusCode, 200);
    final list = await jsonOf(await send('GET', '/v1/apps/app/builds'));
    expect(list['builds'], isEmpty);
  });
}
