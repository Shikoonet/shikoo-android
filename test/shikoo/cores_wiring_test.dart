import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
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
import 'package:fl_clash/shikoo/engine/owner.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

class _Core extends Mock implements CoreHandlerInterface {}

/// The proxy of each connection the app opens, null for direct; every one is refused.
class _Legs extends HttpOverrides {
  final proxies = <String?>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (_, host, port) {
          proxies.add(host == null ? null : '$host:$port');
          return Future.error(const SocketException('refused'));
        };
}

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

  /// What the core runs after an apply, as FlClash's updateGroups would then read it.
  void Function()? onApply;

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
    onApply?.call();
    return true;
  }
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
      ready: core == ShikooCore.mihomo || cores.contains(core),
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
  ShikooCarrying? Function()? carrying,
  bool desktop = false,
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
      shikooDesktopProvider.overrideWithValue(desktop),
      if (carrying != null)
        ownerCarryingProvider.overrideWithValue(() async => carrying()),
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
  _run(container, running);
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

/// The servers' types as the core runs them: Go swaps a server it hands to a core for a `Socks5`.
void _run(ProviderContainer container, Map<String, String> running) =>
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

const _onMihomo = {'A': 'Vless', 'B': 'Vless', 'W': 'WireGuard'};
const _vlessHandedOver = {'A': 'Socks5', 'B': 'Socks5', 'W': 'WireGuard'};

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
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: '0.8.98',
      buildNumber: '1',
    );
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
    home.setup.onApply = () => _run(home.container, _vlessHandedOver);

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

    home.setup.onApply = () => _run(home.container, _onMihomo);
    await home.controller.setCore(ShikooProtocol.vless, ShikooCore.mihomo);
    home.setup.onApply = () => _run(home.container, _vlessHandedOver);
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

  test('connected, a pick whose engine never starts is told failed even though '
      'the server answers through mihomo, which keeps carrying it with the pick '
      'kept', () async {
    final home = await _home(ready: {ShikooCore.xray});
    await _connectOn(home, 'A');
    home.setup.onApply = () => _run(home.container, _onMihomo);

    await home.controller.setCore(ShikooProtocol.vless, ShikooCore.xray);

    final state = home.container.read(shikooStateProvider);
    expect(state.coreSwitch?.stage, ShikooSwitchStage.failed);
    expect(state.connection, ShikooConnection.on);
    expect(state.selectedServer?.core, ShikooCore.mihomo);
    expect(state.cores.first.chosen, ShikooCore.xray);
    expect(home.setup.runs, isNot(contains(false)));
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
      final home = await _home(
        ready: {ShikooCore.wireguard},
        carrying: () => (core: 'wireguard', server: 'W'),
      );
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

  test('connected, the Iranian-sites switch reconnects an owner core, whose '
      'routes are set as it builds the VPN, and leaves mihomo up', () async {
    final before = database;
    database = Database(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      database = before;
    });
    final home = await _home(
      ready: {ShikooCore.wireguard},
      choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
    );
    await _connectOn(home, 'W');
    home.setup.runs.clear();

    await home.controller.setIranDirect(false);
    expect(home.setup.runs, [false, true]);
    expect(home.container.read(shikooStateProvider).iranDirect, isFalse);

    await _connectOn(home, 'A');
    home.setup.runs.clear();
    await home.controller.setIranDirect(true);
    expect(home.setup.runs, isEmpty);
  });

  test('an official engine that does not start leaves the server on mihomo: '
      'the switch fails, the server shows mihomo, and VpnOptions keep asking '
      'for the engine, which the next connect gets', () async {
    ShikooCarrying report = (core: '', server: '');
    final home = await _home(
      ready: {ShikooCore.wireguard},
      carrying: () => report,
    );
    await _connectOn(home, 'W');
    home.setup.runs.clear();

    await home.controller.setCore(
      ShikooProtocol.wireguard,
      ShikooCore.wireguard,
    );
    expect(home.setup.runs, [false, true]);
    expect(
      home.container.read(shikooStateProvider).coreSwitch?.stage,
      ShikooSwitchStage.failed,
    );
    expect(_server(home, 'W').core, ShikooCore.mihomo);
    expect(
      home.container.read(shikooCoresProvider)[ShikooProtocol.wireguard],
      ShikooCore.wireguard,
    );
    expect(home.container.read(shikooOwnerProvider)?.core, 'wireguard');

    report = (core: 'wireguard', server: 'W');
    await home.controller.disconnect();
    await home.controller.connect();
    await pumpEventQueue();
    expect(_server(home, 'W').core, ShikooCore.wireguard);
  });

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

  for (final (label, report, core, stage)
      in <(String, ShikooCarrying?, ShikooCore, ShikooSwitchStage)>[
        (
          'never started: mihomo carries it, and the switch fails',
          (core: '', server: ''),
          ShikooCore.mihomo,
          ShikooSwitchStage.failed,
        ),
        (
          'silent: read as never started',
          null,
          ShikooCore.mihomo,
          ShikooSwitchStage.failed,
        ),
        (
          'carrying another server: not this one',
          (core: 'wireguard', server: 'another'),
          ShikooCore.mihomo,
          ShikooSwitchStage.failed,
        ),
        (
          'carries it: the switch lands',
          (core: 'wireguard', server: 'W'),
          ShikooCore.wireguard,
          ShikooSwitchStage.done,
        ),
      ]) {
    test('connected, an owner core the Go core reports as $label', () async {
      final home = await _home(
        ready: {ShikooCore.wireguard},
        carrying: () => report,
      );
      await _connectOn(home, 'W');
      home.setup.runs.clear();

      await home.controller.setCore(
        ShikooProtocol.wireguard,
        ShikooCore.wireguard,
      );

      final state = home.container.read(shikooStateProvider);
      expect(home.setup.runs, [false, true]);
      expect(state.selectedServer?.core, core);
      expect(state.coreSwitch?.stage, stage);
      expect(
        home.container.read(shikooCoresProvider)[ShikooProtocol.wireguard],
        ShikooCore.wireguard,
      );
    });
  }

  for (final (label, desktop, report, aside)
      in <(String, bool, ShikooCarrying?, bool)>[
        (
          'on Windows, an owner engine that gives no answer counts as not '
              'carrying: direct',
          true,
          null,
          false,
        ),
        (
          'on Windows, an owner core carrying the server in use: direct by '
              "mihomo's port, the server by a plain request",
          true,
          (core: 'wireguard', server: 'W'),
          true,
        ),
        (
          'on Android the app is out of the VPN: direct',
          false,
          (core: 'wireguard', server: 'W'),
          false,
        ),
        (
          'on Windows, an owner engine that never started leaves mihomo the tunnel: '
              'direct',
          true,
          (core: '', server: ''),
          false,
        ),
      ]) {
    for (final via in [null, ShikooRoute.server]) {
      final route = via == null
          ? 'direct, then by the server'
          : 'by the server';
      test("connected, the app's own requests $route: $label", () async {
        final home = await _home(
          ready: {ShikooCore.wireguard},
          choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
          carrying: () => report,
          desktop: desktop,
        );
        await _connectOn(home, 'W');
        final mihomo =
            'localhost:${home.container.read(patchClashConfigProvider).mixedPort}';
        globalState.container = home.container;
        final legs = _Legs();

        await HttpOverrides.runWithHttpOverrides(() async {
          try {
            await home.controller.refreshService(via: via);
          } catch (_) {}
        }, legs);

        // Aside, a plain request rides the owner's tunnel, so it is the server leg: mihomo's client of W stays shut.
        expect(legs.proxies, switch ((via, aside)) {
          (null, true) => [mihomo, null],
          (null, false) => [null, mihomo],
          (_, true) => [null],
          (_, false) => [mihomo],
        });
      });
    }
  }

  for (final (label, desktop, aside) in [
    ("on Windows, through mihomo's port", true, true),
    ('on Android, direct', false, false),
  ]) {
    test('connected on an owner core, the internet check of the card and of '
        'settings: $label', () async {
      final home = await _home(
        ready: {ShikooCore.wireguard},
        choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
        carrying: () => (core: 'wireguard', server: 'W'),
        desktop: desktop,
      );
      await _connectOn(home, 'W');
      final mihomo =
          'localhost:${home.container.read(patchClashConfigProvider).mixedPort}';
      final legs = _Legs();

      await HttpOverrides.runWithHttpOverrides(
        () => home.container.read(shikooProbeProvider.notifier).probe(),
        legs,
      );

      expect(legs.proxies, isNotEmpty);
      expect(legs.proxies.toSet(), {aside ? mihomo : null});
    });
  }

  test('a server not in use shows its pick, whatever Go says of the one in '
      'use', () async {
    final home = await _home(
      ready: {ShikooCore.wireguard},
      choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
      carrying: () => (core: '', server: ''),
    );

    await _connectOn(home, 'A');

    expect(_server(home, 'W').core, ShikooCore.wireguard);
  });

  test("disconnecting forgets Go's answer, so the pick shows again", () async {
    final home = await _home(
      ready: {ShikooCore.wireguard},
      choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
      carrying: () => (core: '', server: ''),
    );
    await _connectOn(home, 'W');
    expect(_server(home, 'W').core, ShikooCore.mihomo);

    await home.controller.disconnect();
    await pumpEventQueue();

    expect(_server(home, 'W').core, ShikooCore.wireguard);
  });

  test("in Windows' proxy mode the cores row keeps the owner pick and names "
      'mihomo as its carrier', () async {
    final home = await _home(
      ready: {ShikooCore.wireguard},
      choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
      desktop: true,
    );
    (ShikooCore, ShikooCore) row() {
      final row = home.container
          .read(shikooStateProvider)
          .cores
          .firstWhere((row) => row.protocol == ShikooProtocol.wireguard);
      return (row.chosen, row.carrier);
    }

    expect(row(), (ShikooCore.wireguard, ShikooCore.wireguard));

    await home.container
        .read(shikooModeProvider.notifier)
        .save(ShikooMode.proxy);
    await pumpEventQueue();

    expect(row(), (ShikooCore.wireguard, ShikooCore.mihomo));
  });

  test('on Windows the app asks Go again before its own requests: an engine '
      'that stopped since connect leaves them to mihomo', () async {
    ShikooCarrying report = (core: 'wireguard', server: 'W');
    final home = await _home(
      ready: {ShikooCore.wireguard},
      choices: {ShikooProtocol.wireguard: ShikooCore.wireguard},
      carrying: () => report,
      desktop: true,
    );
    await _connectOn(home, 'W');
    expect(_server(home, 'W').core, ShikooCore.wireguard);
    report = (core: '', server: '');
    final mihomo =
        'localhost:${home.container.read(patchClashConfigProvider).mixedPort}';
    globalState.container = home.container;
    final legs = _Legs();

    await HttpOverrides.runWithHttpOverrides(() async {
      try {
        await home.controller.refreshService(via: ShikooRoute.server);
      } catch (_) {}
    }, legs);

    expect(legs.proxies, [mihomo]);
    expect(_server(home, 'W').core, ShikooCore.mihomo);
  });
}
