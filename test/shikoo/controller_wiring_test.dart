import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

class _Core extends Mock implements CoreHandlerInterface {}

class _Proxies extends ProxiesAction {
  final picked = <String>[];

  @override
  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    picked.add(proxyName);
    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(groupName, proxyName);
  }

  @override
  void updateGroupsDebounce([Duration? duration]) {}
}

/// FlClash's own delete also clears files and the core, which a unit test has neither of.
class _Profiles extends ProfilesAction {
  @override
  Future<void> deleteProfile(int id) async {
    await ref.read(profilesProvider.notifier).del(id);
    ref.read(currentProfileIdProvider.notifier).value = null;
  }
}

class _Setup extends SetupAction {
  final runs = <bool>[];

  /// What native reports as the tunnel's start; null is a tunnel not up yet.
  DateTime? tunnel;

  /// Whether a real request gets through the tunnel.
  bool traffic = false;

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    runs.add(running);
    return true;
  }
}

const _version = 'V3.7.9 🆔 : (user123) 📊 (67 GB) ⏰ (23)';

({ProviderContainer container, _Core core, _Proxies proxies, _Setup setup})
_home() {
  SharedPreferences.setMockInitialValues({});
  final core = _Core();
  final profile = Profile.normal(url: 'https://panel.invalid/sub');
  final proxies = _Proxies();
  final setup = _Setup();
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(() => TestProfiles([profile])),
      proxiesActionProvider.overrideWith(() => proxies),
      profilesActionProvider.overrideWith(_Profiles.new),
      setupActionProvider.overrideWith(() => setup),
      coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      nativeRunTimeProvider.overrideWithValue(() async => setup.tunnel),
      trafficPassesProvider.overrideWithValue(() async => setup.traffic),
    ],
  );
  addTearDown(container.dispose);
  container.read(currentProfileIdProvider.notifier).value = profile.id;
  container.read(groupsProvider.notifier).value = [
    const Group(
      type: GroupType.Selector,
      name: 'PROXY',
      hidden: false,
      all: [
        Proxy(name: _version, type: 'Vless'),
        Proxy(name: 'آلمان ۱', type: 'Vless'),
        Proxy(name: 'هلند ۱', type: 'Vless'),
      ],
    ),
  ];
  container.listen(shikooStateProvider, (_, _) {});
  return (container: container, core: core, proxies: proxies, setup: setup);
}

void main() {
  test('connect before any answer waits, then starts on the first server that '
      'answered, never row 1', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final netherlands = Completer<void>();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name != 'هلند ۱') return Delay(name: name, url: '', value: -1);
      await netherlands.future;
      return Delay(name: name, url: '', value: 90);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();

    unawaited(controller.connect());
    await pumpEventQueue();
    expect(setup.runs, isEmpty, reason: 'no tunnel before a server answered');
    expect(container.read(shikooStateProvider).waiting, isTrue);

    netherlands.complete();
    await pumpEventQueue();
    expect(proxies.picked, ['هلند ۱'], reason: 'the first that answered');
    expect(setup.runs, [true]);
    verifyNever(() => core.asyncTestDelay(any(), _version));

    // Stops the tunnel wait, which no native service would ever end here.
    await controller.disconnect();
  });

  test(
    'connect during a round waits for its answers, not the round before',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      var round = 1;
      final answers = Completer<void>();
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        if (round == 2) await answers.future;
        final germanyUp = round == 1 && name == 'آلمان ۱';
        final netherlandsUp = round == 2 && name == 'هلند ۱';
        return Delay(
          name: name,
          url: '',
          value: germanyUp ? 50 : (netherlandsUp ? 90 : -1),
        );
      });
      final controller = container.read(shikooControllerProvider);
      await controller.pingAll();
      expect(proxies.picked, ['آلمان ۱']);

      container
          .read(profilesActionProvider.notifier)
          .updateCurrentSelectedMap('PROXY', 'سرور حذف‌شده');
      round = 2;
      unawaited(controller.pingAll());
      unawaited(controller.connect());
      await pumpEventQueue();
      expect(
        setup.runs,
        isEmpty,
        reason: 'آلمان ۱ answered last round and may be down now',
      );

      answers.complete();
      await pumpEventQueue();
      expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
      expect(setup.runs, [true]);

      await controller.disconnect();
    },
  );

  test('connected, a silent pick of the app gives way at round end; the '
      "user's own stays", () async {
    final (:container, :core, :proxies, :setup) = _home();
    final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    final controller = container.read(shikooControllerProvider);
    await controller.pingAll();
    expect(proxies.picked, ['آلمان ۱']);
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);

    pings['آلمان ۱'] = -1;
    await controller.pingAll();
    await pumpEventQueue();
    expect(proxies.picked, [
      'آلمان ۱',
      'هلند ۱',
    ], reason: 'the app had picked it');
    expect(
      container.read(shikooStateProvider).notice,
      isA<SilentReplaced>().having((n) => n.moved, 'moved', isTrue),
    );

    // The user picks the very server the app had picked: from now on it is theirs.
    await controller.selectServer('هلند ۱');
    expect(
      container.read(shikooStateProvider).notice,
      isNull,
      reason: 'the user chose; the old switch is news no more',
    );
    pings
      ..['هلند ۱'] = -1
      ..['آلمان ۱'] = 50;
    await controller.pingAll();
    expect(proxies.picked, ['آلمان ۱', 'هلند ۱', 'هلند ۱']);
    expect(setup.runs, isEmpty);
  });

  test('a live answer ends "no server answered" without connecting', () async {
    final (:container, :core, :proxies, :setup) = _home();
    var alive = false;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      final up = alive && name == 'هلند ۱';
      return Delay(name: name, url: '', value: up ? 90 : -1);
    });
    final controller = container.read(shikooControllerProvider);
    container
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap('PROXY', 'هلند ۱');
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [Proxy(name: 'آلمان ۱', type: 'Vless')],
      ),
    ];
    unawaited(controller.connect());
    await pumpEventQueue();
    expect(container.read(shikooStateProvider).lastError, ShikooError.noServer);

    // The panel brings the selected server back, and this time it answers.
    alive = true;
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: 'آلمان ۱', type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
        ],
      ),
    ];
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.lastError, isNull);
    expect(state.connection, ShikooConnection.off);
    expect(state.selected, 'هلند ۱');
    expect(setup.runs, isEmpty, reason: 'connecting stays with the user');
  });

  test(
    'log out forgets every service, and connect then does nothing',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      when(() => core.asyncTestDelay(any(), any())).thenAnswer(
        (call) async => Delay(
          name: call.positionalArguments[1] as String,
          url: '',
          value: 50,
        ),
      );
      final controller = container.read(shikooControllerProvider);
      await controller.pingAll();
      expect(container.read(shikooStateProvider).service, isNotNull);

      await controller.forgetServices();
      expect(setup.runs, [false], reason: 'disconnected first');
      expect(container.read(profilesProvider), isEmpty);
      expect(container.read(shikooStateProvider).service, isNull);

      await controller.connect();
      expect(setup.runs, [false], reason: 'nothing to connect with');
    },
  );

  test(
    'disconnected, a silent pick of the app is only replaced, not moved',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        return Delay(name: name, url: '', value: pings[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      await controller.pingAll();
      pings['آلمان ۱'] = -1;
      await controller.pingAll();
      expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
      expect(
        container.read(shikooStateProvider).notice,
        isA<SilentReplaced>().having((n) => n.moved, 'moved', isFalse),
      );
    },
  );

  test('each service keeps its own record of what the app picked', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    expect(proxies.picked, ['آلمان ۱'], reason: 'the app, in the first');
    final first = container.read(currentProfileIdProvider);
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    container.read(currentProfileIdProvider.notifier).value = second.id;
    await controller.selectServer('آلمان ۱');

    pings['آلمان ۱'] = -1;
    container.read(currentProfileIdProvider.notifier).value = first;
    await controller.pingAll();
    expect(
      proxies.picked.last,
      'هلند ۱',
      reason: "the user's pick in the second left the first one the app's",
    );

    container.read(currentProfileIdProvider.notifier).value = second.id;
    await controller.pingAll();
    expect(container.read(shikooStateProvider).selected, 'آلمان ۱');
    expect(proxies.picked, hasLength(3), reason: "the user's own stays");
  });

  test(
    'connected, a silent server picked by hand is measured and kept',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        return Delay(name: name, url: '', value: pings[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      container.read(runTimeProvider.notifier).value = 1;
      await pumpEventQueue();

      pings['هلند ۱'] = -1;
      await controller.selectServer('هلند ۱');
      final state = container.read(shikooStateProvider);
      expect(state.selected, 'هلند ۱');
      expect(
        state.selectedServer?.ping,
        -1,
        reason: 'measured, not the old 90',
      );
      expect(state.notice, isNull);
      expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
    },
  );

  test(
    "the tunnel really up, the app's own silent pick moves at once",
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        return Delay(name: name, url: '', value: pings[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      expect(proxies.picked, ['آلمان ۱']);

      pings['آلمان ۱'] = -1;
      // FlClash marks the run at the press, before Android's consent dialog.
      container.read(runTimeProvider.notifier).value = 1;
      setup.tunnel = DateTime(2026);
      await controller.connect();
      await pumpEventQueue();
      expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
      expect(
        container.read(shikooStateProvider).notice,
        isA<SilentReplaced>().having((n) => n.moved, 'moved', isTrue),
      );
    },
  );

  test(
    "under the consent dialog the app's silent pick stays: no tunnel, no proof",
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        return Delay(name: name, url: '', value: pings[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      container.read(runTimeProvider.notifier).value = 1;

      pings['آلمان ۱'] = -1;
      await controller.pingAll();
      await pumpEventQueue();
      expect(proxies.picked, ['آلمان ۱']);
      expect(container.read(shikooStateProvider).notice, isNull);

      setup.tunnel = DateTime(2026);
      await controller.pingAll();
      await pumpEventQueue();
      expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
    },
  );

  test('a refused VPN consent stops connecting and says so', () async {
    final (:container, :core, :proxies, :setup) = _home();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer(
      (call) async => Delay(
        name: call.positionalArguments[1] as String,
        url: '',
        value: 50,
      ),
    );
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    unawaited(controller.connect());
    await pumpEventQueue();
    expect(
      container.read(shikooStateProvider).connection,
      ShikooConnection.connecting,
    );

    controller.onVpnConsent('refused');
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.lastError, ShikooError.vpnRefused);
    expect(state.connection, ShikooConnection.error);
    expect(setup.runs, [true, false]);
  });

  test('the clock counts from the tunnel, not from the press', () async {
    final (:container, :core, :proxies, :setup) = _home();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer(
      (call) async => Delay(
        name: call.positionalArguments[1] as String,
        url: '',
        value: 50,
      ),
    );
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    // A minute under the consent dialog, then a tunnel up for three seconds.
    container.read(runTimeProvider.notifier).value = 63000;
    setup.tunnel = DateTime.now().subtract(const Duration(seconds: 3));
    await controller.connect();

    final state = container.read(shikooStateProvider);
    expect(state.connection, ShikooConnection.on);
    expect(state.connectedFor.inSeconds, inInclusiveRange(3, 5));

    container.read(runTimeProvider.notifier).value = null;
    await pumpEventQueue();
    expect(
      container.read(shikooStateProvider).connection,
      ShikooConnection.off,
    );
  });

  test(
    'a pick whose pings fail but whose traffic flows stays, with no warning; '
    'when traffic fails too, it moves',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        return Delay(name: name, url: '', value: pings[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      container.read(runTimeProvider.notifier).value = 1;
      setup.tunnel = DateTime(2026);

      // WireGuard on Sam's box: every ping silent, traffic fine.
      pings['آلمان ۱'] = -1;
      setup.traffic = true;
      await controller.pingAll();
      await pumpEventQueue();
      var state = container.read(shikooStateProvider);
      expect(proxies.picked, [
        'آلمان ۱',
      ], reason: 'no switch away from a working server');
      expect(state.notice, isNull);
      expect(
        state.selectedServer?.ping,
        greaterThan(0),
        reason: 'not "no answer"',
      );

      setup.traffic = false;
      await controller.pingAll();
      await pumpEventQueue();
      state = container.read(shikooStateProvider);
      expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
      expect(state.notice, isA<SilentReplaced>());
    },
  );

  test(
    'a server the user picked that carries traffic gets no warning',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      when(() => core.asyncTestDelay(any(), any())).thenAnswer(
        (call) async => Delay(
          name: call.positionalArguments[1] as String,
          url: '',
          value: -1,
        ),
      );
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      container.read(runTimeProvider.notifier).value = 1;
      setup
        ..tunnel = DateTime(2026)
        ..traffic = true;
      await controller.selectServer('هلند ۱');
      expect(
        container.read(shikooStateProvider).selectedServer?.ping,
        greaterThan(0),
      );

      setup.traffic = false;
      await controller.selectServer('هلند ۱');
      expect(container.read(shikooStateProvider).selectedServer?.ping, -1);
    },
  );

  test('nothing is measured at the press, under the consent dialog; the '
      'selected server is once native reports the tunnel', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final probes = <String>[];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      probes.add(name);
      return Delay(name: name, url: '', value: name == 'آلمان ۱' ? 50 : 90);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    probes.clear();

    container.read(runTimeProvider.notifier).value = 1;
    unawaited(controller.connect());
    await pumpEventQueue();
    expect(probes, isEmpty);

    setup.tunnel = DateTime(2026);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await pumpEventQueue();
    expect(probes, ['آلمان ۱']);
    await controller.disconnect();
  });

  test('a paste with no link, or not a Shikoo one, sends no request', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final controller = container.read(shikooControllerProvider);
    expect(await controller.pasteService(null), ShikooPasteError.empty);
    expect(await controller.pasteService(' \n '), ShikooPasteError.empty);
    expect(
      await controller.pasteService('https://example.com/sub/token'),
      ShikooPasteError.notShikoo,
    );
    expect(container.read(profilesProvider), hasLength(1));
  });
}
