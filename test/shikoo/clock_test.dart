import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _years14 = Duration(days: 14 * 365);

DioException _handshake(String reason) => DioException(
  requestOptions: RequestOptions(),
  error: HandshakeException(
    'Handshake error in client',
    OSError('CERTIFICATE_VERIFY_FAILED: $reason(handshake.cc:297)'),
  ),
);

/// What app-dev.chopon.uk answers on plain http: a 307 to https, with its clock.
Future<({String url, List<Uri> asked})> _plainServer(DateTime clock) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final asked = <Uri>[];
  server.listen((request) {
    asked.add(request.uri);
    request.response
      ..statusCode = HttpStatus.temporaryRedirect
      ..headers.date = clock
      ..headers.set(HttpHeaders.locationHeader, 'https://example.invalid/');
    unawaited(request.response.close());
  });
  return (
    url: 'http://127.0.0.1:${server.port}/sub/token123?x=1',
    asked: asked,
  );
}

Future<String> _nobody() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return 'http://127.0.0.1:$port/';
}

void main() {
  tearDown(() => shikooSkew = Duration.zero);

  group('the floor', () {
    test('holds back every clock the core cannot load on, and not today', () {
      for (final year in [1970, 2010, 2012, 2013, 2020]) {
        expect(clockTooEarly(DateTime.utc(year, 7)), isTrue, reason: '$year');
      }
      expect(clockTooEarly(DateTime.now()), isFalse);
    });

    test('is the one Android checks before it starts the core itself', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/follow/clash/ServiceStateMachine.kt',
      ).readAsStringSync();
      final millis = RegExp(
        r'CLOCK_FLOOR_MILLIS = (\d+)L',
      ).firstMatch(kotlin)?[1];
      expect(millis, '${shikooClockFloor.millisecondsSinceEpoch}');
    });
  });

  group('a failed HTTPS call', () {
    test(
      'a certificate not valid yet is the clock, even with no answer',
      () async {
        expect(
          await clockFailed(
            _handshake('certificate is not yet valid'),
            await _nobody(),
          ),
          isTrue,
        );
      },
    );

    test('an expired certificate is the clock only when the server says so, '
        'and only the host is asked', () async {
      final behind = await _plainServer(DateTime.now().subtract(_years14));
      expect(
        await clockFailed(_handshake('certificate has expired'), behind.url),
        isTrue,
      );
      expect(shikooSkew.inDays, closeTo(-_years14.inDays, 1));
      expect(behind.asked.single.toString(), '/');

      final right = await _plainServer(DateTime.now());
      expect(
        await clockFailed(_handshake('certificate has expired'), right.url),
        isFalse,
      );
      expect(shikooSkew, Duration.zero);
      expect(
        await clockFailed(
          _handshake('certificate has expired'),
          await _nobody(),
        ),
        isFalse,
      );
    });

    test('anything else is not the clock and asks nothing', () async {
      final server = await _plainServer(DateTime.now().add(_years14));
      for (final error in [
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 10),
          requestOptions: RequestOptions(),
        ),
        _handshake('unable to get local issuer certificate'),
        const SocketException('Connection refused'),
      ]) {
        expect(await clockFailed(error, server.url), isFalse);
      }
      expect(server.asked, isEmpty);
    });
  });

  test('a valid service on a clock 14 years ahead is not ended', () {
    final service = ShikooService(
      name: 'maryam_k · Gold',
      usedBytes: 0,
      totalBytes: 0,
      expire: DateTime.now().subtract(_years14).add(const Duration(days: 10)),
    );
    expect(service.ended, ShikooServiceStatus.expired);
    learnClock(HttpDate.format(DateTime.now().subtract(_years14)));
    expect(service.ended, isNull);
    learnClock(HttpDate.format(DateTime.now().add(const Duration(minutes: 3))));
    expect(shikooSkew, Duration.zero);
  });
}
