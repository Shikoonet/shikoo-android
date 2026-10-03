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

class _Setup extends SetupAction {
  final runs = <bool>[];

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
      setupActionProvider.overrideWith(() => setup),
      coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
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

    pings['آلمان ۱'] = -1;
    await controller.pingAll();
    expect(proxies.picked, [
      'آلمان ۱',
      'هلند ۱',
    ], reason: 'the app had picked it');
    expect(container.read(shikooStateProvider).notice, isA<SilentReplaced>());

    // The user picks the very server the app had picked: from now on it is theirs.
    await controller.selectServer('هلند ۱');
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
}
