import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriveConnection', () {
    test('connecting wins until native confirms', () {
      expect(
        deriveConnection(connecting: true, running: true, error: null),
        ShikooConnection.connecting,
      );
    });

    test('a running tunnel is on, even after an old error', () {
      expect(
        deriveConnection(
          connecting: false,
          running: true,
          error: ShikooError.connectTimeout,
        ),
        ShikooConnection.on,
      );
    });

    test('only a connect timeout is a connection error', () {
      expect(
        deriveConnection(
          connecting: false,
          running: false,
          error: ShikooError.connectTimeout,
        ),
        ShikooConnection.error,
      );
      expect(
        deriveConnection(
          connecting: false,
          running: false,
          error: ShikooError.serverChange,
        ),
        ShikooConnection.off,
      );
    });
  });

  group('waitForTunnel', () {
    const tick = Duration(milliseconds: 1);

    test('returns true once native reports a run time', () async {
      var calls = 0;
      final up = await waitForTunnel(
        () async => ++calls < 3 ? null : DateTime(2026),
        timeout: const Duration(seconds: 5),
        stillWanted: () => true,
        every: tick,
      );
      expect(up, isNotNull);
      expect(calls, 3);
    });

    test('gives up after the timeout, as when consent is refused', () async {
      final up = await waitForTunnel(
        () async => null,
        timeout: const Duration(milliseconds: 30),
        stillWanted: () => true,
        every: tick,
      );
      expect(up, isNull);
    });

    test('time under the consent dialog does not count', () async {
      var calls = 0;
      final up = await waitForTunnel(
        () async => ++calls < 52 ? null : DateTime(2026),
        timeout: const Duration(milliseconds: 200),
        stillWanted: () => true,
        paused: () => calls < 50,
        every: const Duration(milliseconds: 5),
      );
      expect(up, isNotNull, reason: 'a late OK still connects');
    });

    test('stops at once when the user cancels', () async {
      var calls = 0;
      final up = await waitForTunnel(
        () async {
          calls++;
          return null;
        },
        timeout: const Duration(seconds: 5),
        stillWanted: () => calls < 2,
        every: tick,
      );
      expect(up, isNull);
      expect(calls, 2);
    });

    test('a desktop, which has no VPN service, asks its own run state and '
        'the core process', () async {
      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWithBuild((_, _) => 5000),
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
        ],
      );
      addTearDown(container.dispose);
      final native = container.read(nativeRunTimeProvider);
      final start = (await native())!;
      final since = DateTime.now().difference(start);
      expect(since.inMilliseconds, inInclusiveRange(5000, 6000));

      container.read(coreStatusProvider.notifier).value =
          CoreStatus.disconnected;
      expect(await native(), isNull, reason: 'the core process died');

      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      container.read(runTimeProvider.notifier).value = null;
      expect(await native(), isNull, reason: 'stopped');
    });

    test('a desktop tunnel is up only once its adapter is', () async {
      final adapters = <String>{};
      final asked = <String>[];
      final container = ProviderContainer(
        overrides: [
          runTimeProvider.overrideWithBuild((_, _) => 5000),
          coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
          tunUpProvider.overrideWithValue((device) async {
            asked.add(device);
            return adapters.contains(device);
          }),
        ],
      );
      addTearDown(container.dispose);
      final native = container.read(nativeRunTimeProvider);
      expect(await native(), isNotNull, reason: 'proxy mode has no adapter');
      expect(asked, isEmpty);

      container
          .read(patchClashConfigProvider.notifier)
          .update((c) => c.copyWith.tun(enable: true, device: 'ShikooNet'));
      expect(await native(), isNull, reason: 'the helper failed: no TUN');
      adapters.add('ShikooNet');
      expect(await native(), isNotNull);
      expect(asked, ['ShikooNet', 'ShikooNet']);
    });

    test('the port probe asks loopback only, the one address the core binds '
        'with allow-lan off', () async {
      final lan = (await NetworkInterface.list())
          .expand((i) => i.addresses)
          .where((a) => a.type == InternetAddressType.IPv4)
          .firstOrNull;
      if (lan == null) return markTestSkipped('no LAN address here');
      final elsewhere = await ServerSocket.bind(lan, 0);
      addTearDown(elsewhere.close);
      final here = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(here.close);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final free = container.read(localPortFreeProvider);
      expect(await free(elsewhere.port), isTrue);
      expect(await free(here.port), isFalse);
    });
  });

  test('a name another service has gets a Persian number, never "(1)"', () {
    expect(unusedName('user123 · الماس', {}), 'user123 · الماس');
    expect(
      unusedName('user123 · الماس', {'user123 · الماس'}),
      'user123 · الماس ۲',
    );
    final taken = {'a', for (var n = 2; n < 10; n++) 'a ${'۰۱۲۳۴۵۶۷۸۹'[n]}'};
    expect(unusedName('a', taken), 'a ۱۰');
  });

  test('a link with a known username is that service\'s new link', () {
    final a = Profile.normal(
      url: 'https://s.4g3.uk/sub/old',
    ).copyWith(label: 'user123 · الماس');
    final b = Profile.normal(
      url: 'https://s.4g3.uk/sub/b',
    ).copyWith(label: 'user789 · معمولی');
    final profiles = [a, b];
    expect(serviceOf(profiles, 'https://s.4g3.uk/sub/new', 'user123'), a);
    expect(serviceOf(profiles, 'https://S.4g3.uk/sub/b/', null), b);
    expect(serviceOf(profiles, 'https://s.4g3.uk/sub/c', 'user456'), isNull);
    expect(serviceOf(profiles, 'https://s.4g3.uk/sub/c', null), isNull);
  });

  test('a service has ended only by usage the panel sent', () {
    ShikooService service({
      int used = 0,
      DateTime? expire,
      bool known = true,
    }) => ShikooService(
      name: 'user123 · الماس',
      usedBytes: used,
      totalBytes: 10,
      expire: expire,
      usageKnown: known,
    );
    final past = DateTime.now().subtract(const Duration(days: 1));
    expect(service().ended, isNull);
    expect(service(used: 10).ended, ShikooServiceStatus.exhausted);
    expect(service(expire: past).ended, ShikooServiceStatus.expired);
    expect(service(used: 10, known: false).ended, isNull);
  });
}
