import 'dart:io';

import 'package:app_updater/src/services/artifact_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final payload = List<int>.generate(200000, (index) => index % 251);

  late HttpServer server;
  late Directory tempDir;
  late ArtifactDownloader downloader;
  var rangeRequests = 0;
  var ignoreRange = false;
  var dropFirstResponse = false;

  Uri url() =>
      Uri.parse('http://${server.address.host}:${server.port}/app.apk');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('artifact_downloader');
    downloader = ArtifactDownloader();
    rangeRequests = 0;
    ignoreRange = false;
    dropFirstResponse = false;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        final response = request.response;
        if (request.method == 'HEAD') {
          response.headers.contentLength = payload.length;
          await response.close();
          return;
        }

        var start = 0;
        final range = request.headers.value(HttpHeaders.rangeHeader);
        if (range != null && range.startsWith('bytes=')) {
          rangeRequests++;
          start = int.parse(range.substring('bytes='.length).split('-').first);
        }
        if (ignoreRange) start = 0;

        final body = payload.sublist(start);
        response.statusCode =
            start > 0 ? HttpStatus.partialContent : HttpStatus.ok;
        response.headers.contentLength = body.length;
        if (start > 0) {
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${payload.length - 1}/${payload.length}',
          );
        }

        if (dropFirstResponse) {
          dropFirstResponse = false;
          response.add(body.sublist(0, body.length ~/ 2));
          await response.flush();
          await response.close();
          return;
        }
        response.add(body);
        await response.close();
      } catch (_) {
        // Truncated responses make close() throw on purpose in the resume test.
      }
    });
  });

  tearDown(() async {
    downloader.close();
    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  test('resumes a partial download with a Range request', () async {
    final destination = File('${tempDir.path}/Watchtower.apk');
    final partial = File('${destination.path}.part');
    await partial.writeAsBytes(payload.sublist(0, 50000));

    final progress = <int>[];
    await downloader.download(
      url(),
      destination: destination,
      onProgress: (received, total) => progress.add(received),
    );

    expect(rangeRequests, 1);
    expect(await destination.readAsBytes(), payload);
    expect(progress.first, greaterThanOrEqualTo(50000));
    expect(progress.last, payload.length);
  });

  test('restarts when the server ignores the Range header', () async {
    ignoreRange = true;
    final destination = File('${tempDir.path}/Watchtower.apk');
    await File('${destination.path}.part')
        .writeAsBytes(payload.sublist(0, 70000));

    await downloader.download(url(), destination: destination);

    expect(await destination.readAsBytes(), payload);
    expect(await File('${destination.path}.part').exists(), isFalse);
  });

  test('keeps the partial file when the transfer is interrupted', () async {
    dropFirstResponse = true;
    final destination = File('${tempDir.path}/Watchtower.apk');
    final partial = File('${destination.path}.part');

    await expectLater(
      downloader.download(url(), destination: destination),
      throwsA(anything),
    );
    expect(await partial.exists(), isTrue);
    expect(await partial.length(), greaterThan(0));

    await downloader.download(url(), destination: destination);
    expect(rangeRequests, 1);
    expect(await destination.readAsBytes(), payload);
  });
}
