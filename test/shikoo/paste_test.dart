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
      ]) {
        expect(shikooLink(link), link, reason: link);
      }
    });

    test('is one service however its host is cased or its path ends', () {
      expect(
        shikooLink('HTTPS://SUB.4G3.UK/sub/AbC/'),
        'https://sub.4g3.uk/sub/AbC',
        reason: 'the token keeps its case',
      );
      expect(
        normalLink('https://Sub.4g3.uk/sub/x/'),
        normalLink('https://sub.4g3.uk/sub/x'),
      );
      expect(shikooLink('https://s.4g3.uk/'), 'https://s.4g3.uk/');
    });

    test('leaves the punctuation and direction marks of a sentence behind', () {
      for (final end in ['،', '.', ',', ')', '»', '\u200f', '\u200e', '.)']) {
        expect(
          shikooLink('لینکت: (https://s.4g3.uk/sub/abc$end ممنون'),
          'https://s.4g3.uk/sub/abc',
          reason: end,
        );
      }
    });

    test('is the first Shikoo link of a message, not its first link', () {
      expect(
        shikooLink(
          'راهنما: https://t.me/shikoonet\nلینک: https://s.4g3.uk/sub/abc',
        ),
        'https://s.4g3.uk/sub/abc',
      );
    });

    test('is never longer than 2048 characters', () {
      final long = 'https://s.4g3.uk/sub/${'a' * 2048}';
      expect(shikooLink(long), isNull);
      expect(
        shikooLink('$long https://s.4g3.uk/sub/ok'),
        'https://s.4g3.uk/sub/ok',
      );
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
    final request = RequestOptions(path: '/sub');
    DioException answered(int status) => DioException.badResponse(
      statusCode: status,
      requestOptions: request,
      response: Response(requestOptions: request, statusCode: status),
    );

    test('is the link only when the panel says it does not know it (404, 410), '
        'the network when nothing answered, and otherwise unavailable', () {
      expect(addFailure(answered(404)), ShikooPasteError.revoked);
      expect(addFailure(answered(410)), ShikooPasteError.revoked);
      expect(addFailure(answered(403)), ShikooPasteError.unavailable);
      expect(addFailure(answered(500)), ShikooPasteError.unavailable);
      expect(addFailure(answered(503)), ShikooPasteError.unavailable);
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
        addFailure(const FormatException('no servers')),
        ShikooPasteError.unavailable,
      );
    });

    test('reads a real 404 as the link, a 500 as the panel and a refused port '
        'as the network', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((call) {
        call.response.statusCode = call.uri.path == '/boom' ? 500 : 404;
        unawaited(call.response.close());
      });
      final url = 'http://127.0.0.1:${server.port}';
      final dio = Dio();
      expect(
        addFailure(await _failure(() => dio.get<void>('$url/sub'))),
        ShikooPasteError.revoked,
      );
      expect(
        addFailure(await _failure(() => dio.get<void>('$url/boom'))),
        ShikooPasteError.unavailable,
      );
      await server.close(force: true);
      expect(
        addFailure(await _failure(() => dio.get<void>('$url/sub'))),
        ShikooPasteError.offline,
      );
    });
  });

  group('a config', () {
    test('with a server in either YAML style, or an entry whose name it '
        'cannot read, has servers: refusing a working one costs more', () {
      const flow =
          'proxies:\n  - {name: "آلمان ۱", type: vless, server: a.b}\n'
          'proxy-groups:\n  - {name: PROXY, type: select, proxies: ["آلمان ۱"]}\n';
      const block =
          'mixed-port: 7890\nproxies:\n- name: Germany 1\n  type: vless\n'
          '  alpn:\n    - h2\nrules:\n- MATCH,PROXY\n';
      const nameLater = 'proxies:\n  - type: vless\n    name: x\n';
      for (final config in [flow, block, nameLater]) {
        expect(hasServers(config), isTrue, reason: config);
      }
    });

    test('that is empty, a web page, or only the info rows has none', () {
      const infoOnly =
          'proxies:\n  - {name: "V3.7.9 🆔 : (user123)", type: vless}\n'
          '  - {name: "قبل از اتصال به‌روزرسانی کنید", type: vless}\n'
          'proxy-groups:\n  - {name: PROXY, type: select}\n';
      for (final config in [
        '',
        '<!doctype html><html><body>Login</body></html>',
        'proxies:\nrules:\n  - MATCH,DIRECT\n',
        'mixed-port: 7890\n',
        infoOnly,
      ]) {
        expect(hasServers(config), isFalse, reason: config);
      }
    });
  });
}
