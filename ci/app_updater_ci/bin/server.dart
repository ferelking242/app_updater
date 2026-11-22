import 'dart:io';

import 'package:app_updater_ci/app_updater_ci.dart';
import 'package:args/args.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '0.0.0.0', help: 'Bind address.')
    ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Bind port.')
    ..addOption(
      'data',
      defaultsTo: 'data',
      help: 'Directory holding builds and artifacts.',
    )
    ..addOption(
      'token',
      help: 'Write token. Defaults to APP_UPDATER_CI_TOKEN.',
    )
    ..addFlag(
      'private',
      negatable: false,
      help: 'Require the token for reads too.',
    )
    ..addOption(
      'keep',
      defaultsTo: '10',
      help: 'Builds kept per app and channel (0 disables pruning).',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln('app_updater CI server\n\n${parser.usage}');
    return;
  }

  final token = (args['token'] as String?) ??
      Platform.environment['APP_UPDATER_CI_TOKEN'] ??
      '';
  if (token.isEmpty) {
    stderr.writeln(
      'Refusing to start without a write token. Pass --token or set '
      'APP_UPDATER_CI_TOKEN.',
    );
    exitCode = 2;
    return;
  }

  final server = AppUpdaterCiServer(
    dataDir: Directory(args['data'] as String),
    writeToken: token,
    requireTokenForReads: args['private'] as bool,
    keepPerChannel: int.tryParse(args['keep'] as String) ?? 10,
  );

  final httpServer = await shelf_io.serve(
    server.handler,
    args['host'] as String,
    int.parse(args['port'] as String),
  );
  stdout.writeln(
    'app_updater CI server listening on http://${httpServer.address.host}:'
    '${httpServer.port} (data: ${Directory(args['data'] as String).absolute.path})',
  );
}
