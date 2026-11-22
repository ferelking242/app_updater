import 'package:app_updater/app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VersionUtils', () {
    test('normalizes tags, suffixes and build metadata', () {
      expect(VersionUtils.normalize('v1.2.3'), '1.2.3');
      expect(VersionUtils.normalize('release-2.0'), '2.0');
      expect(VersionUtils.normalize('nightly'), isNull);
      expect(VersionUtils.buildNumber('1.2.3+42'), 42);
    });

    test('compares numerically, not lexicographically', () {
      expect(VersionUtils.isNewer('1.9.0', '1.10.0'), isTrue);
      expect(VersionUtils.isNewer('1.10.0', '1.9.0'), isFalse);
      expect(VersionUtils.compare('2.0', '2.0.0'), 0);
      expect(VersionUtils.compare('1.0.0-beta', '1.0.0'), 0);
    });
  });

  group('UpdateCandidate', () {
    test('parses a CI manifest and resolves relative artifact URLs', () {
      final candidate = UpdateCandidate.fromJson(
        <String, dynamic>{
          'version': 'v3.1.4',
          'buildNumber': '77',
          'platform': 'android',
          'releaseNotes': 'Faster downloads',
          'publishedAt': '2026-11-20T10:00:00Z',
          'urgency': 'high',
          'artifacts': [
            {
              'name': 'app-arm64-v8a.apk',
              'url': '/builds/7/artifact',
              'abi': 'arm64-v8a'
            },
            {
              'name': 'app-x86_64.apk',
              'url': '/builds/8/artifact',
              'abi': 'x86_64'
            },
          ],
        },
        baseUri: Uri.parse('https://updates.example.com'),
      );

      expect(candidate.version, '3.1.4');
      expect(candidate.buildNumber, 77);
      expect(candidate.platform, UpdatePlatform.android);
      expect(candidate.urgency, UpdateUrgency.high);
      expect(
        candidate.artifactFor(abi: 'arm64-v8a')?.url,
        'https://updates.example.com/builds/7/artifact',
      );
      expect(candidate.artifactFor(abi: 'x86_64')?.fileName, 'app-x86_64.apk');
    });

    test('falls back to the first artifact when the ABI is unknown', () {
      const candidate = UpdateCandidate(
        version: '1.0.0',
        platform: UpdatePlatform.android,
        artifacts: [
          UpdateArtifact(
              fileName: 'app-universal.apk', url: 'https://x/app.apk'),
        ],
      );
      expect(candidate.artifactFor(abi: 'arm64-v8a')?.fileName,
          'app-universal.apk');
    });

    test('rejects artifacts of another platform', () {
      const candidate = UpdateCandidate(
        version: '1.0.0',
        platform: UpdatePlatform.android,
        artifacts: [
          UpdateArtifact(fileName: 'app-windows.exe', url: 'https://x/app.exe'),
          UpdateArtifact(fileName: 'app.apk', url: 'https://x/app.apk'),
        ],
      );
      expect(candidate.artifactFor()?.fileName, 'app.apk');
    });

    test('round-trips through JSON', () {
      const original = UpdateCandidate(
        version: '2.2.0',
        buildNumber: 12,
        platform: UpdatePlatform.windows,
        channel: 'beta',
        mandatory: true,
        artifacts: [
          UpdateArtifact(
            fileName: 'setup.exe',
            url: 'https://x/setup.exe',
            sizeBytes: 1024,
            sha256: 'abc',
          ),
        ],
      );
      final restored = UpdateCandidate.fromJson(original.toJson());
      expect(restored.version, '2.2.0');
      expect(restored.buildNumber, 12);
      expect(restored.mandatory, isTrue);
      expect(restored.channel, 'beta');
      expect(restored.artifacts.single.sha256, 'abc');
    });
  });
}
