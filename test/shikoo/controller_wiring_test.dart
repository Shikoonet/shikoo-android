import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:fl_clash/shikoo/engine/clock.dart';
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
    if (ref.read(currentProfileIdProvider) == id) {
      ref.read(currentProfileIdProvider.notifier).value = null;
    }
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
var _inFlight = 0;
var _mostInFlight = 0;

/// Paths the panel answers 404 for, as for a link it no longer knows.
final _gone = <String>{};

DateTime? _panelClock;

Future<String> _panel(ProviderContainer container, _Core core) async {
  globalState.container = container;
  _mostInFlight = 0;
  _gone.clear();
  _panelClock = null;
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
  server.listen((call) async {
    _mostInFlight = math.max(_mostInFlight, ++_inFlight);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (_gone.contains(call.uri.path)) {
      call.response.statusCode = 404;
      await call.response.close();
      _inFlight--;
      return;
    }
    final [kind, ...rest] = call.uri.pathSegments;
    final user = kind == 'none' ? null : rest.first;
    if (_panelClock case final at?) call.response.headers.date = at;
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
    if (kind == 'bad') {
      call.response.headers.set(
        'content-disposition',
        "attachment; filename*=UTF-8''%ZZ",
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
    await call.response.close();
    _inFlight--;
  });
  return 'http://127.0.0.1:${server.port}';
}

/// The emulator's name for the computer, 10.0.2.2, reaches the test's panel. Set before any
/// request: FlClash's client is made once and kept.
class _EmulatorHost extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (uri, _, _) => switch (uri) {
          Uri(host: 'clock.test', scheme: 'https') =>
            Future<ConnectionTask<Socket>>.error(
              HandshakeException(
                'Handshake error in client',
                OSError('CERTIFICATE_VERIFY_FAILED: $_certificate'),
              ),
            ),
          Uri(host: 'clock.test') => Socket.startConnect(
            InternetAddress.loopbackIPv4,
            _clockPort!,
          ),
          _ => Socket.startConnect(
            uri.host == '10.0.2.2' ? InternetAddress.loopbackIPv4 : uri.host,
            uri.port,
          ),
        };
}

/// `clock.test`: https fails on the certificate's dates, plain http answers with the server's [at].
String? _certificate;
int? _clockPort;

Future<void> _clockTest(String certificate, DateTime at) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((call) {
    call.response.headers.date = at;
    unawaited(call.response.close());
  });
  _certificate = certificate;
  _clockPort = server.port;
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
    'connected, a tapped server that does not answer is measured and never '
    'gets the traffic; the next tap or leaving the app clears the news',
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
      var state = container.read(shikooStateProvider);
      expect(state.selected, 'آلمان ۱');
      expect(proxies.picked, ['آلمان ۱'], reason: 'never moved to a dead one');
      expect(setup.runs, isEmpty, reason: 'the tunnel was never touched');
      expect(state.switching, (
        to: 'هلند ۱',
        from: 'آلمان ۱',
        stage: ShikooSwitchStage.failed,
      ));
      expect(
        state.servers.firstWhere((server) => server.name == 'هلند ۱').ping,
        -1,
        reason: 'measured, not the old 90',
      );
      expect(state.notice, isNull);

      await controller.selectServer('آلمان ۱');
      expect(container.read(shikooStateProvider).switching, isNull);
      await controller.selectServer('هلند ۱');
      controller.clearNews();
      state = container.read(shikooStateProvider);
      expect(state.switching, isNull, reason: 'the app went to the background');
      expect(proxies.picked, ['آلمان ۱', 'آلمان ۱']);
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

  test('a pick whose pings fail but whose traffic flows stays, with no warning '
      'and its last real ping; when traffic fails too, it moves', () async {
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
      50,
      reason: 'the ping measured before, not the IP lookup\'s time',
    );

    setup.traffic = false;
    await controller.pingAll();
    await pumpEventQueue();
    state = container.read(shikooStateProvider);
    expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
    expect(state.notice, isA<SilentReplaced>());
  });

  test('a server the user picked that carries traffic gets no warning, and no '
      'number until a ping answers', () async {
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
    await controller.selectServer('هلند ۱');
    container.read(runTimeProvider.notifier).value = 1;
    setup
      ..tunnel = DateTime(2026)
      ..traffic = true;
    await controller.selectServer('هلند ۱');
    final state = container.read(shikooStateProvider);
    expect(state.selectedServer?.ping, isNull);
    expect(state.notice, isNull);

    setup.traffic = false;
    await controller.selectServer('هلند ۱');
    expect(container.read(shikooStateProvider).selectedServer?.ping, -1);
  });

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

  test('a tapped server keeps its row after its own measure, off or on; the '
      'next round puts it in order', () async {
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
    expect(container.read(shikooStateProvider).selectedServer?.ping, 10);
    expect(order().take(2), ['آلمان ۱', 'هلند ۱'], reason: 'off');
    await controller.pingAll();
    expect(order().take(2), ['هلند ۱', 'آلمان ۱']);

    container.read(runTimeProvider.notifier).value = 1;
    pings['آلمان ۱'] = 5;
    await controller.selectServer('آلمان ۱');
    expect(container.read(shikooStateProvider).selected, 'آلمان ۱');
    expect(order().take(2), ['هلند ۱', 'آلمان ۱'], reason: 'on');
    await controller.pingAll();
    expect(order().take(2), ['آلمان ۱', 'هلند ۱']);
  });

  test('connected, a tapped server is measured first and takes the traffic '
      'only once it answers; the news goes after a few seconds', () async {
    final (:container, :core, :proxies, :setup) = _home();
    Completer<void>? netherlands;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name == 'هلند ۱') await netherlands?.future;
      return Delay(name: name, url: '', value: name == 'هلند ۱' ? 90 : 50);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();

    netherlands = Completer<void>();
    final tap = controller.selectServer('هلند ۱');
    await pumpEventQueue();
    var state = container.read(shikooStateProvider);
    ShikooServer row(String name) =>
        state.servers.firstWhere((server) => server.name == name);
    expect(state.switching, (
      to: 'هلند ۱',
      from: 'آلمان ۱',
      stage: ShikooSwitchStage.moving,
    ));
    expect(proxies.picked, ['آلمان ۱'], reason: 'nothing moves before it');
    expect(state.selected, 'آلمان ۱', reason: 'the tick stays until then');
    expect(row('هلند ۱').testing, isTrue);

    netherlands.complete();
    await tap;
    state = container.read(shikooStateProvider);
    expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
    expect(state.selected, 'هلند ۱');
    expect(state.switching?.stage, ShikooSwitchStage.done);
    expect((row('هلند ۱').testing, row('هلند ۱').ping), (false, 90));
    expect(setup.runs, isEmpty, reason: 'the tunnel stays up throughout');

    await Future<void>.delayed(switchedFor);
    expect(container.read(shikooStateProvider).switching, isNull);
  });

  test('a WireGuard server whose ping fails is tried on real traffic: it stays '
      'if traffic passes, else the old one comes back; known by its type, not '
      'its name', () async {
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: 'آلمان ۱', type: 'Vless'),
          Proxy(name: 'آلمان ۳', type: 'WireGuard'),
          Proxy(name: 'WG ۲', type: 'Vless'),
        ],
      ),
    ];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: name == 'آلمان ۱' ? 50 : -1);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    container.read(runTimeProvider.notifier).value = 1;
    setup
      ..tunnel = DateTime(2026)
      ..traffic = true;
    await pumpEventQueue();

    await controller.selectServer('آلمان ۳');
    var state = container.read(shikooStateProvider);
    expect(proxies.picked, ['آلمان ۱', 'آلمان ۳']);
    expect(state.switching?.stage, ShikooSwitchStage.done);
    expect(state.selectedServer?.ping, isNull, reason: 'not "no answer"');

    await controller.selectServer('آلمان ۱');
    setup.traffic = false;
    await controller.selectServer('آلمان ۳');
    state = container.read(shikooStateProvider);
    expect(proxies.picked, [
      'آلمان ۱',
      'آلمان ۳',
      'آلمان ۱',
      'آلمان ۳',
      'آلمان ۱',
    ]);
    expect(state.selected, 'آلمان ۱');
    expect(state.switching, (
      to: 'آلمان ۳',
      from: 'آلمان ۱',
      stage: ShikooSwitchStage.failed,
    ));

    setup.traffic = true;
    await controller.selectServer('WG ۲');
    expect(
      proxies.picked,
      hasLength(5),
      reason: 'a Vless named like WireGuard',
    );
    expect(
      container.read(shikooStateProvider).switching?.stage,
      ShikooSwitchStage.failed,
    );
  });

  test('the last tap wins: an earlier one that answers later moves nothing, '
      'and its row gets its number back', () async {
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
    final pings = {'آلمان ۱': 50, 'هلند ۱': 90, 'ترکیه ۱': 70};
    Completer<void>? netherlands;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name == 'هلند ۱') await netherlands?.future;
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    container.read(runTimeProvider.notifier).value = 1;
    await pumpEventQueue();

    netherlands = Completer<void>();
    final first = controller.selectServer('هلند ۱');
    await pumpEventQueue();
    final second = controller.selectServer('ترکیه ۱');
    final netherlandsRow = container
        .read(shikooStateProvider)
        .servers
        .firstWhere((server) => server.name == 'هلند ۱');
    expect((netherlandsRow.testing, netherlandsRow.ping), (false, 90));
    await second;
    netherlands.complete();
    await first;
    final state = container.read(shikooStateProvider);
    expect(proxies.picked, ['آلمان ۱', 'ترکیه ۱']);
    expect(state.selected, 'ترکیه ۱');
    expect(state.switching?.to, 'ترکیه ۱');
  });

  test('a disconnect during a switch drops it: no move, no news', () async {
    final (:container, :core, :proxies, :setup) = _home();
    Completer<void>? netherlands;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name == 'هلند ۱') await netherlands?.future;
      return Delay(name: name, url: '', value: name == 'هلند ۱' ? 90 : 50);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    container.read(runTimeProvider.notifier).value = 1;
    await pumpEventQueue();

    netherlands = Completer<void>();
    final tap = controller.selectServer('هلند ۱');
    await pumpEventQueue();
    await controller.disconnect();
    expect(container.read(shikooStateProvider).switching, isNull);
    netherlands.complete();
    await tap;
    expect(proxies.picked, ['آلمان ۱']);
    expect(container.read(shikooStateProvider).switching, isNull);
  });

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

  test('one account on two hosts is two cards, both keeping the panel\'s '
      'account name under the label made unique', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final port = Uri.parse(await _panel(container, core)).port;
    final controller = container.read(shikooControllerProvider);
    await controller.addService('http://127.0.0.1:$port/file/user111/a');
    await controller.addService('http://10.0.2.2:$port/file/user111/a');
    final state = container.read(shikooStateProvider);
    expect({
      for (final s in [?state.service, ...state.others]) (s.name, s.account),
    }, containsAll([('user111', 'user111'), ('user111 ۲', 'user111')]));
  });

  test('the account name is stored with the service and read back after a '
      'restart', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final port = Uri.parse(await _panel(container, core)).port;
    final controller = container.read(shikooControllerProvider);
    await controller.addService('http://127.0.0.1:$port/file/user111/a');
    // A second card of the account, whose label is made unique: only storage gives its account.
    await controller.addService('http://10.0.2.2:$port/file/user111/a');
    final stored = (await SharedPreferences.getInstance()).getString(
      'shikoo.serviceExtras',
    );
    final services = [
      for (final p in container.read(profilesProvider))
        if (p.label.startsWith('user111')) p,
    ];

    final again = _home().container;
    services.forEach(again.read(profilesProvider.notifier).put);
    SharedPreferences.setMockInitialValues({'shikoo.serviceExtras': stored!});
    again.read(shikooControllerProvider);
    await pumpEventQueue();

    final state = again.read(shikooStateProvider);
    expect(
      [?state.service, ...state.others].map((s) => (s.name, s.account)),
      containsAll([('user111', 'user111'), ('user111 ۲', 'user111')]),
    );
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
    expect(_pasted(container).map((p) => (p.url, p.label)), [
      ('$panel/none/a', ''),
      ('$panel/none/b', ''),
    ]);
  });

  test('a file name that will not decode is no username, not a failed '
      'paste', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    expect(await controller.addService('$panel/bad/user333/a'), isNull);
    expect(_pasted(container).map((p) => p.label), ['user333']);
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

  test('switching with the tunnel up, a service without a server already holds '
      'one when the core takes it', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final pings = {'آلمان ۱': 50, 'هلند ۱': 40};
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    when(() => core.getConfig(any())).thenAnswer(
      (_) async => {
        'proxies': [
          {'name': _version, 'type': 'vless'},
          {'name': 'آلمان ۱', 'type': 'vless'},
          {'name': 'هلند ۱', 'type': 'vless'},
        ],
        'proxy-groups': [
          {
            'name': 'PROXY',
            'type': 'select',
            'proxies': [_version, 'آلمان ۱', 'هلند ۱'],
          },
        ],
      },
    );
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    Map<String, String>? held;
    container.listen(currentProfileIdProvider, (_, id) {
      held = container.read(profilesProvider).getProfile(id!)?.selectedMap;
    });
    controller.selectService(second.id);
    await pumpEventQueue();
    expect(held, {'PROXY': 'هلند ۱'}, reason: 'the best known, before row 1');
  });

  test('on open every service that is due is updated, one at a time', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    for (final user in ['user111', 'user222', 'user333']) {
      await controller.addService('$panel/file/$user/a');
    }
    final profiles = container.read(profilesProvider.notifier);
    final old = DateTime(2020);
    for (final profile in container.read(profilesProvider)) {
      profiles.put(
        profile.copyWith(
          lastUpdateDate: profile.url.startsWith(panel) ? old : DateTime.now(),
        ),
      );
    }
    _mostInFlight = 0;
    controller.onForeground();
    bool stale() => _pasted(container).any((p) => p.lastUpdateDate == old);
    for (var i = 0; i < 200 && stale(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(stale(), isFalse);
    expect(_mostInFlight, 1);
  });

  test('a pasted link the panel stops knowing is revoked until an update or '
      'a new paste of the account works again', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final port = Uri.parse(await _panel(container, core)).port;
    final controller = container.read(shikooControllerProvider);
    final emulator = 'http://10.0.2.2:$port';
    await controller.pasteService('$emulator/file/user111/a', debug: true);
    await controller.addService('$emulator/file/user222/a');
    ShikooService service(String name) {
      final state = container.read(shikooStateProvider);
      return [
        state.service!,
        ...state.others,
      ].firstWhere((s) => s.name == name);
    }

    final pasted = service('user111');
    _gone.addAll(['/file/user111/a', '/file/user222/a']);
    await controller.refreshOther(pasted.id);
    await controller.refreshService();
    expect(service('user111').ended, ShikooServiceStatus.revoked);
    expect(service('user222').revoked, isFalse, reason: 'not pasted');

    _gone.clear();
    await controller.refreshOther(pasted.id);
    expect(service('user111').revoked, isFalse);

    _gone.add('/file/user111/a');
    await controller.refreshOther(pasted.id);
    expect(service('user111').revoked, isTrue);
    await controller.pasteService('$emulator/file/user111/b', debug: true);
    expect(service('user111').revoked, isFalse, reason: 'its new link');
  });

  test('removing the service in use disconnects, the next card takes its '
      'place, and nothing reconnects', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final port = Uri.parse(await _panel(container, core)).port;
    final controller = container.read(shikooControllerProvider);
    final emulator = 'http://10.0.2.2:$port';
    final profiles = container.read(profilesProvider.notifier);
    await profiles.del(container.read(currentProfileIdProvider)!);
    for (final user in ['user111', 'user222']) {
      await controller.pasteService('$emulator/file/$user/a', debug: true);
    }
    final [first, second] = container.read(profilesProvider);
    expect(container.read(currentProfileIdProvider), second.id);
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();
    setup.runs.clear();

    await controller.removeService(second.id);
    expect(setup.runs, [false]);
    expect(container.read(currentProfileIdProvider), first.id);
    expect(container.read(profilesProvider), [first]);
    expect(await pastedProfiles(), {first.id});
    expect(container.read(shikooStateProvider).service?.pasted, isTrue);
    container.read(runTimeProvider.notifier).value = null;

    await controller.removeService(first.id);
    expect(setup.runs, [false], reason: 'never reconnects');
    expect(container.read(shikooStateProvider).service, isNull);
    expect(await pastedProfiles(), isEmpty);
  });

  test("a failed update stays with its own service's card, not the next one "
      'in use', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    await controller.addService('$panel/file/user111/a');
    await controller.addService('$panel/file/user222/a');
    final [failing, ok] = _pasted(container);
    container.read(currentProfileIdProvider.notifier).value = failing.id;
    await pumpEventQueue();
    _gone.add('/file/user111/a');
    await controller.refreshService();
    var state = container.read(shikooStateProvider);
    expect(state.refresh, ShikooRefresh.failed);
    expect(state.notice, isA<RefreshFailed>());

    controller.selectService(ok.id);
    await pumpEventQueue();
    state = container.read(shikooStateProvider);
    expect(state.refresh, ShikooRefresh.idle);
    expect(state.notice, isNull);
    expect(
      state.others.firstWhere((s) => s.id == failing.id).refresh,
      ShikooRefresh.failed,
    );

    controller.selectService(failing.id);
    await pumpEventQueue();
    expect(container.read(shikooStateProvider).refresh, ShikooRefresh.failed);
  });

  group('a clock years off', () {
    const years14 = Duration(days: 14 * 365);
    tearDown(() => shikooSkew = Duration.zero);

    test('is learned from the server clock a subscription carries', () async {
      final (:container, :core, proxies: _, setup: _) = _home();
      final panel = await _panel(container, core);
      _panelClock = DateTime.now().subtract(years14);
      await container
          .read(shikooControllerProvider)
          .addService('$panel/file/user111/a');
      expect(shikooSkew.inDays, closeTo(-years14.inDays, 1));
    });

    test('is what a paste refused for an expired certificate says', () async {
      final (:container, :core, proxies: _, setup: _) = _home();
      await _panel(container, core);
      await _clockTest(
        'certificate has expired',
        DateTime.now().subtract(years14),
      );
      expect(
        await container
            .read(shikooControllerProvider)
            .addService('https://clock.test/sub/user111'),
        ShikooPasteError.clock,
      );
    });

    test('shows on the card after an automatic update, not only a pressed '
        'one', () async {
      final (:container, :core, proxies: _, setup: _) = _home();
      await _panel(container, core);
      await _clockTest(
        'certificate is not yet valid',
        DateTime.now().add(years14),
      );
      final profile = Profile.normal(url: 'https://clock.test/sub/user111');
      container.read(profilesProvider.notifier).put(profile);
      container.read(currentProfileIdProvider.notifier).value = profile.id;
      await pumpEventQueue();
      await container
          .read(shikooControllerProvider)
          .refreshService(manual: false);
      expect(
        container.read(shikooStateProvider).notice,
        isA<RefreshFailed>().having((notice) => notice.clock, 'clock', isTrue),
      );
    });
  });

  test('a service without a name has an empty one, also once FlClash has '
      'put its id there', () {
    final (:container, :core, :proxies, :setup) = _home();
    final profile = container.read(profilesProvider).single;
    container
        .read(profilesProvider.notifier)
        .put(profile.copyWith(label: '${profile.id}'));
    expect(container.read(shikooStateProvider).service!.name, '');
  });

  test('the same username on two panels is two services', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    final other = panel.replaceFirst('127.0.0.1', 'localhost');
    await controller.addService('$panel/file/user111/a');
    await controller.addService('$other/file/user111/a');
    expect(
      [
        for (final p in container.read(profilesProvider))
          if (p.url.contains('/file/')) p.url,
      ],
      ['$panel/file/user111/a', '$other/file/user111/a'],
    );
  });

  test('a card the account named takes the panel name back', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    await controller.addService('$panel/file/user222/a', 'user222 · الماس');
    final named = _pasted(container).single;
    expect(named.label, 'user222 · الماس');
    await controller.renameFromPanel(named.id);
    expect(_pasted(container).single.label, 'user222');
  });

  test(
    "the ping count is the service in use's servers, not an older round's",
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final hold = Completer<void>();
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        await hold.future;
        return Delay(
          name: call.positionalArguments[1] as String,
          url: '',
          value: 50,
        );
      });
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
      final controller = container.read(shikooControllerProvider);
      unawaited(controller.pingAll());
      await pumpEventQueue();
      container.read(groupsProvider.notifier).value = [
        const Group(
          type: GroupType.Selector,
          name: 'PROXY',
          hidden: false,
          all: [
            Proxy(name: 'سوئد ۱', type: 'Vless'),
            Proxy(name: 'هلند ۱', type: 'Vless'),
          ],
        ),
      ];
      final pinging = container.read(shikooStateProvider).pinging;
      expect(pinging, (done: 1, total: 2), reason: 'only هلند ۱ is measured');
      hold.complete();
      await pumpEventQueue();
    },
  );

  test('switching with the tunnel up keeps the saved server while the core '
      'still shows the old service', () async {
    final (:container, :core, :proxies, :setup) = _home();
    Group group(List<String> names) => Group(
      type: GroupType.Selector,
      name: 'PROXY',
      hidden: false,
      all: [
        const Proxy(name: _version, type: 'Vless'),
        for (final name in names) Proxy(name: name, type: 'Vless'),
      ],
    );
    container.read(groupsProvider.notifier).value = [
      group(['هلند ۶']),
    ];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer(
      (call) async => Delay(
        name: call.positionalArguments[1] as String,
        url: '',
        value: 50,
      ),
    );
    when(() => core.getConfig(any())).thenAnswer(
      (_) async => {
        'proxies': [
          {'name': _version, 'type': 'vless'},
          {'name': 'هلند ۱', 'type': 'vless'},
        ],
        'proxy-groups': [
          {
            'name': 'PROXY',
            'type': 'select',
            'proxies': [_version, 'هلند ۱'],
          },
        ],
      },
    );
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();
    final saved = Profile.normal(
      url: 'https://panel.invalid/user111',
    ).copyWith(selectedMap: {'PROXY': 'هلند ۱'});
    container.read(profilesProvider.notifier).put(saved);
    proxies.picked.clear();

    // FlClash loads the new profile into the core a frame later; until then
    // the groups are still the old service's.
    controller.selectService(saved.id);
    await pumpEventQueue();
    Map<String, String>? selection() =>
        container.read(profilesProvider).getProfile(saved.id)?.selectedMap;
    expect(selection(), {
      'PROXY': 'هلند ۱',
    }, reason: 'what setup hands the core');
    expect(
      proxies.picked,
      isEmpty,
      reason: 'no old server for the new service',
    );

    container.read(groupsProvider.notifier).value = [
      group(['هلند ۱']),
    ];
    await pumpEventQueue();
    expect(selection(), {'PROXY': 'هلند ۱'});
    expect(proxies.picked, isEmpty);
  });

  test(
    'a link that loads again clears its card of «به‌روز نشد» at once',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final panel = await _panel(container, core);
      final controller = container.read(shikooControllerProvider);
      await controller.addService('$panel/file/user111/a');
      await controller.addService('$panel/file/user222/a');
      final [first, _] = _pasted(container);
      _gone.addAll(['/file/user111/a', '/file/user222/a']);
      await controller.refreshService();
      await controller.refreshOther(first.id);
      var state = container.read(shikooStateProvider);
      expect(state.service!.name, 'user222');
      expect(state.refresh, ShikooRefresh.failed);
      _gone.clear();
      await controller.addService('$panel/file/user111/a', null, false);
      await controller.addService('$panel/file/user222/a', null, false);
      state = container.read(shikooStateProvider);
      expect(state.refresh, ShikooRefresh.idle);
      expect(
        state.others.firstWhere((s) => s.id == first.id).refresh,
        ShikooRefresh.idle,
      );
    },
  );

  test('services without a name are told apart by number', () {
    final (:container, :core, :proxies, :setup) = _home();
    final profiles = container.read(profilesProvider.notifier);
    profiles
      ..put(Profile.normal(url: 'https://panel.invalid/b'))
      ..put(Profile.normal(url: 'https://panel.invalid/c'));
    final state = container.read(shikooStateProvider);
    expect(
      [
        for (final s in [state.service!, ...state.others]) s.number,
      ],
      [1, 2, 3],
    );
  });
}
