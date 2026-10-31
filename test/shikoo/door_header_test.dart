import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart'
    show subscriptionOptions;
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';

/// Plain `test`s only: TestWidgetsFlutterBinding would answer every request itself with a 400.

typedef _Seen = ({String line, String? app, String? agent});

class _Site {
  _Site(this.server) {
    server.listen((request) {
      seen.add((
        line: '${request.method} ${request.uri.path}',
        app: request.headers.value(shikooAppHeader),
        agent: request.headers.value(HttpHeaders.userAgentHeader),
      ));
      request.response
        ..statusCode = 200
        ..write('{}');
      unawaited(request.response.close());
    });
  }

  final HttpServer server;
  final seen = <_Seen>[];

  String get url => 'http://127.0.0.1:${server.port}';
}

Future<_Site> _site() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  return _Site(server);
}

Future<void> _quiet(Future<void> Function() call) async {
  try {
    await call();
  } catch (_) {}
}

void main() {
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'ShikooNet',
      packageName: 'com.shikoonet.app',
      version: '1.0.58',
      buildNumber: '58',
    );
  });

  group('the app door gets the app version, and only the door', () {
    test('every call to it carries the version, and the User-Agent stays '
        "Dart's", () async {
      final door = await _site();
      final api = ShikooApi([door.url], null, null, null, () => '1.0.58');

      await _quiet(() => api.start(deviceName: 'x', kind: 'phone'));
      await _quiet(() => api.poll('1', 'secret'));
      await _quiet(() => api.services('token'));
      await _quiet(() => api.report({}, token: 'token'));
      await _quiet(() => api.logout('token'));
      await _quiet(() => api.update('arm64-v8a'));
      await _quiet(() async {
        final file = await api.download(
          '${door.url}/dl/a.apk',
          0,
          CancelToken(),
        );
        await file.data!.stream.drain<void>();
      });

      expect(door.seen.map((s) => s.line), [
        'POST /api/v1/app/login/start',
        'POST /api/v1/app/login/poll',
        'GET /api/v1/app/services',
        'POST /api/v1/app/report',
        'POST /api/v1/app/logout',
        'GET /api/v1/app/update',
        'GET /dl/a.apk',
      ]);
      expect(door.seen.map((s) => s.app).toSet(), {'1.0.58'});
      expect(door.seen.every((s) => s.agent!.startsWith('Dart/')), isTrue);
    });

    test(
      'the app\'s own door client reads the version Settings shows',
      () async {
        final container = ProviderContainer(
          overrides: [shikooVersionProvider.overrideWithValue('1.0.58')],
        );
        addTearDown(container.dispose);

        expect(container.read(shikooApiProvider).version!(), '1.0.58');
      },
    );

    test(
      'the health probe carries it to the door and no other probe does',
      () async {
        final home = await _site();
        final abroad = await _site();
        final door = await _site();

        await runProbes(
          domestic: [home.url],
          international: '${abroad.url}/generate_204',
          doors: [door.url],
          appHeaders: {shikooAppHeader: '1.0.58'},
        );

        expect(door.seen.map((s) => (s.line, s.app)), [
          ('GET /health', '1.0.58'),
        ]);
        expect([...home.seen, ...abroad.seen].map((s) => s.app), [null, null]);
      },
    );

    test(
      'a link at the door gets it, a panel link and a foreign port do not',
      () {
        final door = Uri.parse(shikooApiBases.first);
        var asked = 0;
        String version() {
          asked++;
          return '1.0.58';
        }

        Map<String, String> of(Uri url) => doorHeaders(url, version);

        expect(of(door.resolve('/api/v1/app/sub/abc')), {
          shikooAppHeader: '1.0.58',
        });
        expect(of(Uri.parse('https://sub.4g3.uk/sub/token')), isEmpty);
        expect(of(door.replace(port: door.port + 1)), isEmpty);
        expect(of(door.replace(scheme: 'http', port: 80)), isEmpty);
        expect(asked, 1, reason: 'the version is read for the door alone');
      },
    );

    test('a shelf account at the door is fetched with it, and a panel '
        'subscription without', () {
      final door = shikooApiBases.first;

      expect(subscriptionOptions('$door/api/v1/app/sub/abc').headers, {
        shikooAppHeader: '1.0.58',
      });
      expect(subscriptionOptions('https://sub.4g3.uk/sub/token').headers, {});
      expect(
        subscriptionOptions('$door/api/v1/app/sub/abc').responseType,
        ResponseType.bytes,
      );
    });
  });
}
