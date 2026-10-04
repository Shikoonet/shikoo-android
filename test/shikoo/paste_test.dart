import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:test/test.dart';

Future<Object> _failure(Future<void> Function() request) async {
  try {
    await request();
  } catch (error) {
    return error;
  }
  throw StateError('the request did not fail');
}

void main() {
  group('a Shikoo link', () {
    test('is one a Shikoo panel serves, over https', () {
      for (final link in [
        'https://4g3.uk/sub/abc',
        'https://sub.4g3.uk:2096/sub/abc',
        'HTTPS://SUB.4G3.UK/sub/abc',
      ]) {
        expect(shikooLink(link), link, reason: link);
      }
    });

    test('is found inside a whole copied message', () {
      expect(
        shikooLink('لینک اشتراک شما:\nhttps://s.4g3.uk/sub/abc\nممنون'),
        'https://s.4g3.uk/sub/abc',
      );
    });

    test('is not a look-alike, a foreign panel, or no link at all', () {
      for (final text in [
        'https://evil4g3.uk/sub/abc',
        'https://4g3.uk.evil.com/sub/abc',
        'https://4g3.uk@evil.com/sub/abc',
        'http://sub.4g3.uk/sub/abc',
        'vless://uuid@4g3.uk:443',
        'https://example.com/sub/abc',
        'سلام',
        'http://10.0.2.2:18289/sub',
      ]) {
        expect(shikooLink(text), isNull, reason: text);
      }
    });

    test('in a test build, is also the fake panel on the emulator', () {
      expect(
        shikooLink('http://10.0.2.2:18289/sub', debug: true),
        'http://10.0.2.2:18289/sub',
      );
      expect(shikooLink('http://4g3.uk/sub', debug: true), isNull);
    });
  });

  group('a failed add', () {
    test(
      'is the link when the panel answered, the network when it did not',
      () {
        final request = RequestOptions(path: '/sub');
        expect(
          addFailure(
            DioException.badResponse(
              statusCode: 404,
              requestOptions: request,
              response: Response(requestOptions: request, statusCode: 404),
            ),
          ),
          ShikooPasteError.revoked,
        );
        for (final type in [
          DioExceptionType.connectionError,
          DioExceptionType.connectionTimeout,
          DioExceptionType.receiveTimeout,
          DioExceptionType.unknown,
        ]) {
          expect(
            addFailure(DioException(requestOptions: request, type: type)),
            ShikooPasteError.offline,
            reason: type.name,
          );
        }
        expect(addFailure(TimeoutException('')), ShikooPasteError.offline);
        expect(
          addFailure(const FormatException('not a config')),
          ShikooPasteError.revoked,
        );
      },
    );

    test(
      'reads a real 404 as the link and a refused port as the network',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((call) {
          call.response.statusCode = 404;
          unawaited(call.response.close());
        });
        final url = 'http://127.0.0.1:${server.port}/sub';
        final dio = Dio();
        expect(
          addFailure(await _failure(() => dio.get<void>(url))),
          ShikooPasteError.revoked,
        );
        await server.close(force: true);
        expect(
          addFailure(await _failure(() => dio.get<void>(url))),
          ShikooPasteError.offline,
        );
      },
    );
  });
}
