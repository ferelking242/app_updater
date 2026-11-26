import 'dart:convert';

import 'package:app_updater/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _release({
  required String tag,
  bool prerelease = false,
  List<String> assets = const <String>[],
}) {
  return <String, dynamic>{
    'tag_name': tag,
    'draft': false,
    'prerelease': prerelease,
    'body': 'notes for $tag',
    'html_url': 'https://github.com/me/app/releases/tag/$tag',
    'published_at': '2026-11-20T10:00:00Z',
    'assets': assets
        .map(
          (name) => <String, dynamic>{
            'name': name,
            'size': 1024,
            'browser_download_url':
                'https://github.com/me/app/releases/download/$tag/$name',
          },
        )
        .toList(),
  };
}

GitHubReleasesSource _source(
  List<Map<String, dynamic>> releases, {
  bool includePrereleases = false,
}) {
  final client = MockClient(
    (request) async => http.Response(jsonEncode(releases), 200),
  );
  return GitHubReleasesSource(
    owner: 'me',
    repo: 'app',
    includePrereleases: includePrereleases,
    client: client,
  );
}

void main() {
  test('reads the newest stable release with an Android asset', () async {
    final source = _source([
      _release(tag: 'v2.0.0', assets: const ['app-2.0.0-ios.ipa']),
      _release(tag: 'v1.9.0', assets: const ['app-1.9.0-arm64.apk']),
    ]);

    final candidate = await source.fetchLatest(
      platform: UpdatePlatform.android,
    );

    expect(candidate, isNotNull);
    expect(candidate!.version, '1.9.0');
    expect(candidate.artifacts.single.fileName, 'app-1.9.0-arm64.apk');
  });

  test('skips prereleases unless asked for them', () async {
    final releases = [
      _release(
        tag: 'android-latest',
        prerelease: true,
        assets: const ['Watchtower-8.1.914-b914-arm64-release.apk'],
      ),
      _release(tag: 'v8.1.573', assets: const ['app-8.1.573-arm64.apk']),
    ];

    final stable = await _source(releases).fetchLatest(
      platform: UpdatePlatform.android,
    );
    expect(stable!.version, '8.1.573');

    final rolling = await _source(
      releases,
      includePrereleases: true,
    ).fetchLatest(platform: UpdatePlatform.android);
    expect(rolling!.version, '8.1.914');
    expect(rolling.channel, 'beta');
    expect(
      rolling.artifacts.single.fileName,
      'Watchtower-8.1.914-b914-arm64-release.apk',
    );
  });

  test('derives the version from the asset name for rolling tags', () async {
    final source = _source(
      [
        _release(
          tag: 'android-latest',
          prerelease: true,
          assets: const ['Watchtower-8.1.914-b914-arm64-release.apk'],
        ),
      ],
      includePrereleases: true,
    );

    final candidate = await source.fetchLatest(
      platform: UpdatePlatform.android,
    );

    expect(candidate!.version, '8.1.914');
  });
}
