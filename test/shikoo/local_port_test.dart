import 'dart:async';

import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/app/windows_proxy.dart';
import 'package:fl_clash/shikoo/app/wininet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:proxy/proxy_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Windows extends ProxyPlatform {
  final calls = <String>[];

  @override
  Future<bool> startProxy(int port, List<String> bypassDomain) async {
    calls.add('start $port');
    return true;
  }

  @override
  Future<bool> stopProxy() async {
    calls.add('stop');
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

    ShikooSystemProxy launch() => ShikooSystemProxy(
      windows,
      () => 7890,
      read: () => now,
      write: (setting) {
        written.add(setting);
        now = setting;
        return true;
      },
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      windows = _Windows();
      now = _before;
      written = [];
    });

    Future<bool> saved() async => (await SharedPreferences.getInstance())
        .containsKey(ShikooSystemProxy.savedKey);

    test("is this app's only while on and at its port", () {
      expect(
        proxyIsOurs(_setting(proxyTypeProxy, '127.0.0.1:7890'), 7890),
        isTrue,
      );
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
      now = _setting(proxyTypeProxy, '127.0.0.1:7890');
      expect(await proxy.startProxy(7890, const []), isTrue);
      expect(await proxy.stopProxy(), isTrue);
      expect(windows.calls, ['start 7890', 'start 7890', 'stop']);
      expect(written, [_before]);
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

      now = _setting(proxyTypeDirect, '127.0.0.1:7890');
      await proxy.startProxy(7890, const []);
      now = _setting(proxyTypeDirect, '127.0.0.1:7890');
      expect(await proxy.stopProxy(), isTrue);
      expect(written, isEmpty, reason: 'turned off by hand while connected');
    });

    test('a crash or a Windows shutdown while connected is undone at the '
        'next launch', () async {
      await launch().startProxy(7890, const []);
      now = _setting(proxyTypeProxy, '127.0.0.1:7890');
      final afterCrash = launch();
      expect(await afterCrash.stopProxy(), isTrue);
      expect(windows.calls, ['start 7890', 'stop']);
      expect(written, [_before]);

      now = _before;
      await launch().startProxy(7890, const []);
      now = _setting(proxyTypeDirect, '127.0.0.1:7890');
      expect(await launch().stopProxy(), isTrue);
      expect(written, [_before, _before]);
      expect(windows.calls, ['start 7890', 'stop', 'start 7890']);
    });

    test('a setting Windows refused stays on disk for the next try', () async {
      final proxy = ShikooSystemProxy(
        windows,
        () => 7890,
        read: () => now,
        write: (_) => false,
      );
      await proxy.startProxy(7890, const []);
      now = _setting(proxyTypeProxy, '127.0.0.1:7890');
      expect(await proxy.stopProxy(), isFalse);
      expect(await saved(), isTrue);
    });
  });
}
