import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/core/controller.dart';
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
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
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
  var applies = 0;
  DateTime? tunnel;
  bool traffic = true;

  /// Holds an apply open until completed.
  Completer<void>? gate;

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    runs.add(running);
    return true;
  }

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applies++;
    await gate?.future;
    return true;
  }
}

class _ProxyMode extends ShikooModeNotifier {
  @override
  ShikooMode build() => ShikooMode.proxy;
}

class _Timeline extends ShikooDiag {
  final lines = <String>[];

  @override
  void add(String kind, String text, {DateTime? at}) =>
      lines.add('$kind $text');
}

Map<ShikooCore, ShikooCoreSpec> _ready(Set<ShikooCore> cores) => {
  for (final MapEntry(key: core, value: spec) in shikooCoreSpecs.entries)
    core: (
      ready: spec.ready || cores.contains(core),
      shape: spec.shape,
      serves: spec.serves,
    ),
};

/// What the profile says: A and B VLESS, W WireGuard.
const _profile = {
  'proxies': [
    {'name': 'A', 'type': 'vless'},
    {'name': 'B', 'type': 'vless'},
    {'name': 'W', 'type': 'wireguard'},
  ],
  'proxy-groups': [
    {
      'name': 'PROXY',
      'type': 'select',
      'proxies': ['A', 'B', 'W'],
    },
  ],
};

typedef _Home = ({
  ProviderContainer container,
  ShikooController controller,
  _Core core,
  _Proxies proxies,
  _Setup setup,
});

Future<_Home> _home({
  Set<ShikooCore> ready = const {},
  ShikooChoices choices = const {},
  Map<String, String> running = const {
    'A': 'Vless',
    'B': 'Vless',
    'W': 'WireGuard',
  },
  bool proxy = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final core = _Core();
  final profile = Profile.normal(url: 'https://panel.invalid/sub');
  final proxies = _Proxies();
  final setup = _Setup();
  final container = ProviderContainer(
    overrides: [
      tunAuthorizeProvider.overrideWithValue(() async => ShikooAdmin.refused),
      coreOwnerProvider.overrideWithValue(() => CoreProcessOwner.helper),
      profilesProvider.overrideWith(() => TestProfiles([profile])),
      proxiesActionProvider.overrideWith(() => proxies),
      setupActionProvider.overrideWith(() => setup),
      coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      nativeRunTimeProvider.overrideWithValue(() async => setup.tunnel),
      trafficPassesProvider.overrideWithValue(() async => setup.traffic),
      shikooDiagProvider.overrideWithValue(_Timeline()),
      shikooCoreSpecsProvider.overrideWithValue(_ready(ready)),
      if (proxy) ...[
        shikooDesktopProvider.overrideWithValue(true),
        shikooModeProvider.overrideWith(_ProxyMode.new),
      ],
    ],
  );
  addTearDown(container.dispose);
  // Last in, first out: the checks a connect leaves running end before the container goes.
  addTearDown(pumpEventQueue);
  when(() => core.getConfig(any())).thenAnswer((_) async => _profile);
  when(() => core.asyncTestDelay(any(), any())).thenAnswer(
    (call) async =>
        Delay(name: call.positionalArguments[1] as String, url: '', value: 50),
  );
  for (final MapEntry(:key, :value) in choices.entries) {
    await container.read(shikooCoresProvider.notifier).set(key, value);
  }
  container.read(currentProfileIdProvider.notifier).value = profile.id;
  container.read(initProvider.notifier).value = true;
  container.read(groupsProvider.notifier).value = [
    Group(
      type: GroupType.Selector,
      name: 'PROXY',
      hidden: false,
      all: [
        for (final MapEntry(:key, :value) in running.entries)
          Proxy(name: key, type: value),
      ],
    ),
  ];
  container.listen(shikooStateProvider, (_, _) {});
  final controller = container.read(shikooControllerProvider);
  await pumpEventQueue();
  return (
    container: container,
    controller: controller,
    core: core,
    proxies: proxies,
    setup: setup,
  );
}

Future<void> _connectOn(_Home home, String name) async {
  await home.controller.selectServer(name);
  home.container.read(runTimeProvider.notifier).value = 1;
  home.setup.tunnel = DateTime(2026);
  await pumpEventQueue();
}

ShikooServer _server(_Home home, String name) => home.container
    .read(shikooStateProvider)
    .servers
    .firstWhere((server) => server.name == name);

void main() {
  setUpAll(() {
    final files = Directory.systemTemp.createTempSync('shikoo-cores-');
    AppPath.supportDirectory = AppPath.temporaryDirectory =
        AppPath.cacheDirectory = () async => files;
    AppPath.downloadDirectory = () async => files;
  });

  test('each server carries its profile protocol and the core really carrying '
      'it, and a row per protocol says which cores are ready', () async {
    final home = await _home(
      ready: {ShikooCore.xray},
      choices: {ShikooProtocol.vless: ShikooCore.xray},
      running: {'A': 'Socks5', 'B': 'Vless', 'W': 'WireGuard'},
    );

    expect(
      [
        for (final name in ['A', 'B', 'W'])
          (_server(home, name).protocol, _server(home, name).core),
      ],
      [
        (ShikooProtocol.vless, ShikooCore.xray),
        (ShikooProtocol.vless, ShikooCore.mihomo),
        (ShikooProtocol.wireguard, ShikooCore.mihomo),
      ],
      reason: 'B: Go left it to mihomo, so it kept its own type',
    );
    final rows = home.container.read(shikooStateProvider).cores;
    expect(rows.map((row) => (row.protocol, row.chosen)), [
      (ShikooProtocol.vless, ShikooCore.xray),
      (ShikooProtocol.wireguard, ShikooCore.mihomo),
    ]);
    expect(rows.last.options, [
      (core: ShikooCore.mihomo, ready: true),
      (core: ShikooCore.xray, ready: true),
      (core: ShikooCore.singBox, ready: false),
      (core: ShikooCore.wireguard, ready: false),
    ]);
  });

  test('Windows in Proxy mode keeps an owner pick in its row, while its '
      'servers go through mihomo', () async {
    final home = await _home(
      ready: {ShikooCore.wireguard},
      choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
      proxy: true,
    );

    final state = home.container.read(shikooStateProvider);
    expect(state.cores.last.protocol, ShikooProtocol.wireguard);
    expect(state.cores.last.chosen, ShikooCore.wireguard);
    expect(_server(home, 'W').core, ShikooCore.mihomo);
  });

  test('a pick this build lacks shows as not ready and every server stays on '
      'mihomo', () async {
    final home = await _home(choices: {ShikooProtocol.vless: ShikooCore.xray});

    final state = home.container.read(shikooStateProvider);
    expect(state.cores.first.chosen, ShikooCore.mihomo);
    expect(
      state.cores.first.options,
      contains((core: ShikooCore.xray, ready: false)),
    );
    expect(state.servers.map((server) => server.core).toSet(), {
      ShikooCore.mihomo,
    });
  });

  test('disconnected, a new pick is stored and the config applied again, with '
      'no notice', () async {
    final home = await _home(ready: {ShikooCore.xray});

    await home.controller.setCore(ShikooProtocol.vless, ShikooCore.xray);

    expect(home.setup.applies, 1);
    expect(home.setup.runs, isEmpty);
    expect(home.container.read(shikooStateProvider).coreSwitch, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shikoo.core.vless'), 'xray');
  });

  test('connected, moving the server in use to a core behind mihomo is told as '
      'a switch, keeps the tunnel, and a failed one stays', () async {
    final home = await _home(ready: {ShikooCore.xray});
    await _connectOn(home, 'A');
    final gate = home.setup.gate = Completer<void>();

    final setting = home.controller.setCore(
      ShikooProtocol.vless,
      ShikooCore.xray,
    );
    await pumpEventQueue();
    expect(
      home.container.read(shikooStateProvider).coreSwitch?.stage,
      ShikooSwitchStage.moving,
    );
    gate.complete();
    await setting;

    expect(home.container.read(shikooStateProvider).coreSwitch, (
      protocol: ShikooProtocol.vless,
      to: ShikooCore.xray,
      stage: ShikooSwitchStage.done,
    ));
    expect(home.setup.runs, isNot(contains(false)));

    await home.controller.setCore(ShikooProtocol.vless, ShikooCore.mihomo);
    when(() => home.core.asyncTestDelay(any(), any())).thenAnswer(
      (call) async => Delay(
        name: call.positionalArguments[1] as String,
        url: '',
        value: -1,
      ),
    );
    home.setup.traffic = false;
    await home.controller.setCore(ShikooProtocol.vless, ShikooCore.xray);

    expect(
      home.container.read(shikooStateProvider).coreSwitch?.stage,
      ShikooSwitchStage.failed,
    );
    expect(
      home.container.read(shikooCoresProvider)[ShikooProtocol.vless],
      ShikooCore.xray,
      reason: 'no way back to the old core on its own (Sam, 2026-10-22)',
    );
    await Future<void>.delayed(switchedFor);
    expect(home.container.read(shikooStateProvider).coreSwitch, isNull);
  });

  test(
    'a pick for another protocol re-applies the config but tells nothing',
    () async {
      final home = await _home(ready: {ShikooCore.xray});
      await _connectOn(home, 'A');

      await home.controller.setCore(ShikooProtocol.wireguard, ShikooCore.xray);

      expect(home.setup.applies, 1);
      expect(home.container.read(shikooStateProvider).coreSwitch, isNull);
    },
  );

  test('connected, a switch to or from an owner core reconnects instead of '
      'switching inside mihomo', () async {
    final home = await _home(
      ready: {ShikooCore.wireguard},
      choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
    );
    await _connectOn(home, 'A');
    home.setup.runs.clear();

    await home.controller.selectServer('B');
    expect(home.setup.runs, isEmpty, reason: 'both on mihomo');
    expect(
      home.container.read(shikooStateProvider).switching?.stage,
      ShikooSwitchStage.done,
    );

    await home.controller.selectServer('W');
    expect(home.proxies.picked.last, 'W');
    expect(home.setup.runs, [false, true]);
    expect(home.container.read(shikooStateProvider).selected, 'W');
  });

  test(
    'connected, picking an owner core for the server in use reconnects',
    () async {
      final home = await _home(ready: {ShikooCore.wireguard});
      await _connectOn(home, 'W');
      home.setup.runs.clear();

      await home.controller.setCore(
        ShikooProtocol.wireguard,
        ShikooCore.wireguard,
      );

      expect(home.setup.runs, [false, true]);
      expect(
        home.container.read(shikooStateProvider).coreSwitch?.stage,
        ShikooSwitchStage.done,
      );
    },
  );

  test('WireGuard handed to a core behind mihomo keeps its ping exception: '
      'the core shows it as Socks5, the profile as WireGuard', () async {
    final home = await _home(
      ready: {ShikooCore.xray},
      choices: {ShikooProtocol.wireguard: ShikooCore.xray},
      running: {'A': 'Vless', 'B': 'Vless', 'W': 'Socks5'},
    );
    when(() => home.core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: name == 'A' ? 50 : -1);
    });
    await _connectOn(home, 'A');

    await home.controller.selectServer('W');
    expect(
      home.container.read(shikooStateProvider).switching?.stage,
      ShikooSwitchStage.done,
      reason: 'real traffic passes, so a failed ping does not decide',
    );

    await home.controller.selectServer('A');
    await home.controller.selectServer('B');
    expect(
      home.container.read(shikooStateProvider).switching?.stage,
      ShikooSwitchStage.failed,
      reason: 'a VLESS server with no answer is not tried on traffic',
    );
  });
}
