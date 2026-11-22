import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/update_candidate.dart';
import '../utils/version_utils.dart';
import 'update_source.dart';

/// Reads builds from GitHub **Releases** assets.
///
/// This is the classic channel: tag the release, attach the binaries, and the
/// app finds them through the API. It complements [GitHubArtifactsSource],
/// which serves unsigned CI builds between two releases.
class GitHubReleasesSource extends UpdateSource {
  GitHubReleasesSource({
    required this.owner,
    required this.repo,
    this.token,
    this.headers,
    this.apiBase = 'https://api.github.com',
    this.includePrereleases = false,
    this.client,
    super.downloader,
  });

  final String owner;
  final String repo;
  final String? token;
  final Map<String, String>? headers;
  final String apiBase;
  final bool includePrereleases;
  final http.Client? client;

  @override
  String get id => 'github-releases:$owner/$repo';

  @override
  Future<UpdateCandidate?> fetchLatest({
    required UpdatePlatform platform,
    String? channel,
    String? abi,
  }) async {
    final httpClient = client ?? http.Client();
    final uri = Uri.parse('$apiBase/repos/$owner/$repo/releases?per_page=30');
    try {
      final response = await httpClient.get(uri, headers: _headers());
      if (response.statusCode != 200) return null;
      final releases = jsonDecode(response.body);
      if (releases is! List) return null;

      // GitHub returns releases newest first, but a recent release may ship
      // no asset for this platform. Keep the highest version instead of the
      // first one so an asset-less release never hides an older usable build.
      UpdateCandidate? best;
      for (final entry in releases.whereType<Map>()) {
        final release = entry.cast<String, dynamic>();
        if (release['draft'] == true) continue;
        if (release['prerelease'] == true && !includePrereleases) continue;

        final tag = release['tag_name']?.toString() ?? '';
        final version = VersionUtils.normalize(tag);
        if (version == null) continue;

        final assets = ((release['assets'] as List?) ?? const [])
            .whereType<Map>()
            .map((asset) => asset.cast<String, dynamic>())
            .toList(growable: false);
        final artifacts = assets
            .map(
              (asset) => UpdateArtifact(
                fileName: (asset['name'] ?? '').toString(),
                url: asset['browser_download_url']?.toString(),
                sizeBytes: parseIntOrNull(asset['size']),
              ),
            )
            .where((artifact) => artifact.url != null)
            .toList(growable: false);

        final matching = artifacts
            .where((artifact) => artifact.matches(platform: platform, abi: abi))
            .toList(growable: false);
        if (matching.isEmpty) continue;

        final candidate = UpdateCandidate(
          version: version,
          platform: platform,
          channel: release['prerelease'] == true ? 'beta' : 'stable',
          releaseNotes: release['body']?.toString(),
          publishedAt:
              DateTime.tryParse(release['published_at']?.toString() ?? ''),
          releaseUrl: release['html_url']?.toString(),
          artifacts: matching,
          metadata: <String, dynamic>{
            'provider': 'github-releases',
            'tag': tag,
          },
        );
        if (best == null ||
            VersionUtils.compare(version, best.version) > 0) {
          best = candidate;
        }
      }
      return best;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  Map<String, String> _headers() => <String, String>{
        'Accept': 'application/vnd.github+json',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
        ...?headers,
      };
}
