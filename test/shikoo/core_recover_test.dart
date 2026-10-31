import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/path.dart';
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
import 'package:fl_clash/shikoo/app/alerts.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:flutter/services.dart';
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
  void Function()? onStop;

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    calls.add('run $running');
    ref.read(runTimeProvider.notifier).value = running ? 0 : null;
    if (!running) onStop?.call();
    return true;
  }

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async => true;
}

/// A restart that joined one under way, which then met the dead core.
const _stillDown = [CoreStatus.disconnected];

/// A core that came up and died again at once: a death of its own.
const _upAndDown = [CoreStatus.connected, CoreStatus.disconnected];

/// FlClash's restart: the core comes up unless [outcomes] gives what it goes through.
class _Core extends CoreAction {
  _Core(this.calls);

  final List<String> calls;
  final outcomes = <List<CoreStatus>>[];
  Completer<void>? hold;

  @override
  Future<bool> restartCore() async {
    calls.add('restart');
    final status = ref.read(coreStatusProvider.notifier);
    status.value = CoreStatus.connecting;
    await hold?.future;
    final next = outcomes.isEmpty
        ? const [CoreStatus.connected]
        : outcomes.removeAt(0);
    for (final value in next) {
      status.value = value;
    }
    return status.value == CoreStatus.connected;
  }
}

/// FlClash's own restart, with only the process swap and initCore faked.
class _RealCore extends CoreAction {
  _RealCore(this.calls);

  final List<String> calls;
  bool initFails = false;

  @override
  Future<CoreLifecycleResult> restartLifecycle() async {
    calls.add('restart');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const CoreLifecycleResult(
      revision: 1,
      outcome: CoreLifecycleOutcome.applied,
    );
  }

  @override
  Future<void> initCore() async {
    if (initFails) throw StateError('init failed');
  }
}

class _Desk {
  _Desk({bool desktop = true, CoreAction? real}) {
    SharedPreferences.setMockInitialValues({});
    final handler = _Handler();
    when(() => handler.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final value = coreUp ? delay : -1;
      await gate?.future;
      return Delay(
        name: call.positionalArguments[1] as String,
        url: '',
        value: value,
      );
    });
    final profile = Profile.normal(url: 'https://panel.invalid/sub');
    container = ProviderContainer(
      overrides: [
        shikooDesktopProvider.overrideWithValue(desktop),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        setupActionProvider.overrideWith(() => setup),
        coreActionProvider.overrideWith(() => real ?? core),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(handler)),
        nativeRunTimeProvider.overrideWithValue(() async {
          final hook = onRunTime;
          onRunTime = null;
          hook?.call();
          return tunnel;
        }),
        localPortFreeProvider.overrideWithValue((_) async {
          final hook = onPort;
          onPort = null;
          hook?.call();
          return portFree;
        }),
        tunAuthorizeProvider.overrideWithValue(() async => ShikooAdmin.ready),
        coreOwnerProvider.overrideWithValue(() => CoreProcessOwner.helper),
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
  late final setup = _Setup(calls);
  late final ProviderContainer container;
  late final ShikooController controller;
  DateTime? tunnel = DateTime.now();
  bool portFree = true;
  int delay = 50;

  /// Holds every ping's answer until completed; a dead core answers -1.
  Completer<void>? gate;

  /// Run inside the next tunnel or port check, before it answers.
  void Function()? onRunTime;
  void Function()? onPort;

  ShikooState get state => container.read(shikooStateProvider);

  int get restarts => calls.where((call) => call == 'restart').length;

  Future<void> connect() async {
    await pumpEventQueue();
    await controller.connect();
    // The traffic check asks for the tunnel once after the connect: done before a test arms onRunTime.
    await pumpEventQueue();
    expect(state.connection, ShikooConnection.on);
    calls.clear();
  }

  /// What CoreManager.onCrash does when the core's pipe closes under it.
  void dieNow() => container.read(coreStatusProvider.notifier).value =
      CoreStatus.disconnected;

  Future<void> die() async {
    dieNow();
    await pumpEventQueue();
  }

  bool get coreUp => container.read(coreStatusProvider) == CoreStatus.connected;

  /// A start that failed, as CoreAction's: down without ever having been up.
  Future<void> failStart() async {
    container.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    await pumpEventQueue();
    container.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
    await pumpEventQueue();
  }

  void expectDown() {
    expect(calls.last, 'run false');
    expect(state.connection, ShikooConnection.error);
    expect(state.lastError, ShikooError.coreDown);
  }
}

void main() {
  setUpAll(() {
    final files = Directory.systemTemp.createTempSync('shikoo-recover-');
    AppPath.supportDirectory = AppPath.temporaryDirectory =
        AppPath.cacheDirectory = () async => files;
  });
  tearDown(() => shikooSkew = Duration.zero);

  test('a core that dies while connected comes back with the tunnel, on the '
      'computer only', () async {
    final desk = _Desk();
    await desk.connect();
    desk.core.hold = Completer();
    await desk.die();
    expect(desk.state.connection, ShikooConnection.connecting);

    desk.core.hold!.complete();
    await pumpEventQueue();
    expect(desk.calls, ['restart']);
    expect(desk.state.connection, ShikooConnection.on);
    expect(desk.state.lastError, isNull);

    final phone = _Desk(desktop: false);
    await phone.connect();
    await phone.die();
    expect(phone.calls, isEmpty);
  });

  test('a death while off: one restart, never connecting, no error', () async {
    final desk = _Desk()..tunnel = null;
    await pumpEventQueue();
    final seen = <ShikooConnection>[];
    desk.container.listen(
      shikooStateProvider.select((s) => s.connection),
      (_, now) => seen.add(now),
    );
    await desk.die();
    expect(desk.calls, ['restart']);
    expect(seen, isNot(contains(ShikooConnection.connecting)));
    expect(desk.state.connection, ShikooConnection.off);
    expect(desk.state.lastError, isNull);
  });

  test('three deaths come back, the fourth within the window is left down: '
      'off, with the error', () async {
    final desk = _Desk();
    await desk.connect();
    for (var death = 1; death <= coreRevives; death++) {
      await desk.die();
      expect(desk.state.connection, ShikooConnection.on);
    }
    expect(desk.restarts, coreRevives);

    await desk.die();
    expect(desk.restarts, coreRevives);
    desk.expectDown();
  });

  test('a core left down is a drop the customer is told of, not a stop of '
      'theirs', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final posts = <String>[];
    const channel = MethodChannel('shikoo/alerts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'post') posts.add((call.arguments as Map)['kind']);
      return call.method == 'target' ? null : true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final settle = alertSettle;
    alertSettle = const Duration(milliseconds: 20);
    addTearDown(() => alertSettle = settle);
    final desk = _Desk();
    await desk.connect();
    desk.controller.foreground = false;
    desk.container.read(shikooAlertsProvider);
    for (var death = 1; death <= coreRevives + 1; death++) {
      await desk.die();
    }
    desk.expectDown();
    await Future<void>.delayed(alertSettle * 4);
    expect(posts, ['dropped']);
  });

  test('once the window has passed, the deaths before it no longer '
      'count', () async {
    final desk = _Desk();
    await desk.connect();
    for (var death = 1; death <= coreRevives; death++) {
      await desk.die();
    }
    shikooSkew = coreReviveWindow + const Duration(seconds: 1);
    await desk.die();
    expect(desk.restarts, coreRevives + 1);
    expect(desk.state.connection, ShikooConnection.on);
  });

  test('a restart that came back down is tried once more and is no death; a '
      'core that came up and died at once is one, counted', () async {
    final desk = _Desk();
    await desk.connect();
    desk.core.outcomes.add(_stillDown);
    await desk.die();
    expect(desk.restarts, 2);
    expect(desk.state.connection, ShikooConnection.on);

    desk.core.outcomes.add(_upAndDown);
    await desk.die();
    expect(desk.restarts, 4);
    expect(desk.state.connection, ShikooConnection.on);

    await desk.die();
    expect(desk.restarts, 4);
    desk.expectDown();
  });

  test('two deaths during one restart are two deaths, each with its '
      'restart', () async {
    final desk = _Desk();
    await desk.connect();
    desk.core.outcomes.add([..._upAndDown, ..._upAndDown]);
    await desk.die();
    expect(desk.restarts, 3);
    expect(desk.state.connection, ShikooConnection.on);

    await desk.die();
    expect(desk.restarts, 3);
    desk.expectDown();
  });

  test('three deaths while the revive waits for the tunnel come back, each '
      'with its restart; the fourth is left down', () async {
    final desk = _Desk();
    await desk.connect();
    desk.tunnel = null;
    for (var death = 1; death <= coreRevives; death++) {
      await desk.die();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(desk.restarts, death);
      expect(desk.state.connection, ShikooConnection.connecting);
    }
    desk.tunnel = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(desk.state.connection, ShikooConnection.on);

    await desk.die();
    expect(desk.restarts, coreRevives);
    desk.expectDown();
  });

  test('a core that dies while the tunnel is read again is not on: that '
      'death gets its restart', () async {
    final desk = _Desk();
    await desk.connect();
    desk.onRunTime = desk.dieNow;
    await desk.die();
    expect(desk.restarts, 2);
    expect(desk.coreUp, isTrue);
    expect(desk.state.connection, ShikooConnection.on);
  });

  test("a core that dies while the proxy's port is read again is not on: that "
      'death gets its restart', () async {
    final desk = _Desk();
    await pumpEventQueue();
    await desk.controller.setMode(ShikooMode.proxy);
    await desk.connect();
    desk
      ..portFree = false
      ..onPort = desk.dieNow;
    await desk.die();
    expect(desk.restarts, 2);
    expect(desk.coreUp, isTrue);
    expect(desk.state.connection, ShikooConnection.on);
  });

  test('a death while the revive gives up and disconnects is answered after '
      'it', () async {
    final desk = _Desk();
    await desk.connect();
    desk
      ..tunnel = null
      ..setup.onStop = desk.dieNow;
    await desk.die();
    desk.container.read(runTimeProvider.notifier).value = null;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(desk.restarts, 2);
    expect(desk.coreUp, isTrue);
    expect(desk.state.lastError, ShikooError.coreDown);
  });

  test('deaths while off say nothing; past the cap the core stays down and the '
      'screen off', () async {
    final desk = _Desk()..tunnel = null;
    await pumpEventQueue();
    for (var death = 1; death <= coreRevives + 1; death++) {
      await desk.die();
    }
    expect(desk.calls, List.filled(coreRevives, 'restart'));
    expect(desk.coreUp, isFalse);
    expect(desk.state.connection, ShikooConnection.off);
    expect(desk.state.lastError, isNull);
  });

  test('a death whose second try fails too is left down after two '
      'restarts', () async {
    final desk = _Desk();
    await desk.connect();
    desk.core.outcomes.addAll([_stillDown, _stillDown]);
    await desk.die();
    expect(desk.restarts, 2);
    desk.expectDown();
  });

  test("FlClash's restart whose initCore fails is left down at once", () async {
    final calls = <String>[];
    final real = _RealCore(calls);
    final desk = _Desk(real: real);
    await desk.connect();
    real.initFails = true;
    await desk.container
        .read(coreActionProvider.notifier)
        .restartCore()
        .catchError((Object _) => false);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, ['restart', 'restart']);
    desk.expectDown();
  });

  test('disconnect while the core comes back leaves it off, with no '
      'error', () async {
    final desk = _Desk();
    await desk.connect();
    desk.core.hold = Completer();
    await desk.die();
    expect(desk.state.connection, ShikooConnection.connecting);

    await desk.controller.disconnect();
    desk.core.hold!.complete();
    await pumpEventQueue();
    expect(desk.calls, ['restart', 'run false']);
    expect(desk.state.connection, ShikooConnection.off);
    expect(desk.state.lastError, isNull);
  });

  test(
    'connect on a core left down restarts it first; one that stays down '
    'fails the connect with its own text, with a server chosen or not',
    () async {
      final desk = _Desk();
      await pumpEventQueue();
      await desk.failStart();
      expect(desk.calls, isEmpty);

      await desk.controller.connect();
      expect(desk.calls, ['restart', 'run true']);
      expect(desk.state.connection, ShikooConnection.on);

      await desk.controller.disconnect();
      await desk.failStart();
      desk.core.outcomes.addAll([_stillDown, _stillDown]);
      desk.calls.clear();
      await desk.controller.connect();
      expect(desk.calls, ['restart']);
      expect(desk.state.connection, ShikooConnection.error);
      expect(desk.state.lastError, ShikooError.coreStart);

      desk.container
          .read(profilesActionProvider.notifier)
          .updateCurrentSelectedMap('PROXY', '');
      await desk.controller.connect();
      expect(desk.restarts, 2);
      expect(desk.state.lastError, ShikooError.coreStart);
    },
  );

  test("FlClash's restart whose initCore keeps failing: a death while off "
      'says nothing, and each connect fails with its own text', () async {
    final calls = <String>[];
    final real = _RealCore(calls);
    final desk = _Desk(real: real)..tunnel = null;
    await pumpEventQueue();
    real.initFails = true;
    await desk.die();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(desk.state.lastError, isNull);
    for (var press = 1; press <= 3; press++) {
      await desk.controller.connect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(desk.state.lastError, ShikooError.coreStart);
    }
  });

  test('a phone, or a computer still starting, connects without restarting '
      'the core', () async {
    final phone = _Desk(desktop: false);
    await pumpEventQueue();
    await phone.failStart();
    await phone.controller.connect();
    await pumpEventQueue();
    expect(phone.calls, ['run true']);

    final starting = _Desk();
    await pumpEventQueue();
    starting.container.read(initProvider.notifier).value = false;
    await starting.failStart();
    await starting.controller.connect();
    await pumpEventQueue();
    expect(starting.calls, ['run true']);
  });

  test('a core that comes back measures the servers again', () async {
    final desk = _Desk()
      ..tunnel = null
      ..delay = -1;
    await pumpEventQueue();
    await desk.controller.pingAll();
    expect(desk.state.servers.single.ping, isNot(50));

    desk.delay = 50;
    await desk.die();
    expect(desk.state.servers.single.ping, 50);
  });

  test('a core that comes back under the tunnel measures the selected server '
      'alone, with no round of the list (Sam, 2026-10-11)', () async {
    final desk = _Desk()..delay = -1;
    await desk.connect();
    desk.delay = 50;
    await desk.die();
    await pumpEventQueue();
    expect(desk.state.connection, ShikooConnection.on);
    expect(desk.state.servers.single.ping, 50);
    expect(desk.state.sorted, isFalse, reason: 'a round would sort the list');
  });

  test("a round's answers from the dead core are dropped once it is back: "
      'the servers are measured again', () async {
    final desk = _Desk()
      ..tunnel = null
      ..delay = -1;
    await pumpEventQueue();
    final first = desk.gate = Completer();
    final round = desk.controller.pingAll();
    await pumpEventQueue();
    desk.core.hold = Completer();
    await desk.die();
    final second = desk.gate = Completer();
    first.complete();
    await pumpEventQueue();

    desk.delay = 50;
    desk.core.hold!.complete();
    await pumpEventQueue();
    desk.gate = null;
    second.complete();
    await round;
    await pumpEventQueue();
    expect(desk.state.servers.single.ping, 50);
  });

  test('one revive at a time: a death while one waits is answered by it, on '
      'its next look', () async {
    final desk = _Desk();
    await desk.connect();
    desk.tunnel = null;
    await desk.die();
    expect(desk.restarts, 1);
    await desk.die();
    expect(desk.restarts, 1);

    desk.tunnel = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(desk.restarts, 2);
    expect(desk.state.connection, ShikooConnection.on);
  });

  test('a death after a mode change or a press of off and on during a revive '
      'is answered once the stale revive ends', () async {
    for (final press in [
      (_Desk desk) async {
        await desk.controller.setMode(ShikooMode.proxy);
        desk.portFree = false;
      },
      (_Desk desk) async {
        await desk.controller.disconnect();
        await desk.controller.connect();
      },
    ]) {
      final desk = _Desk();
      await desk.connect();
      desk.tunnel = null;
      await desk.die();
      desk.tunnel = DateTime.now();
      await press(desk);
      await pumpEventQueue();
      expect(desk.state.connection, ShikooConnection.on);

      await desk.die();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(desk.restarts, 2);
      expect(desk.coreUp, isTrue);
      expect(desk.state.connection, ShikooConnection.on);
      expect(desk.state.lastError, isNull);
    }
  });

  test(
    'a revive that throws is not started again for the deaths it left',
    () async {
      final desk = _Desk();
      await desk.connect();
      desk.tunnel = null;
      var errors = 0;
      await runZonedGuarded(() async {
        await desk.die();
        desk.dieNow();
        desk.container.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }, (_, _) => errors++);
      expect(errors, 1);
    },
  );

  test('a proxy whose port stays free after the restart is not on; once '
      'FlClash drops the run it is off, with the error', () async {
    final desk = _Desk();
    await pumpEventQueue();
    await desk.controller.setMode(ShikooMode.proxy);
    await desk.connect();

    await desk.die();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(desk.state.connection, ShikooConnection.connecting);
    desk.container.read(runTimeProvider.notifier).value = null;
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(desk.calls, ['restart', 'run false']);
    expect(desk.state.lastError, ShikooError.coreDown);

    await desk.connect();
    desk.portFree = false;
    await desk.die();
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
