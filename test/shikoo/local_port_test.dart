import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/app/windows_proxy.dart';
import 'package:fl_clash/shikoo/app/wininet.dart';
import 'package:fl_clash/shikoo/engine/mode.dart' show shikooDesktopPort;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:proxy/proxy_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Core extends Mock implements CoreHandlerInterface {}

/// The test binding answers every HttpClient request with 400 and never sends it.
class _RealHttp extends HttpOverrides {}

class _Windows extends ProxyPlatform {
  final calls = <String>[];
  void Function()? onStart;
  void Function()? onStop;

  @override
  Future<bool> startProxy(int port, List<String> bypassDomain) async {
    calls.add('start $port');
    onStart?.call();
    return true;
  }

  @override
  Future<bool> stopProxy() async {
    calls.add('stop');
    onStop?.call();
    return true;
  }
}

WinProxy _setting(int flags, [String? server]) =>
    (flags: flags, server: server, bypass: null, pac: null);

/// Windows' own default: no proxy, "Automatically detect settings" on.
const WinProxy _before = (
  flags: proxyTypeDirect | 8,
  server: 'corp:3128',
  bypass: '<local>',
  pac: 'http://wpad/wpad.dat',
);

void main() {
  test('the port password and the core log reach the core only after its '
      'first config, the log on every start', () async {
    final core = _Core();
    when(core.startLog).thenAnswer((_) {});
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    final pushed = <List<String>>[];
    container.listen(
      updateParamsProvider,
      (_, next) => pushed.add(next.authentication),
    );
    final attached = Completer<void>();

    final locking = afterAttach(attached.future, container, desktop: false);
    await pumpEventQueue();
    expect(pushed, isEmpty);
    verifyNever(core.startLog);

    attached.complete();
    await locking;
    await pumpEventQueue();
    expect(pushed.single, hasLength(1));
    verify(core.startLog).called(1);

    await afterAttach(Future.value(), container, desktop: false);
    await pumpEventQueue();
    expect(pushed, hasLength(1));
    verify(core.startLog).called(1);
  });

  test('a desktop port has no password, not even one set before, and only '
      'this machine reaches it', () {
    final android = portLock(const NetworkProps(), desktop: false);
    expect(android.authentication.credentials, hasLength(1));
    expect(
      portLock(android, desktop: true).authentication.credentials,
      isEmpty,
    );
    final lan = const PatchClashConfig().copyWith(allowLan: true);
    expect(shikooClashConfig(lan).allowLan, isFalse);
  });

  test('a desktop port is none of the ones other proxy apps take', () {
    const c = PatchClashConfig();
    final port = shikooClashConfig(c, desktop: true).mixedPort;
    expect(port, shikooDesktopPort);
    expect([7890, 7891, 7897, 10808, 10809, 1080, 2080], isNot(contains(port)));
    expect(port, inExclusiveRange(15000, 49152));
    expect(shikooClashConfig(c).mixedPort, c.mixedPort);
  });

  group("Windows' system proxy", () {
    late _Windows windows;
    late WinProxy? now;
    late List<WinProxy> written;
    late Set<int> answering;
    late List<String> asked;
    var refuse = false;

    final ours = _setting(proxyTypeDirect | proxyTypeProxy, '127.0.0.1:7890');

    ShikooSystemProxy launch([int port = 7890]) => ShikooSystemProxy(
      windows,
      () => port,
      read: () => now,
      write: (setting) {
        if (refuse) return false;
        written.add(setting);
        now = setting;
        return true;
      },
      listening: (host, port) async {
        asked.add('$host:$port');
        return answering.contains(port);
      },
      guard: () async {},
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      windows = _Windows()
        ..onStart = (() => now = ours)
        ..onStop = (() => now = _setting(proxyTypeDirect, now?.server));
      now = _before;
      written = [];
      answering = {};
      asked = [];
      refuse = false;
    });

    Future<bool> saved() async => (await SharedPreferences.getInstance())
        .containsKey(ShikooSystemProxy.savedKey);

    test('every connect asks the helper to guard this process, without '
        'waiting for its answer', () async {
      var guards = 0;
      final proxy = ShikooSystemProxy(
        windows,
        () => 7890,
        read: () => now,
        write: (_) => true,
        guard: () {
          guards++;
          return Completer<void>().future;
        },
      );
      expect(await proxy.startProxy(7890, const []), isTrue);
      expect(await proxy.startProxy(7890, const []), isTrue);
      expect(await proxy.stopProxy(), isTrue);
      expect(guards, 2);
    });

    test("the guard posts this process's pid to the helper, and a helper "
        'that is not there is no error', () async {
      final helper = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final asked = Completer<String>();
      helper.listen((request) async {
        final body = await utf8.decodeStream(request);
        asked.complete(
          '${request.method} ${request.uri.path} '
          '${request.headers.contentType?.mimeType} $body',
        );
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });
      await HttpOverrides.runWithHttpOverrides(() async {
        final port = helper.port;
        await guardThisProcess(port: port);
        expect(await asked.future, 'POST /guard application/json {"pid":$pid}');
        await helper.close(force: true);
        await guardThisProcess(port: port);
      }, _RealHttp());
    });

    test("is this app's only while on and at its port", () {
      expect(proxyIsOurs(ours, 7890), isTrue);
      expect(
        proxyIsOurs(_setting(proxyTypeProxy | 8, '127.0.0.1:7890'), 7890),
        isTrue,
      );
      for (final setting in [
        _setting(proxyTypeProxy, '127.0.0.1:10808'),
        _setting(proxyTypeDirect, '127.0.0.1:7890'),
        _setting(proxyTypeProxy, 'http=127.0.0.1:7890;https=127.0.0.1:7890'),
        _setting(proxyTypeProxy),
      ]) {
        expect(proxyIsOurs(setting, 7890), isFalse, reason: '$setting');
      }
    });

    test('goes back to the setting from before the first connect, '
        'auto-detect and setup script included', () async {
      final proxy = launch();
      expect(await proxy.stopProxy(), isTrue);
      expect(windows.calls, isEmpty);

      expect(await proxy.startProxy(7890, const []), isTrue);
      expect(await proxy.startProxy(7890, const []), isTrue);
      expect(await proxy.stopProxy(), isTrue);
      expect(windows.calls, ['start 7890', 'start 7890', 'stop']);
      expect(written, [_before]);
      expect(asked, isEmpty, reason: 'corp:3128 is not on this computer');
      expect(await saved(), isFalse);
    });

    test("leaves another app's proxy set while connected, and forgets its "
        'own copy', () async {
      final proxy = launch();
      await proxy.startProxy(7890, const []);
      now = _setting(proxyTypeProxy, '127.0.0.1:10808');
      expect(await proxy.stopProxy(), isTrue);
      expect(windows.calls, ['start 7890']);
      expect(written, isEmpty);
      expect(await saved(), isFalse);

      await proxy.startProxy(7890, const []);
      now = _setting(proxyTypeDirect, '127.0.0.1:7890');
      expect(await proxy.stopProxy(), isTrue);
      expect(written, isEmpty, reason: 'turned off by hand while connected');
    });

    test('a crash or a Windows shutdown while connected is undone at the '
        'next launch', () async {
      await launch().startProxy(7890, const []);
      final afterCrash = launch();
      expect(await afterCrash.stopProxy(), isTrue);
      expect(windows.calls, ['start 7890', 'stop']);
      expect(written, [_before]);

      await launch().startProxy(7890, const []);
      now = _setting(proxyTypeDirect, '127.0.0.1:7890');
      expect(await launch().stopProxy(), isTrue);
      expect(written, [_before, _before]);
      expect(windows.calls, ['start 7890', 'stop', 'start 7890']);
    });

    test('at the next launch, our server with other flags than FlClash\'s '
        'stop leaves is a choice made by hand', () async {
      await launch().startProxy(7890, const []);
      now = _setting(proxyTypeDirect | 8, '127.0.0.1:7890');
      expect(await launch().stopProxy(), isTrue);
      expect(written, isEmpty);
      expect(await saved(), isFalse);
    });

    test('a setting Windows refused stays on disk, and the next connect keeps '
        'it rather than what that disconnect left', () async {
      final proxy = launch();
      await proxy.startProxy(7890, const []);
      refuse = true;
      expect(await proxy.stopProxy(), isFalse);
      expect(await saved(), isTrue);

      refuse = false;
      await proxy.startProxy(7890, const []);
      expect(await proxy.stopProxy(), isTrue);
      expect(written, [_before]);
    });

    test('an exit that lands while a connect saves the setting waits for it, '
        'so the setting from before still comes back', () async {
      final proxy = launch();
      await proxy.stopProxy();
      await Future.wait([proxy.startProxy(7890, const []), proxy.stopProxy()]);
      expect(written, [_before]);
      expect(await saved(), isFalse);
    });

    test('a proxy of another app on this computer comes back only while that '
        'app answers; else it is turned off, its auto-detect kept', () async {
      const local = (
        flags: proxyTypeDirect | proxyTypeProxy | 8,
        server: 'http=127.0.0.1:10809;socks=localhost:10808',
        bypass: '<local>',
        pac: null,
      );
      now = local;
      answering = {10808};
      await launch().startProxy(7890, const []);
      await launch().stopProxy();
      expect(written.last, local);

      now = local;
      answering = {};
      await launch().startProxy(7890, const []);
      await launch().stopProxy();
      expect(written.last, (
        flags: proxyTypeDirect | 8,
        server: local.server,
        bypass: '<local>',
        pac: null,
      ));
      expect(asked, [
        '127.0.0.1:10809',
        'localhost:10808',
        '127.0.0.1:10809',
        'localhost:10808',
      ]);
    });

    test(
      'a proxy elsewhere, or a setup script, comes back as it was',
      () async {
        for (final setting in [
          (
            flags: proxyTypeDirect | proxyTypeProxy,
            server: 'proxy.corp:3128',
            bypass: null,
            pac: null,
          ),
          (
            flags: proxyTypeDirect | 4,
            server: '127.0.0.1:1',
            bypass: null,
            pac: 'http://127.0.0.1:1/proxy.pac',
          ),
        ]) {
          now = setting;
          await launch().startProxy(7890, const []);
          await launch().stopProxy();
          expect(written.last, setting);
        }
        expect(asked, isEmpty);
      },
    );

    test("the uninstaller's restore, with no config to read the port from, "
        'knows our proxy by the port saved at connect', () async {
      await launch().startProxy(7890, const []);
      expect(await launch(0).stopProxy(), isTrue);
      expect(windows.calls, ['start 7890', 'stop']);
      expect(written, [_before]);
      expect(await saved(), isFalse);
    });

    test("the uninstaller's restore ends its process even when it fails, "
        'since the uninstaller waits on it', () async {
      SharedPreferences.setMockInitialValues({
        ShikooSystemProxy.savedKey: '{not json',
      });
      await expectLater(
        restoreProxyAndExit(quit: (code) => throw StateError('exit $code')),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'exit 1'),
        ),
      );
    });

    test("the uninstaller's restore exits 0 once the proxy is back", () async {
      await expectLater(
        restoreProxyAndExit(
          quit: (code) => throw StateError('exit $code'),
          restore: () async => true,
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'exit 0'),
        ),
      );
    });

    testWidgets("the uninstaller's restore gives up after 10 seconds, since "
        'the uninstaller waits on it with no limit of its own', (tester) async {
      final codes = <int>[];
      restoreProxyAndExit(
        quit: (code) {
          codes.add(code);
          throw StateError('exit $code');
        },
        restore: () => Completer<bool>().future,
      ).ignore();
      await tester.pump(const Duration(seconds: 9));
      expect(codes, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(codes, [1]);
    });
  });
}
