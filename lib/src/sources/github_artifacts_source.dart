import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/prepared_update.dart';
import '../models/update_candidate.dart';
import '../utils/version_utils.dart';
import 'update_source.dart';

/// Reads builds published as **GitHub Actions artifacts**.
///
/// Artifacts are not versioned by GitHub, so the version is resolved from, in
/// order: the artifact name (`myapp-android-arm64-1.4.2`), the workflow run
/// title, then the branch name. When none of them contains a version, the run
/// is skipped unless [versionResolver] is provided.
///
/// The recommended CI setup (see `ci/github-actions/publish.yml`) uploads the
/// built file together with an `app-update.json` manifest. The manifest is read
/// after the download and always wins over name-based detection.
class GitHubArtifactsSource extends UpdateSource {
  GitHubArtifactsSource({
    required this.owner,
    required this.repo,
    this.workflow,
    this.branch,
    this.token,
    this.headers,
    this.apiBase = 'https://api.github.com',
    this.versionResolver,
    this.maxRuns = 20,
    this.client,
    super.downloader,
  });

  /// Repository owner (user or organisation).
  final String owner;

  /// Repository name.
  final String repo;

  /// Workflow file name (`build-release.yml`), workflow name or numeric id.
  /// When null, every workflow is considered.
  final String? workflow;

  /// Restrict runs to a branch (`main`). When null, the default branch is used
  /// by GitHub's API only if no branch filter is sent, which returns runs from
  /// every branch; pass a branch to get predictable results.
  final String? branch;

  /// Token used for private repositories and to avoid the anonymous rate
  /// limit (60 requests/hour).
  final String? token;

  /// Extra headers merged into every API request.
  final Map<String, String>? headers;

  /// GitHub Enterprise base URL.
  final String apiBase;

  /// Last chance to derive a version from a run that has no version in its
  /// name. Return null to skip the run.
  final String? Function(String artifactName, Map<String, dynamic> run)?
      versionResolver;

  /// How many workflow runs are inspected before giving up.
  final int maxRuns;

  final http.Client? client;

  @override
  String get id => 'github-artifacts:$owner/$repo';

  @override
  Future<UpdateCandidate?> fetchLatest({
    required UpdatePlatform platform,
    String? channel,
    String? abi,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final runs = await _listRuns(httpClient, branch);
      for (final run in runs) {
        if (run['conclusion'] != 'success') continue;
        final runId = run['id'];
        if (runId == null) continue;

        final artifacts = await _listArtifacts(httpClient, runId);
        for (final artifact in artifacts) {
          if (artifact['expired'] == true) continue;
          final name = (artifact['name'] ?? '').toString();
          final candidate = _candidateFor(
            run: run,
            artifact: artifact,
            name: name,
            platform: platform,
            channel: channel,
            abi: abi,
          );
          if (candidate != null) return candidate;
        }
      }
    } finally {
      if (client == null) httpClient.close();
    }
    return null;
  }

  @override
  Future<PreparedUpdate> prepareDownload(
    UpdateCandidate candidate,
    UpdateArtifact artifact, {
    required Directory workDir,
    Map<String, String>? headers,
    DownloadProgressCallback? onProgress,
  }) {
    return super.prepareDownload(
      candidate,
      artifact,
      workDir: workDir,
      headers: _requestHeaders(extra: headers),
      onProgress: onProgress,
    );
  }

  UpdateCandidate? _candidateFor({
    required Map<String, dynamic> run,
    required Map<String, dynamic> artifact,
    required String name,
    required UpdatePlatform platform,
    required String? channel,
    required String? abi,
  }) {
    if (!_matchesPlatform(name, platform)) return null;
    if (abi != null && abi.isNotEmpty && !_matchesAbi(name, abi)) return null;

    final artifactChannel = _channelOf(name);
    if (channel != null &&
        channel != artifactChannel &&
        artifactChannel != 'stable') {
      return null;
    }

    final version = _versionOf(name, run);
    if (version == null) return null;

    final downloadUrl =
        (artifact['archive_download_url'] ?? artifact['url'])?.toString();
    if (downloadUrl == null || downloadUrl.isEmpty) return null;

    return UpdateCandidate(
      version: version,
      buildNumber: parseIntOrNull(run['run_number']),
      platform: platform,
      channel: artifactChannel,
      releaseNotes: (run['display_title'] ?? run['name'])?.toString(),
      publishedAt: DateTime.tryParse(
          (run['updated_at'] ?? run['created_at'] ?? '').toString()),
      releaseUrl: run['html_url']?.toString(),
      artifacts: <UpdateArtifact>[
        UpdateArtifact(
          fileName: '$name.zip',
          url: downloadUrl,
          sizeBytes: parseIntOrNull(artifact['size_in_bytes']),
          abi: abi,
        ),
      ],
      metadata: <String, dynamic>{
        'provider': 'github-actions',
        'runId': run['id'],
        'runNumber': run['run_number'],
        'headSha': run['head_sha'],
        'workflow': run['path'] ?? run['name'],
        'artifactName': name,
      },
    );
  }

  Future<List<Map<String, dynamic>>> _listRuns(
    http.Client httpClient,
    String? branch,
  ) async {
    final query = <String, String>{
      'status': 'success',
      'per_page': '$maxRuns',
      if (branch != null && branch.isNotEmpty) 'branch': branch,
    };
    final uri = Uri.parse('$apiBase/repos/$owner/$repo/actions/runs')
        .replace(queryParameters: query);
    final response = await httpClient.get(uri, headers: _requestHeaders());
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) {
      throw HttpException(
        'GitHub runs request failed with HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final runs = (body['workflow_runs'] as List?) ?? const [];
    return runs
        .whereType<Map>()
        .map((run) => run.cast<String, dynamic>())
        .where(_matchesWorkflow)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _listArtifacts(
    http.Client httpClient,
    Object runId,
  ) async {
    final uri = Uri.parse(
      '$apiBase/repos/$owner/$repo/actions/runs/$runId/artifacts',
    );
    final response = await httpClient.get(uri, headers: _requestHeaders());
    if (response.statusCode != 200) return const [];
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final artifacts = (body['artifacts'] as List?) ?? const [];
    return artifacts
        .whereType<Map>()
        .map((artifact) => artifact.cast<String, dynamic>())
        .toList(growable: false);
  }

  bool _matchesWorkflow(Map<String, dynamic> run) {
    final target = workflow;
    if (target == null || target.isEmpty) return true;
    final path = (run['path'] ?? '').toString();
    final name = (run['name'] ?? '').toString();
    final id = run['workflow_id']?.toString() ?? '';
    final file = path.split('/').last;
    return id == target || name == target || file == target;
  }

  String? _versionOf(String artifactName, Map<String, dynamic> run) {
    final fromArtifact = _firstVersion(artifactName);
    if (fromArtifact != null) return fromArtifact;

    for (final key in const ['display_title', 'name', 'head_branch']) {
      final fromRun = _firstVersion(run[key]?.toString());
      if (fromRun != null) return fromRun;
    }
    return versionResolver?.call(artifactName, run);
  }

  String? _firstVersion(String? value) {
    if (value == null) return null;
    final match =
        RegExp(r'(?:^|[^0-9])v?(\d+\.\d+(?:\.\d+)*)').firstMatch(value);
    final found = match?.group(1);
    return found == null ? null : VersionUtils.normalize(found);
  }

  static String _channelOf(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('nightly')) return 'nightly';
    if (lower.contains('beta')) return 'beta';
    if (lower.contains('alpha')) return 'alpha';
    return 'stable';
  }

  static bool _matchesPlatform(String name, UpdatePlatform platform) {
    final lower = name.toLowerCase();
    switch (platform) {
      case UpdatePlatform.android:
        return !lower.contains('ios') &&
            !lower.contains('windows') &&
            !lower.contains('linux') &&
            !lower.contains('macos');
      case UpdatePlatform.ios:
        return lower.contains('ios') || lower.contains('ipa');
      case UpdatePlatform.windows:
        return lower.contains('windows') || lower.contains('win');
      case UpdatePlatform.linux:
        return lower.contains('linux');
      case UpdatePlatform.macos:
        return lower.contains('macos') ||
            lower.contains('mac') ||
            lower.contains('darwin');
      case UpdatePlatform.web:
      case UpdatePlatform.unknown:
        return true;
    }
  }

  static bool _matchesAbi(String name, String abi) {
    final lower = name.toLowerCase();
    final normalized = abi.toLowerCase();
    if (lower.contains(normalized)) return true;
    switch (normalized) {
      case 'arm64-v8a':
        return lower.contains('arm64') || lower.contains('aarch64');
      case 'armeabi-v7a':
        return lower.contains('armv7') || lower.contains('armeabi');
      case 'x86_64':
        return lower.contains('x86_64') || lower.contains('x64');
      default:
        return false;
    }
  }

  Map<String, String> _requestHeaders({Map<String, String>? extra}) {
    final result = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      ...?headers,
      ...?extra,
    };
    return result;
  }

  /// Manifest file name expected inside published artifacts.
  static String get manifestFileName => 'app-update.json';
}
