import 'dart:convert';
import 'dart:io';

import 'package:app_updater/app_updater.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory workDir;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('app_updater_test_');
  });

  tearDown(() async {
    if (await workDir.exists()) await workDir.delete(recursive: true);
  });

  test('picks the newest successful run and matches the artifact', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/actions/runs')) {
        return http.Response(
          jsonEncode({
            'workflow_runs': [
              {
                'id': 1,
                'conclusion': 'success',
                'run_number': 41,
                'display_title': 'Nightly build',
                'path': '.github/workflows/build.yml',
                'head_sha': 'abc',
                'updated_at': '2026-11-21T08:00:00Z',
                'html_url': 'https://github.com/me/app/actions/runs/1',
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/runs/1/artifacts')) {
        return http.Response(
          jsonEncode({
            'artifacts': [
              {
                'name': 'app-ios-1.0.0',
                'expired': false,
                'size_in_bytes': 10,
                'archive_download_url': 'https://api.github.com/ios.zip',
              },
              {
                'name': 'app-android-arm64-v8a-2.4.1',
                'expired': false,
                'size_in_bytes': 2048,
                'archive_download_url': 'https://api.github.com/android.zip',
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final source = GitHubArtifactsSource(
      owner: 'me',
      repo: 'app',
      workflow: 'build.yml',
      client: client,
    );

    final candidate = await source.fetchLatest(
      platform: UpdatePlatform.android,
      abi: 'arm64-v8a',
    );

    expect(candidate, isNotNull);
    expect(candidate!.version, '2.4.1');
    expect(candidate.buildNumber, 41);
    expect(candidate.channel, 'stable');
    expect(
        candidate.artifacts.single.url, 'https://api.github.com/android.zip');
    expect(candidate.metadata['runId'], 1);
  });

  test('skips runs without any parseable version', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/actions/runs')) {
        return http.Response(
          jsonEncode({
            'workflow_runs': [
              {'id': 9, 'conclusion': 'success', 'path': 'ci.yml'},
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/runs/9/artifacts')) {
        return http.Response(
          jsonEncode({
            'artifacts': [
              {
                'name': 'debug-bundle',
                'expired': false,
                'archive_download_url': 'https://api.github.com/debug.zip',
              },
            ],
          }),
          200,
        );
      }
      return http.Response('', 404);
    });

    final source =
        GitHubArtifactsSource(owner: 'me', repo: 'app', client: client);
    final candidate =
        await source.fetchLatest(platform: UpdatePlatform.android);
    expect(candidate, isNull);
  });

  test('downloads the artifact zip and reads app-update.json', () async {
    final archiveBytes = _buildArchive({
      'app-update.json': jsonEncode({
        'version': '5.0.3',
        'releaseNotes': 'From the build manifest',
      }),
      'build/app-arm64-v8a.apk': 'fake apk bytes',
    });

    final client = MockClient((request) async {
      if (request.url.toString() == 'https://api.github.com/android.zip') {
        return http.Response.bytes(archiveBytes, 200, headers: {
          'content-type': 'application/zip',
        });
      }
      return http.Response('', 404);
    });

    final source = GitHubArtifactsSource(
      owner: 'me',
      repo: 'app',
      client: client,
      downloader: ArtifactDownloader(client: client),
    );

    const candidate = UpdateCandidate(
      version: '5.0.0',
      platform: UpdatePlatform.android,
      artifacts: [
        UpdateArtifact(
          fileName: 'app-android-arm64-v8a-5.0.0.zip',
          url: 'https://api.github.com/android.zip',
          abi: 'arm64-v8a',
        ),
      ],
    );

    final prepared = await source.prepareDownload(
      candidate,
      candidate.artifacts.single,
      workDir: workDir,
    );

    expect(prepared.version, '5.0.3');
    expect(prepared.releaseNotes, 'From the build manifest');
    expect(prepared.file.path, endsWith('app-arm64-v8a.apk'));
    expect(await prepared.file.readAsString(), 'fake apk bytes');
    expect(prepared.sha256, hasLength(64));
  });
}

List<int> _buildArchive(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(archive);
}
