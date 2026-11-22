import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// What a CI job wants to publish.
class PublishRequest {
  const PublishRequest({
    required this.endpoint,
    required this.appId,
    required this.file,
    required this.version,
    required this.platform,
    this.token,
    this.channel = 'stable',
    this.buildNumber,
    this.abi,
    this.releaseNotes,
    this.releaseUrl,
    this.minimumVersion,
    this.urgency = 'medium',
    this.mandatory = false,
    this.externalUrl,
    this.dryRun = false,
    this.writeManifest = false,
  });

  final Uri endpoint;
  final String appId;
  final File file;
  final String version;
  final String platform;
  final String? token;
  final String channel;
  final int? buildNumber;
  final String? abi;
  final String? releaseNotes;
  final String? releaseUrl;
  final String? minimumVersion;
  final String urgency;
  final bool mandatory;

  /// Publish a link instead of uploading the bytes (S3, GitHub, ...).
  final String? externalUrl;

  final bool dryRun;

  /// Writes `app-update.json` next to [file] for the GitHub-artifacts flow.
  final bool writeManifest;
}

/// Result of a successful publish.
class PublishResult {
  const PublishResult({
    required this.buildId,
    required this.manifestUrl,
    required this.manifest,
    this.uploaded = false,
  });

  final String buildId;
  final String manifestUrl;
  final Map<String, dynamic> manifest;
  final bool uploaded;
}

/// Publishes a build to an `app_updater` CI server.
///
/// Returns null on a dry run.
Future<PublishResult?> publishBuild(
  PublishRequest request, {
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final base = request.endpoint.toString().replaceAll(RegExp(r'/$'), '');
  final metadata = <String, dynamic>{
    'version': request.version,
    'platform': request.platform,
    'channel': request.channel,
    if (request.buildNumber != null) 'buildNumber': request.buildNumber,
    if (request.abi != null) 'abi': request.abi,
    if (request.releaseNotes != null) 'releaseNotes': request.releaseNotes,
    if (request.releaseUrl != null) 'releaseUrl': request.releaseUrl,
    if (request.minimumVersion != null)
      'minimumVersion': request.minimumVersion,
    'urgency': request.urgency,
    'mandatory': request.mandatory,
    if (request.externalUrl != null)
      'url': request.externalUrl
    else
      'fileName': p.basename(request.file.path),
  };

  if (request.writeManifest && !request.dryRun) {
    await writeBuildManifest(request, metadata);
  }

  if (request.dryRun) return null;

  final createResponse = await httpClient.post(
    Uri.parse('$base/v1/apps/${request.appId}/builds'),
    headers: _headers(request),
    body: jsonEncode(metadata),
  );
  if (createResponse.statusCode != 201) {
    throw HttpException(
      'Server refused the build: HTTP ${createResponse.statusCode} '
      '${createResponse.body}',
    );
  }
  final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
  final buildId = created['buildId'].toString();

  if (request.externalUrl != null) {
    return PublishResult(
      buildId: buildId,
      manifestUrl: '$base/v1/apps/${request.appId}/latest'
          '?platform=${request.platform}&channel=${request.channel}',
      manifest: metadata,
    );
  }

  final bytes = await request.file.readAsBytes();
  final uploadUrl = created['uploadUrl']?.toString() ??
      '/v1/apps/${request.appId}/builds/$buildId/artifact';
  final uploadResponse = await httpClient.put(
    Uri.parse('$base$uploadUrl'),
    headers: {
      ..._headers(request),
      'content-type': 'application/octet-stream',
      'x-file-name': p.basename(request.file.path),
      'x-sha256': sha256.convert(bytes).toString(),
    },
    body: bytes,
  );
  if (uploadResponse.statusCode != 201) {
    throw HttpException(
      'Artifact upload failed: HTTP ${uploadResponse.statusCode} '
      '${uploadResponse.body}',
    );
  }

  return PublishResult(
    buildId: buildId,
    manifestUrl: '$base/v1/apps/${request.appId}/latest'
        '?platform=${request.platform}&channel=${request.channel}',
    manifest: jsonDecode(uploadResponse.body) as Map<String, dynamic>,
    uploaded: true,
  );
}

/// Writes `app-update.json` next to the build, for the GitHub artifacts flow.
Future<File> writeBuildManifest(
  PublishRequest request,
  Map<String, dynamic> metadata,
) async {
  final bytes = await request.file.readAsBytes();
  final manifest = <String, dynamic>{
    ...metadata,
    'sha256': sha256.convert(bytes).toString(),
    'size': bytes.length,
    'publishedAt': DateTime.now().toUtc().toIso8601String(),
  };
  final target = File(p.join(request.file.parent.path, 'app-update.json'));
  await target.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
  return target;
}

Map<String, String> _headers(PublishRequest request) => <String, String>{
  'content-type': 'application/json',
  'accept': 'application/json',
  if (request.token != null && request.token!.isNotEmpty)
    'authorization': 'Bearer ${request.token}',
};
