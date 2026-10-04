import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/path.dart';
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
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/misc.dart' show Override;
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

  /// Holds the traffic check open until completed.
  Completer<void>? trafficGate;

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
  }) async => true;
}

/// The panel answers at once: a paste goes through without a network.
class _Panel extends ShikooController {
  _Panel(this.ref) : super(ref);

  final Ref ref;

  @override
  Future<ShikooPasteError?> addService(
    String url, [
    String? label,
    bool select = true,
  ]) async {
    ref.read(profilesProvider.notifier).put(Profile.normal(url: url));
    return null;
  }
}

const _version = 'V3.7.9 🆔 : (user123) 📊 (67 GB) ⏰ (23)';

({ProviderContainer container, _Core core, _Proxies proxies, _Setup setup})
_home([List<Override> more = const []]) {
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
      trafficPassesProvider.overrideWithValue(() async {
        await setup.trafficGate?.future;
        return setup.traffic;
      }),
      ...more,
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

/// The live panel's shape: every account titled "Shi" (`U2hp`), the account in the file name
/// (`/file/<user>/…`), in the first row only (`/row/<user>/…`), or nowhere (`/none/…`).
Future<String> _panel(ProviderContainer container, _Core core) async {
  globalState.container = container;
  when(() => core.validateConfig(any())).thenAnswer((_) async => '');
  when(() => core.getConfig(any())).thenAnswer(
    (_) async => {
      'proxies': [
        {'name': 'هلند ۱', 'type': 'Http'},
      ],
    },
  );
  when(() => core.asyncTestDelay(any(), any())).thenAnswer(
    (call) async =>
        Delay(name: call.positionalArguments[1] as String, url: '', value: 50),
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((call) {
    final [kind, ...rest] = call.uri.pathSegments;
    final user = kind == 'none' ? null : rest.first;
    call.response.headers
      ..contentType = ContentType('text', 'yaml', charset: 'utf-8')
      ..set('profile-title', 'base64:U2hp')
      ..set('subscription-userinfo', 'upload=0; download=0; total=1073741824');
    if (kind == 'file') {
      call.response.headers.set(
        'content-disposition',
        'attachment; filename="$user"',
      );
    }
    const at = 'type: http, server: 1.1.1.1, port: 1';
    call.response.write(
      [
        'proxies:',
        if (user != null) '  - {name: "V3.7.9 🆔 : ($user) 📊 (1 GB)", $at}',
        '  - {name: "هلند ۱", $at}',
      ].join('\n'),
    );
    unawaited(call.response.close());
  });
  return 'http://127.0.0.1:${server.port}';
}

/// The emulator's name for the computer, 10.0.2.2, reaches the test's panel. Set before any
/// request: FlClash's client is made once and kept.
class _EmulatorHost extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (uri, _, _) => Socket.startConnect(
          uri.host == '10.0.2.2' ? InternetAddress.loopbackIPv4 : uri.host,
          uri.port,
        );
}

List<Profile> _pasted(ProviderContainer container) => [
  for (final profile in container.read(profilesProvider))
    if (profile.url.startsWith('http://127.0.0.1')) profile,
];

void main() {
  setUpAll(() {
    HttpOverrides.global = _EmulatorHost();
    final files = Directory.systemTemp.createTempSync('shikoo-wiring-');
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
    await pumpEventQueue();
    await controller.selectServer('آلمان ۱');

    pings['آلمان ۱'] = -1;
    container.read(currentProfileIdProvider.notifier).value = first;
    await pumpEventQueue();
    expect(
      proxies.picked.last,
      'هلند ۱',
      reason: "the user's pick in the second left the first one the app's",
    );

    final picks = proxies.picked.length;
    container.read(currentProfileIdProvider.notifier).value = second.id;
    await pumpEventQueue();
    expect(container.read(shikooStateProvider).selected, 'آلمان ۱');
    expect(proxies.picked, hasLength(picks), reason: "the user's own stays");
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

  test(
    'a paste marks its profile pasted; one the account adds is not',
    () async {
      final container = _home([
        shikooControllerProvider.overrideWith(_Panel.new),
      ]).container;
      final controller = container.read(shikooControllerProvider);
      expect(
        await controller.pasteService('سرویسم: https://4g3.uk/sub/mine.'),
        isNull,
      );
      await controller.addService('https://4g3.uk/sub/account');
      final ids = {
        for (final profile in container.read(profilesProvider))
          profile.url: profile.id,
      };
      expect(await pastedProfiles(), {ids['https://4g3.uk/sub/mine']});
    },
  );

  test('a traffic check that ends after a switch or a disconnect proves '
      'nothing for the server it began on', () async {
    for (final interrupt in ['switch', 'disconnect']) {
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
      await controller.selectServer('آلمان ۱');

      pings['آلمان ۱'] = -1;
      setup
        ..traffic = true
        ..trafficGate = Completer<void>();
      final round = controller.pingAll();
      await pumpEventQueue();
      if (interrupt == 'switch') {
        await controller.selectServer('هلند ۱');
      } else {
        await controller.disconnect();
        container.read(runTimeProvider.notifier).value = null;
      }
      setup.trafficGate!.complete();
      await round;
      await pumpEventQueue();
      final germany = container
          .read(shikooStateProvider)
          .servers
          .firstWhere((server) => server.name == 'آلمان ۱');
      expect(germany.ping, -1, reason: interrupt);
    }
  });

  test('a second service with the same server names is measured and gets '
      'a server of its own', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    container.read(shikooControllerProvider);
    await pumpEventQueue();
    expect(proxies.picked, ['آلمان ۱']);

    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    container.read(currentProfileIdProvider.notifier).value = second.id;
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.pick, ShikooPick.server, reason: 'not finding forever');
    expect(state.selected, 'آلمان ۱');
    expect(proxies.picked, ['آلمان ۱', 'آلمان ۱']);
  });

  test('a service the panel sent no usage header for shows no usage', () {
    final (:container, :core, :proxies, :setup) = _home();
    expect(container.read(shikooStateProvider).service!.usageKnown, isFalse);

    final measured = Profile.normal(
      url: 'https://panel.invalid/measured',
    ).copyWith(subscriptionInfo: const SubscriptionInfo(total: 1 << 30));
    container.read(profilesProvider.notifier).put(measured);
    container.read(currentProfileIdProvider.notifier).value = measured.id;
    expect(container.read(shikooStateProvider).service!.usageKnown, isTrue);
  });

  test(
    'every service is listed, and choosing another one puts it in use',
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
      await pumpEventQueue();
      final first = container.read(currentProfileIdProvider)!;
      final second = Profile.normal(
        url: 'https://panel.invalid/second',
      ).copyWith(label: 'user456 · طلایی');
      container.read(profilesProvider.notifier).put(second);
      var state = container.read(shikooStateProvider);
      expect(state.service!.id, first);
      expect(state.others.map((s) => s.name), ['user456 · طلایی']);

      controller.selectService(second.id);
      await pumpEventQueue();
      state = container.read(shikooStateProvider);
      expect(state.service!.id, second.id);
      expect(state.others.map((s) => s.id), [first]);
      expect(state.selected, isNotNull, reason: 'measured and picked');
    },
  );

  test(
    'a server measured on its own takes its place in the order at once',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        return Delay(name: name, url: '', value: pings[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      List<String> order() => [
        for (final server in container.read(shikooStateProvider).servers)
          server.name,
      ];
      expect(order().take(2), ['آلمان ۱', 'هلند ۱']);

      pings['هلند ۱'] = 10;
      await controller.selectServer('هلند ۱');
      expect(order().take(2), ['هلند ۱', 'آلمان ۱']);
    },
  );

  test(
    'after a switch with the tunnel up, a service with no server of its own '
    'takes the best known one at once, then the fastest when the round ends',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final germany = Completer<void>();
      var switched = false;
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        final netherlands = name == 'هلند ۱';
        if (!switched) {
          return Delay(name: name, url: '', value: netherlands ? 40 : 50);
        }
        if (!netherlands) await germany.future;
        return Delay(name: name, url: '', value: netherlands ? 3466 : 120);
      });
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      container.read(runTimeProvider.notifier).value = 1;
      setup.tunnel = DateTime(2026);
      await pumpEventQueue();
      final second = Profile.normal(url: 'https://panel.invalid/second');
      container.read(profilesProvider.notifier).put(second);
      switched = true;
      controller.selectService(second.id);
      await pumpEventQueue();
      expect(proxies.picked, [
        'هلند ۱',
        'هلند ۱',
      ], reason: 'at once, so traffic never sits on row 1');

      germany.complete();
      await pumpEventQueue();
      final state = container.read(shikooStateProvider);
      expect(proxies.picked, ['هلند ۱', 'هلند ۱', 'آلمان ۱']);
      expect(state.selected, 'آلمان ۱');
      expect(state.notice, isNull);
    },
  );

  test(
    'back on a service, its server stays if it answers; a silent one that '
    'does not gives way to the fastest at round end, with no notice',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      container.read(groupsProvider.notifier).value = [
        const Group(
          type: GroupType.Selector,
          name: 'PROXY',
          hidden: false,
          all: [
            Proxy(name: 'آلمان ۱', type: 'Vless'),
            Proxy(name: 'هلند ۱', type: 'Vless'),
            Proxy(name: 'ترکیه ۱', type: 'Vless'),
          ],
        ),
      ];
      final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
      Completer<void>? turkey;
      var turkeyCalls = 0;
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        if (name == 'ترکیه ۱' && turkey != null && ++turkeyCalls == 2) {
          await turkey.future;
        }
        return Delay(name: name, url: '', value: pings[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      final first = container.read(currentProfileIdProvider)!;
      final second = Profile.normal(url: 'https://panel.invalid/second');
      container.read(profilesProvider.notifier).put(second);
      controller.selectService(second.id);
      await pumpEventQueue();
      controller.selectService(first);
      await pumpEventQueue();
      expect(proxies.picked, [
        'آلمان ۱',
        'آلمان ۱',
      ], reason: 'it still answered');

      pings['آلمان ۱'] = -1;
      turkey = Completer<void>();
      controller.selectService(second.id);
      await pumpEventQueue();
      var state = container.read(shikooStateProvider);
      expect(state.pick, ShikooPick.finding, reason: 'آلمان ۱ did not answer');
      expect(state.selected, isNull);

      turkey.complete();
      await pumpEventQueue();
      state = container.read(shikooStateProvider);
      expect(state.selected, 'هلند ۱');
      expect(state.pick, ShikooPick.server);
      expect(state.notice, isNull);
    },
  );

  test('a round that ends after a switch says nothing about the new '
      "service's server", () async {
    final (:container, :core, :proxies, :setup) = _home();
    var germanyDown = 0;
    Completer<void>? netherlands;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name == 'هلند ۱') await netherlands?.future;
      final down = name == 'آلمان ۱' && germanyDown > 0;
      if (down) germanyDown--;
      return Delay(name: name, url: '', value: down ? -1 : 50);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    final first = container.read(currentProfileIdProvider)!;
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    controller.selectService(second.id);
    await pumpEventQueue();
    expect(proxies.picked, ['آلمان ۱', 'آلمان ۱']);

    germanyDown = 2;
    netherlands = Completer<void>();
    controller.selectService(first);
    await pumpEventQueue();
    controller.selectService(second.id);
    await pumpEventQueue();
    netherlands.complete();
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.notice, isNull);
    expect(state.selected, 'آلمان ۱');
    expect(proxies.picked, hasLength(2));
  });

  test('two accounts the panel titles alike are two cards, each named by its '
      'username', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    expect(await controller.addService('$panel/file/user111/a'), isNull);
    expect(await controller.addService('$panel/row/user222/a'), isNull);
    expect(_pasted(container).map((p) => p.label), ['user111', 'user222']);
  });

  test('an account pasted again from a new link is the same card, with the '
      'new link', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    await controller.addService('$panel/file/user111/a');
    await controller.addService('$panel/file/user111/b');
    expect(_pasted(container).map((p) => (p.label, p.url)), [
      ('user111', '$panel/file/user111/b'),
    ]);
  });

  test('with no username, only the same link is the same card', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    await controller.addService('$panel/none/a');
    await controller.addService('$panel/none/b');
    await controller.addService('$panel/none/a');
    expect(_pasted(container).map((p) => p.url), [
      '$panel/none/a',
      '$panel/none/b',
    ]);
  });

  test('a paste counts as pasted, also when it gives a known account its new '
      'link', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final port = Uri.parse(await _panel(container, core)).port;
    final controller = container.read(shikooControllerProvider);
    final emulator = 'http://10.0.2.2:$port';
    for (final link in ['file/user111/a', 'file/user111/b']) {
      expect(
        await controller.pasteService('$emulator/$link', debug: true),
        isNull,
      );
    }
    final pasted = [
      for (final profile in container.read(profilesProvider))
        if (profile.url.startsWith(emulator)) profile,
    ];
    expect(pasted.map((p) => p.url), ['$emulator/file/user111/b']);
    expect(await pastedProfiles(), {pasted.single.id});
  });
}
