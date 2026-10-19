import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/desktop/lifecycle.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/desktop/fakes.dart';
import '../helpers/test_profiles.dart';

class _Handler extends Mock implements CoreHandlerInterface {}

class _Setup extends SetupAction {
  _Setup(this.calls);

  final List<String> calls;

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    calls.add('run $running');
    ref.read(runTimeProvider.notifier).value = running ? 0 : null;
    return true;
  }

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async => true;
}

/// FlClash's restart: each one brings the core up unless [outcomes] says otherwise.
class _Core extends CoreAction {
  _Core(this.calls);

  final List<String> calls;
  final outcomes = <bool>[];
  Completer<void>? hold;

  @override
  Future<bool> restartCore() async {
    calls.add('restart');
    final status = ref.read(coreStatusProvider.notifier);
    status.value = CoreStatus.connecting;
    await hold?.future;
    final up = outcomes.isEmpty || outcomes.removeAt(0);
    status.value = up ? CoreStatus.connected : CoreStatus.disconnected;
    return up;
  }
}

class _Desk {
  _Desk({bool desktop = true}) {
    SharedPreferences.setMockInitialValues({});
    final handler = _Handler();
    when(() => handler.asyncTestDelay(any(), any())).thenAnswer(
      (call) async => Delay(
        name: call.positionalArguments[1] as String,
        url: '',
        value: 50,
      ),
    );
    final profile = Profile.normal(url: 'https://panel.invalid/sub');
    container = ProviderContainer(
      overrides: [
        shikooDesktopProvider.overrideWithValue(desktop),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        setupActionProvider.overrideWith(() => _Setup(calls)),
        coreActionProvider.overrideWith(() => core),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(handler)),
        nativeRunTimeProvider.overrideWithValue(() async => tunnel),
        localPortFreeProvider.overrideWithValue((_) async => portFree),
        tunAuthorizeProvider.overrideWithValue(() async => ShikooAdmin.ready),
        trafficPassesProvider.overrideWithValue(() async => true),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentProfileIdProvider.notifier).value = profile.id;
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [Proxy(name: 'هلند ۱', type: 'Vless')],
      ),
    ];
    container
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap('PROXY', 'هلند ۱');
    container.read(initProvider.notifier).value = true;
    container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
    container.listen(shikooStateProvider, (_, _) {});
    controller = container.read(shikooControllerProvider);
  }

  final calls = <String>[];
  late final core = _Core(calls);
  late final ProviderContainer container;
  late final ShikooController controller;
  DateTime? tunnel = DateTime.now();
  bool portFree = true;

  ShikooState get state => container.read(shikooStateProvider);

  int get restarts => calls.where((call) => call == 'restart').length;

  Future<void> connect() async {
    await pumpEventQueue();
    await controller.connect();
    expect(state.connection, ShikooConnection.on);
    calls.clear();
  }

  /// What CoreManager.onCrash does when the core's pipe closes under it.
  void die() => container.read(coreStatusProvider.notifier).value =
      CoreStatus.disconnected;

  /// A start that failed, as CoreAction's: down without ever having been up.
  Future<void> failStart() async {
    container.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    await pumpEventQueue();
    container.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
    await pumpEventQueue();
  }
}

void main() {
  test('a core that dies while connected comes back with the tunnel, on the '
      'computer only', () async {
    final desk = _Desk();
    await desk.connect();
    desk.core.hold = Completer();
    desk.die();
    await pumpEventQueue();
    expect(desk.state.connection, ShikooConnection.connecting);

    desk.core.hold!.complete();
    await pumpEventQueue();
    expect(desk.calls, ['restart']);
    expect(desk.state.connection, ShikooConnection.on);
    expect(desk.state.lastError, isNull);

    final phone = _Desk(desktop: false);
    await phone.connect();
    phone.die();
    await pumpEventQueue();
    expect(phone.calls, isEmpty);
  });

  test('a fourth death within the window is left down: off, with the '
      'error', () async {
    final desk = _Desk();
    await desk.connect();
    for (var death = 1; death <= coreRevives; death++) {
      desk.die();
      await pumpEventQueue();
      expect(desk.state.connection, ShikooConnection.on);
    }
    expect(desk.restarts, coreRevives);

    desk.die();
    await pumpEventQueue();
    expect(desk.restarts, coreRevives);
    expect(desk.calls.last, 'run false');
    expect(desk.state.connection, ShikooConnection.error);
    expect(desk.state.lastError, ShikooError.coreDown);
  });

  test('a restart that met the dead core is asked again, within the same '
      'budget', () async {
    final desk = _Desk();
    await desk.connect();
    desk.core.outcomes.addAll([false, true]);
    desk.die();
    await pumpEventQueue();
    expect(desk.calls, ['restart', 'restart']);
    expect(desk.state.connection, ShikooConnection.on);

    desk.core.outcomes.add(false);
    desk.die();
    await pumpEventQueue();
    expect(desk.restarts, coreRevives);
    expect(desk.state.lastError, ShikooError.coreDown);
  });

  test('disconnect while the core comes back leaves it off, with no '
      'error', () async {
    final desk = _Desk();
    await desk.connect();
    desk.core.hold = Completer();
    desk.die();
    await pumpEventQueue();
    expect(desk.state.connection, ShikooConnection.connecting);

    await desk.controller.disconnect();
    desk.core.hold!.complete();
    await pumpEventQueue();
    expect(desk.calls, ['restart', 'run false']);
    expect(desk.state.connection, ShikooConnection.off);
    expect(desk.state.lastError, isNull);
  });

  test('connect on a core left down restarts it first', () async {
    final desk = _Desk();
    await pumpEventQueue();
    await desk.failStart();
    expect(desk.calls, isEmpty);

    await desk.controller.connect();
    expect(desk.calls, ['restart', 'run true']);
    expect(desk.state.connection, ShikooConnection.on);

    await desk.controller.disconnect();
    await desk.failStart();
    desk.core.outcomes.add(false);
    desk.calls.clear();
    await desk.controller.connect();
    expect(desk.calls, ['restart']);
    expect(desk.state.lastError, ShikooError.coreDown);
  });

  test('a proxy whose port stays free after the restart is not on; once '
      'FlClash drops the run it is off, with the error', () async {
    final desk = _Desk();
    await pumpEventQueue();
    await desk.controller.setMode(ShikooMode.proxy);
    await desk.connect();

    desk.die();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(desk.state.connection, ShikooConnection.connecting);
    desk.container.read(runTimeProvider.notifier).value = null;
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(desk.calls, ['restart', 'run false']);
    expect(desk.state.lastError, ShikooError.coreDown);

    await desk.connect();
    desk.portFree = false;
    desk.die();
    await pumpEventQueue();
    expect(desk.state.connection, ShikooConnection.on);
  });

  test('the lifecycle starts a second Core after an unexpected '
      'disconnect', () async {
    final transport = FakeDesktopCoreTransport();
    final first = FakeLauncher(owner: CoreProcessOwner.helper, pid: 42);
    final resolver = MutableLauncherResolver(first);
    final lifecycle = DesktopCoreLifecycle(
      transportFactory: () => transport,
      launcherResolver: resolver,
      sessionIdFactory: () => first.lease.sessionId,
      verifyPeerPid: true,
      timeouts: const DesktopCoreTimeouts(
        ready: Duration(seconds: 1),
        connection: Duration(seconds: 1),
        disconnection: Duration(seconds: 1),
      ),
    );
    final start = lifecycle.start();
    transport.ready();
    await first.started;
    transport.connect(pid: 42, generation: 1);
    await start;

    transport.disconnect(1);
    await first.lease.stopStarted;
    final second = FakeLauncher(owner: CoreProcessOwner.helper, pid: 43);
    resolver.launcher = second;
    final restart = lifecycle.restart();
    await second.started;
    transport.connect(pid: 43, generation: 2);
    final result = await restart;

    expect(result.outcome, CoreLifecycleOutcome.applied);
    expect(result.session?.pid, 43);
    expect(lifecycle.state, isA<DesktopCoreRunning>());
    expect(first.lease.stopCount, 1);
    expect(second.startCount, 1);
    await lifecycle.close();
  });
}
