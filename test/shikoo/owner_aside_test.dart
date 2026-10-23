import 'dart:async';
import 'dart:io';

import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plain `test`s only: TestWidgetsFlutterBinding would answer every request itself with a 400.

/// Answers every request with [status]: a site, or FlClash's local proxy.
Future<({int port, List<String> asked})> _answering(int status) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final asked = <String>[];
  server.listen((request) {
    asked.add(request.method);
    request.response.statusCode = status;
    unawaited(request.response.close());
  });
  return (port: server.port, asked: asked);
}

const _limit = Duration(seconds: 3);

Future<ProbeChecks> _probe(int proxyPort) => runProbes(
  domestic: ['http://aparat.invalid/'],
  international: 'http://gstatic.invalid/generate_204',
  doors: ['http://door.invalid'],
  limit: _limit,
  proxy: 'PROXY 127.0.0.1:$proxyPort',
);

void main() {
  test('through the local proxy, its own 502 is no Iranian site, and nothing '
      'else passes on it either', () async {
    final proxy = await _answering(HttpStatus.badGateway);

    final checks = await _probe(proxy.port);

    expect([
      checks.domestic.result,
      checks.international.result,
      checks.door.result,
    ], everyElement('http_502'));
    expect(proxy.asked, unorderedEquals(['HEAD', 'GET', 'GET']));
  });

  test('through the local proxy, any other answer from the Iranian site still '
      'counts', () async {
    final proxy = await _answering(HttpStatus.movedPermanently);

    expect((await _probe(proxy.port)).domestic.result, 'ok');
  });

  test(
    'direct, a 502 from the Iranian site itself is still an answer',
    () async {
      final site = await _answering(HttpStatus.badGateway);

      final checks = await runProbes(
        domestic: ['http://127.0.0.1:${site.port}/'],
        international: 'http://127.0.0.1:${site.port}/generate_204',
        doors: ['http://127.0.0.1:${site.port}'],
        limit: _limit,
      );

      expect(checks.domestic.result, 'ok');
    },
  );
}
