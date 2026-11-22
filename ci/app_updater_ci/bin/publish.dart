import 'dart:io';

import 'package:app_updater_ci/app_updater_ci.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('endpoint', help: 'CI server base URL. Required unless --dry-run.')
    ..addOption('app', help: 'Application id registered on the server.')
    ..addOption('file', abbr: 'f', help: 'Built file to publish.')
    ..addOption('version', abbr: 'v', help: 'Version of the build (1.4.2).')
    ..addOption('platform', defaultsTo: 'android')
    ..addOption('channel', defaultsTo: 'stable')
    ..addOption('build-number')
    ..addOption('abi')
    ..addOption('notes', help: 'Release notes (inline).')
    ..addOption('notes-file', help: 'Read release notes from a file.')
    ..addOption('release-url')
    ..addOption('minimum-version')
    ..addOption('urgency', defaultsTo: 'medium')
    ..addOption('url', help: 'Publish this URL instead of uploading the file.')
    ..addOption('token', help: 'Write token. Defaults to APP_UPDATER_CI_TOKEN.')
    ..addFlag('mandatory', negatable: false)
    ..addFlag(
      'write-manifest',
      negatable: false,
      help: 'Also write app-update.json next to the file (GitHub artifacts).',
    )
    ..addFlag('dry-run', negatable: false, help: 'Validate without uploading.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln('Publish a build to app_updater\n\n${parser.usage}');
    return;
  }

  final appId = args['app'] as String?;
  final version = args['version'] as String?;
  final filePath = args['file'] as String?;
  final endpoint = args['endpoint'] as String?;
  final dryRun = args['dry-run'] as bool;
  final externalUrl = args['url'] as String?;

  if (appId == null || version == null || filePath == null) {
    _fail(parser, '--app, --version and --file are required.');
  }
  if (!dryRun && endpoint == null) {
    _fail(parser, '--endpoint is required (or use --dry-run).');
  }

  final file = File(p.normalize(filePath));
  if (!file.existsSync()) _fail(parser, 'File not found: ${file.path}');

  var notes = args['notes'] as String?;
  final notesFile = args['notes-file'] as String?;
  if (notes == null && notesFile != null) {
    final source = File(notesFile);
    if (!source.existsSync()) _fail(parser, 'Notes file not found: $notesFile');
    notes = await source.readAsString();
  }

  final request = PublishRequest(
    endpoint: Uri.parse(endpoint ?? 'https://example.invalid'),
    appId: appId,
    file: file,
    version: version,
    platform: args['platform'] as String,
    channel: args['channel'] as String,
    buildNumber: int.tryParse(args['build-number'] as String? ?? ''),
    abi: args['abi'] as String?,
    releaseNotes: notes,
    releaseUrl: args['release-url'] as String?,
    minimumVersion: args['minimum-version'] as String?,
    urgency: args['urgency'] as String,
    mandatory: args['mandatory'] as bool,
    externalUrl: externalUrl,
    dryRun: dryRun,
    writeManifest: args['write-manifest'] as bool,
    token: (args['token'] as String?) ??
        Platform.environment['APP_UPDATER_CI_TOKEN'],
  );

  try {
    final result = await publishBuild(request);
    if (result == null) {
      stdout.writeln('Dry run: ${file.path} (${await file.length()} bytes) is valid.');
      return;
    }
    stdout.writeln('Published build ${result.buildId}');
    stdout.writeln('Manifest: ${result.manifestUrl}');
    if (result.uploaded) stdout.writeln('Artifact uploaded.');
  } catch (error) {
    stderr.writeln('Publish failed: $error');
    exitCode = 1;
  }
}

Never _fail(ArgParser parser, String message) {
  stderr.writeln('$message\n\n${parser.usage}');
  exit(2);
}
