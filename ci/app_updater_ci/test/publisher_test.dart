import 'dart:convert';
import 'dart:io';

import 'package:app_updater_ci/app_updater_ci.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late File apk;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('publisher_test_');
    apk = File(p.join(tmp.path, 'app-arm64-v8a.apk'));
    await apk.writeAsString('apk bytes');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('posts metadata then uploads the artifact', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'POST') {
        expect(jsonDecode(request.body)['version'], '2.0.0');
        return http.Response('{"buildId":"b1","uploadUrl":"/up"}', 201);
      }
      expect(request.headers['x-sha256'], hasLength(64));
      expect(request.bodyBytes, utf8.encode('apk bytes'));
      return http.Response('{"version":"2.0.0"}', 201);
    });

    final result = await publishBuild(
      PublishRequest(
        endpoint: Uri.parse('https://updates.example.com'),
        appId: 'app',
        file: apk,
        version: '2.0.0',
        platform: 'android',
        abi: 'arm64-v8a',
        token: 'secret',
      ),
      client: client,
    );

    expect(calls, [
      'POST /v1/apps/app/builds',
      'PUT /up',
    ]);
    expect(result!.buildId, 'b1');
    expect(result.uploaded, isTrue);
  });

  test('writes app-update.json for the GitHub artifacts flow', () async {
    await publishBuild(
      PublishRequest(
        endpoint: Uri.parse('https://updates.example.com'),
        appId: 'app',
        file: apk,
        version: '2.0.0',
        platform: 'android',
        writeManifest: true,
      ),
      client: MockClient((_) async => http.Response('{"buildId":"b1"}', 201)),
    );

    final manifestFile = File(p.join(tmp.path, 'app-update.json'));
    expect(manifestFile.existsSync(), isTrue);
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
    expect(manifest['version'], '2.0.0');
    expect(manifest['sha256'], hasLength(64));
    expect(manifest['size'], 9);
  });

  test('a dry run never touches the network', () async {
    final client = MockClient((_) async {
      fail('network must not be used');
    });
    final result = await publishBuild(
      PublishRequest(
        endpoint: Uri.parse('https://updates.example.com'),
        appId: 'app',
        file: apk,
        version: '2.0.0',
        platform: 'android',
        dryRun: true,
      ),
      client: client,
    );
    expect(result, isNull);
  });
}
