import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/update_candidate.dart';
import 'update_source.dart';

/// Reads builds from an `app_updater` CI server (see `ci/app_updater_ci`).
///
/// A build published by CI is announced with a single `POST` to the server and
/// becomes immediately visible here:
///
/// ```dart
/// final source = CiFeedSource(
///   endpoint: Uri.parse('https://updates.example.com'),
///   appId: 'watchtower',
///   channel: 'stable',
/// );
/// ```
///
/// Endpoint contract:
/// `GET {endpoint}/v1/apps/{appId}/latest?platform=android&channel=stable`.
class CiFeedSource extends UpdateSource {
  CiFeedSource({
    required this.endpoint,
    required this.appId,
    this.channel = 'stable',
    this.token,
    this.headers,
    this.client,
    super.downloader,
  });

  /// Base URL of the CI server (`https://updates.example.com`).
  final Uri endpoint;

  /// Application identifier registered on the server.
  final String appId;

  /// Default channel (`stable`, `beta`, `nightly`).
  final String channel;

  /// Optional read token, for servers that keep builds private.
  final String? token;

  /// Extra HTTP headers.
  final Map<String, String>? headers;

  final http.Client? client;

  @override
  String get id => 'ci-feed:${endpoint.host}/$appId';

  /// Absolute URL of the manifest for [platform].
  Uri manifestUri({
    required UpdatePlatform platform,
    String? channel,
    String? abi,
  }) {
    return endpoint.resolve('/v1/apps/$appId/latest').replace(
      queryParameters: <String, String>{
        'platform': platform.id,
        'channel': channel ?? this.channel,
        if (abi != null && abi.isNotEmpty) 'abi': abi,
      },
    );
  }

  @override
  Future<UpdateCandidate?> fetchLatest({
    required UpdatePlatform platform,
    String? channel,
    String? abi,
  }) async {
    final httpClient = client ?? http.Client();
    final uri = manifestUri(platform: platform, channel: channel, abi: abi);
    try {
      final response = await httpClient.get(uri, headers: _headers());
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw HttpException(
          'CI feed request failed with HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final body = jsonDecode(response.body);
      final map = _asManifest(body);
      if (map == null || map.isEmpty) return null;
      final candidate = UpdateCandidate.fromJson(map, baseUri: endpoint);
      if (candidate.artifacts.isEmpty && candidate.releaseUrl == null) {
        return null;
      }
      return candidate;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  Map<String, dynamic>? _asManifest(Object? body) {
    if (body is Map) {
      final map = body.cast<String, dynamic>();
      if (map['build'] is Map) {
        return (map['build'] as Map).cast<String, dynamic>();
      }
      if (map['builds'] is List) {
        final builds = (map['builds'] as List).whereType<Map>();
        if (builds.isEmpty) return null;
        return builds.first.cast<String, dynamic>();
      }
      return map;
    }
    if (body is List && body.isNotEmpty) {
      final first =
          body.firstWhere((entry) => entry is Map, orElse: () => null);
      return first == null ? null : (first as Map).cast<String, dynamic>();
    }
    return null;
  }

  Map<String, String> _headers() => <String, String>{
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
        ...?headers,
      };
}
