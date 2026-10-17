import 'dart:async';

import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:proxy/proxy_platform_interface.dart';

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

String _internetSettings({required bool on, required String server}) =>
    '''

HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings
    ProxyEnable    REG_DWORD    ${on ? '0x1' : '0x0'}
    MigrateProxy    REG_DWORD    0x1
    ProxyServer    REG_SZ    $server
    ProxyOverride    REG_SZ    <local>;localhost;127.*

''';

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

  group("Windows' system proxy", () {
    test('is this app\'s only while on and at its port', () {
      expect(
        proxyIsOurs(
          _internetSettings(on: true, server: '127.0.0.1:7890'),
          7890,
        ),
        isTrue,
      );
      for (final (on, server) in [
        (true, '127.0.0.1:10808'),
        (false, '127.0.0.1:7890'),
        (true, 'http=127.0.0.1:7890;https=127.0.0.1:7890'),
      ]) {
        expect(
          proxyIsOurs(_internetSettings(on: on, server: server), 7890),
          isFalse,
          reason: '$on $server',
        );
      }
      expect(proxyIsOurs('', 7890), isFalse);
    });

    test(
      'is turned off only while it is this app\'s, and set as asked',
      () async {
        final windows = _Windows();
        var settings = _internetSettings(on: true, server: '127.0.0.1:10808');
        final proxy = ShikooSystemProxy(
          windows,
          () => 7890,
          read: () async => settings,
        );

        expect(await proxy.stopProxy(), isTrue);
        expect(windows.calls, isEmpty, reason: 'another app\'s proxy stays');

        expect(await proxy.startProxy(7890, const []), isTrue);
        settings = _internetSettings(on: true, server: '127.0.0.1:7890');
        expect(await proxy.stopProxy(), isTrue);
        expect(windows.calls, ['start 7890', 'stop']);
      },
    );
  });
}
