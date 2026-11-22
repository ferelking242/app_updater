import 'dart:convert';

import 'package:app_updater/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reads the manifest published by the CI server', () async {
    Uri? requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(
        jsonEncode({
          'build': {
            'version': '8.1.168',
            'buildNumber': 168,
            'platform': 'android',
            'channel': 'stable',
            'releaseNotes': 'Fixed player crash',
            'artifacts': [
              {
                'name': 'watchtower-arm64-v8a.apk',
                'url': '/v1/apps/watchtower/builds/12/artifact',
                'abi': 'arm64-v8a',
                'size': 42000000,
              },
            ],
          },
        }),
        200,
      );
    });

    final source = CiFeedSource(
      endpoint: Uri.parse('https://updates.example.com'),
      appId: 'watchtower',
      client: client,
    );

    final candidate = await source.fetchLatest(
      platform: UpdatePlatform.android,
      abi: 'arm64-v8a',
    );

    expect(requested.toString(), contains('/v1/apps/watchtower/latest'));
    expect(requested!.queryParameters['platform'], 'android');
    expect(requested!.queryParameters['abi'], 'arm64-v8a');
    expect(candidate!.version, '8.1.168');
    expect(
      candidate.artifacts.single.url,
      'https://updates.example.com/v1/apps/watchtower/builds/12/artifact',
    );
  });

  test('returns null when no build is published yet', () async {
    final source = CiFeedSource(
      endpoint: Uri.parse('https://updates.example.com'),
      appId: 'watchtower',
      client: MockClient((_) async => http.Response('{"error":"none"}', 404)),
    );
    expect(
      await source.fetchLatest(platform: UpdatePlatform.android),
      isNull,
    );
  });

  test('sends the read token', () async {
    String? authorization;
    final source = CiFeedSource(
      endpoint: Uri.parse('https://updates.example.com'),
      appId: 'private-app',
      token: 'secret',
      client: MockClient((request) async {
        authorization = request.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'version': '1.0.1',
            'platform': 'android',
            'artifacts': [
              {'name': 'app.apk', 'url': 'https://cdn.example.com/app.apk'},
            ],
          }),
          200,
        );
      }),
    );
    await source.fetchLatest(platform: UpdatePlatform.android);
    expect(authorization, 'Bearer secret');
  });
}
