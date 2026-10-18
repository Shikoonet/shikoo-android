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
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/order.dart';
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

  /// Holds a change in the core until completed; the core answers each change on its own.
  final gates = <String, Completer<void>>{};

  /// Changes the core refuses: as in FlClash's own, the selection before comes back.
  final refused = <String>{};

  @override
  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    picked.add(proxyName);
    final before = ref.read(selectedMapProvider)[groupName] ?? '';
    final profiles = ref.read(profilesActionProvider.notifier);
    profiles.updateCurrentSelectedMap(groupName, proxyName);
    final gate = gates[proxyName];
    if (gate != null) await gate.future;
    if (refused.contains(proxyName)) {
      profiles.updateCurrentSelectedMap(groupName, before);
    }
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

  /// What an applied profile changes, such as the core's server list.
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
    onApply?.call();
    return true;
  }
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

class _Restart extends CoreAction {
  _Restart(this.calls, {this.fails = false, this.hold});

  final List<String> calls;
  final bool fails;
  final Future<void>? Function()? hold;

  @override
  Future<bool> restartCore() async {
    calls.add('restart');
    await hold?.call();
    if (fails) throw StateError('the core did not come back');
    return true;
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
    var state = container.read(shikooStateProvider);
    expect(state.waiting, isTrue);
    expect(state.pick, ShikooPick.finding);
    expect(state.pinging, isNull, reason: "connect's probe is not a ping");
    expect(
      state.servers.where((s) => s.testing),
      isEmpty,
      reason: 'no spinner',
    );

    netherlands.complete();
    await pumpEventQueue();
    expect(proxies.picked, ['هلند ۱'], reason: 'the first that answered');
    expect(setup.runs, [true]);
    verifyNever(() => core.asyncTestDelay(any(), _version));
    state = container.read(shikooStateProvider);
    expect(
      [for (final s in state.servers) (s.name, s.ping)],
      [('آلمان ۱', null), ('هلند ۱', 90)],
      reason: 'only the winner has a number, and the panel order stays',
    );
    expect(state.sorted, isFalse);

    // Stops the tunnel wait, which no native service would ever end here.
    await controller.disconnect();
  });

  test(
    'connect takes a usage-multiplier first answer at once, and the first '
    'ordinary server to answer then takes over, with no error (#29)',
    () async {
      const four = 'ضریب مصرف NE 4 x';
      for (final netherlandsUp in [true, false]) {
        final (:container, :core, :proxies, :setup) = _home();
        container.read(groupsProvider.notifier).value = [
          const Group(
            type: GroupType.Selector,
            name: 'PROXY',
            hidden: false,
            all: [
              Proxy(name: four, type: 'Vless'),
              Proxy(name: 'هلند ۱', type: 'Vless'),
            ],
          ),
        ];
        var firstRound = true;
        final netherlands = Completer<void>();
        when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
          final name = call.positionalArguments[1] as String;
          if (name == four) return Delay(name: name, url: '', value: 60);
          if (!firstRound) await netherlands.future;
          final up = firstRound || netherlandsUp;
          return Delay(name: name, url: '', value: up ? 90 : -1);
        });
        final controller = container.read(shikooControllerProvider);
        await controller.pingAll();
        expect(proxies.picked, ['هلند ۱'], reason: 'a ping round skips the 4x');

        container
            .read(profilesActionProvider.notifier)
            .updateCurrentSelectedMap('PROXY', 'سرور حذف‌شده');
        firstRound = false;
        unawaited(controller.connect());
        await pumpEventQueue();
        expect(proxies.picked, ['هلند ۱', four], reason: 'connect never waits');
        expect(setup.runs, [true]);

        netherlands.complete();
        await pumpEventQueue();
        final state = container.read(shikooStateProvider);
        expect(
          proxies.picked,
          ['هلند ۱', four, if (netherlandsUp) 'هلند ۱'],
          reason: netherlandsUp
              ? 'the first ordinary answer takes over'
              : 'هلند ۱ answered only the round before',
        );
        expect(setup.runs, [true], reason: 'the tunnel is not started again');
        expect((state.notice, state.lastError), (null, null));

        await controller.disconnect();
      }
    },
  );

  test('an automatic pick of a usage-multiplier server gives way at the end of '
      'a ping round to an ordinary server that answers; one the user chose '
      'stays (#29)', () async {
    const four = 'ضریب مصرف NE 4 x';
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: four, type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
        ],
      ),
    ];
    var netherlands = -1;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      final ms = name == four ? 60 : netherlands;
      return Delay(name: name, url: '', value: ms);
    });
    final controller = container.read(shikooControllerProvider);
    await controller.pingAll();
    expect(proxies.picked, [four], reason: 'nothing else answered');

    netherlands = 90;
    await controller.pingAll();
    await pumpEventQueue();
    expect(proxies.picked, [four, 'هلند ۱']);
    expect(container.read(shikooStateProvider).notice, isNull);

    await controller.selectServer(four);
    await controller.pingAll();
    await pumpEventQueue();
    expect(proxies.picked, [four, 'هلند ۱', four], reason: 'the user chose it');
    expect(container.read(shikooStateProvider).selected, four);
  });

  test('a usage-multiplier server an older version picked by itself gives '
      'way the same way after the update (#29)', () async {
    const four = 'ضریب مصرف NE 4 x';
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: four, type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
        ],
      ),
    ];
    final id = container.read(currentProfileIdProvider);
    SharedPreferences.setMockInitialValues({
      'shikoo.appPicks': '{"$id":"$four"}',
    });
    container
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap('PROXY', four);
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: name == four ? 60 : 90);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();

    await controller.pingAll();
    await pumpEventQueue();
    expect(proxies.picked, ['هلند ۱']);
  });

  test('a usage-multiplier server the user taps while connect still searches '
      'stays when an ordinary server answers after (#29)', () async {
    const four = 'ضریب مصرف NE 4 x';
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: four, type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
        ],
      ),
    ];
    final answers = Completer<void>();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      await answers.future;
      return Delay(name: name, url: '', value: name == four ? 60 : 90);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    unawaited(controller.connect());
    await pumpEventQueue();
    await controller.selectServer(four);

    answers.complete();
    await pumpEventQueue();
    expect(proxies.picked, [four]);
    expect(container.read(shikooStateProvider).selected, four);

    await controller.disconnect();
  });

  test('an automatic pick that stops answering gives way to an ordinary '
      'server, not to a faster usage-multiplier one (#29)', () async {
    const four = 'NL 3 x ضریب مصرف';
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: four, type: 'Vless'),
          Proxy(name: 'آلمان ۱', type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
        ],
      ),
    ];
    final pings = {four: 40, 'آلمان ۱': 50, 'هلند ۱': 90};
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
    expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
    expect(
      container.read(shikooStateProvider).notice,
      isA<SilentReplaced>().having((n) => n.replacement, 'to', 'هلند ۱'),
    );
  });

  test('the search moves off a usage-multiplier first answer one change at a '
      'time: whichever change the core refuses, in either order, connecting '
      'or connected, the wait ends on the server the core has, and the app '
      'pick names it (#29)', () async {
    const four = 'ضریب مصرف NE 4 x';
    const nl = 'هلند ۱';
    for (final refused in [
      <String>{},
      {nl},
      {four},
      {four, nl},
    ]) {
      for (final connected in [false, true]) {
        for (final fourFirst in [true, false]) {
          final (:container, :core, :proxies, :setup) = _home();
          container.read(groupsProvider.notifier).value = [
            const Group(
              type: GroupType.Selector,
              name: 'PROXY',
              hidden: false,
              all: [
                Proxy(name: four, type: 'Vless'),
                Proxy(name: nl, type: 'Vless'),
              ],
            ),
          ];
          final netherlands = Completer<void>();
          when(() => core.asyncTestDelay(any(), any())).thenAnswer((
            call,
          ) async {
            final name = call.positionalArguments[1] as String;
            if (name != four) await netherlands.future;
            return Delay(name: name, url: '', value: name == four ? 60 : 70);
          });
          proxies.gates.addAll({four: Completer(), nl: Completer()});
          proxies.refused.addAll(refused);
          final errors = <ShikooError?>[];
          container.listen(
            shikooStateProvider.select((s) => s.lastError),
            (_, error) => errors.add(error),
          );
          final controller = container.read(shikooControllerProvider);
          await pumpEventQueue();
          if (connected) {
            setup.tunnel = DateTime(2026);
            container.read(runTimeProvider.notifier).value = 1;
          } else {
            unawaited(controller.connect());
          }
          await pumpEventQueue();
          netherlands.complete();
          await pumpEventQueue();
          final reason =
              'refused=$refused connected=$connected '
              'fourFirst=$fourFirst';
          expect(proxies.picked, [four], reason: 'one at a time, $reason');

          for (final name in fourFirst ? [four, nl] : [nl, four]) {
            proxies.gates[name]!.complete();
            await pumpEventQueue();
          }
          final state = container.read(shikooStateProvider);
          final has = refused.contains(nl)
              ? (refused.contains(four) ? null : four)
              : nl;
          final id = container.read(currentProfileIdProvider);
          final picks = (await SharedPreferences.getInstance()).getString(
            'shikoo.appPicks',
          );
          expect(proxies.picked, [four, nl], reason: reason);
          expect((state.waiting, state.selected), (false, has), reason: reason);
          expect(picks, has == null ? '{}' : '{"$id":"$has"}', reason: reason);
          expect(
            setup.runs,
            connected || has == null ? isEmpty : [true],
            reason: reason,
          );
          expect(
            state.lastError,
            refused.contains(nl) && (connected || has == null)
                ? ShikooError.serverChange
                : null,
            reason: reason,
          );
          if (!refused.contains(nl)) {
            expect(
              errors,
              isNot(contains(ShikooError.serverChange)),
              reason: reason,
            );
          }
          expect(
            state.servers.firstWhere((s) => s.name == nl).ping,
            70,
            reason: 'the server moved to keeps the ping it answered with',
          );

          await controller.disconnect();
        }
      }
    }
  });

  test('a server change the core refuses says so and keeps whose pick the '
      'server was', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final id = container.read(currentProfileIdProvider);
    SharedPreferences.setMockInitialValues({
      'shikoo.appPicks': '{"$id":"آلمان ۱"}',
    });
    container
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap('PROXY', 'آلمان ۱');
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();

    proxies.refused.add('هلند ۱');
    await controller.selectServer('هلند ۱');
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(
      (state.selected, state.lastError),
      ('آلمان ۱', ShikooError.serverChange),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shikoo.appPicks'), '{"$id":"آلمان ۱"}');
  });

  test('server changes reach the core one at a time, and one overtaken while '
      'it waits is never sent', () async {
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: 'آلمان ۱', type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
          Proxy(name: 'فنلاند ۱', type: 'Vless'),
        ],
      ),
    ];
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    final germany = proxies.gates['آلمان ۱'] = Completer();

    for (final name in ['آلمان ۱', 'هلند ۱', 'فنلاند ۱']) {
      unawaited(controller.selectServer(name));
    }
    await pumpEventQueue();
    expect(proxies.picked, ['آلمان ۱']);
    germany.complete();
    await pumpEventQueue();
    expect(proxies.picked, ['آلمان ۱', 'فنلاند ۱']);
    expect(container.read(shikooStateProvider).selected, 'فنلاند ۱');
  });

  test("a server the customer taps while the app's change is still in the "
      'core shows at once and stays when an ordinary server answers after, '
      'usage-multiplier or not (#29)', () async {
    const four = 'ضریب مصرف NE 4 x';
    const three = 'NL 3 x ضریب مصرف';
    for (final tapped in [three, 'آلمان ۱']) {
      final (:container, :core, :proxies, :setup) = _home();
      container.read(groupsProvider.notifier).value = [
        const Group(
          type: GroupType.Selector,
          name: 'PROXY',
          hidden: false,
          all: [
            Proxy(name: four, type: 'Vless'),
            Proxy(name: three, type: 'Vless'),
            Proxy(name: 'هلند ۱', type: 'Vless'),
            Proxy(name: 'آلمان ۱', type: 'Vless'),
          ],
        ),
      ];
      final netherlands = Completer<void>();
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        if (name == 'هلند ۱') await netherlands.future;
        final ms = {four: 60, 'هلند ۱': 70}[name] ?? -1;
        return Delay(name: name, url: '', value: ms);
      });
      final held = proxies.gates[four] = Completer();
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      unawaited(controller.connect());
      await pumpEventQueue();

      unawaited(controller.selectServer(tapped));
      await pumpEventQueue();
      expect(container.read(shikooStateProvider).selected, tapped);
      netherlands.complete();
      await pumpEventQueue();
      held.complete();
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      expect(proxies.picked, [four, tapped], reason: tapped);
      expect(container.read(shikooStateProvider).selected, tapped);
      expect(prefs.getString('shikoo.appPicks'), '{}', reason: 'a hand pick');
      expect(setup.runs, [true]);

      await controller.disconnect();
    }
  });

  test('the first ordinary server to answer takes over from a '
      'usage-multiplier first answer still in the core; one answering later '
      'changes nothing (#29)', () async {
    const four = 'ضریب مصرف NE 4 x';
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: four, type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
          Proxy(name: 'آلمان ۱', type: 'Vless'),
        ],
      ),
    ];
    final answers = {'هلند ۱': Completer<void>(), 'آلمان ۱': Completer<void>()};
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      await answers[name]?.future;
      return Delay(name: name, url: '', value: name == four ? 60 : 50);
    });
    final held = proxies.gates[four] = Completer();
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    unawaited(controller.connect());
    await pumpEventQueue();

    for (final answer in answers.values) {
      answer.complete();
      await pumpEventQueue();
    }
    expect(container.read(shikooStateProvider).selected, 'هلند ۱');
    held.complete();
    await pumpEventQueue();
    final id = container.read(currentProfileIdProvider);
    final prefs = await SharedPreferences.getInstance();
    expect(proxies.picked, [four, 'هلند ۱']);
    expect(container.read(shikooStateProvider).selected, 'هلند ۱');
    expect(prefs.getString('shikoo.appPicks'), '{"$id":"هلند ۱"}');

    await controller.disconnect();
  });

  test('connect pressed again while the first search\'s 4x change is still in '
      'the core: a change still waiting to be sent keeps the search going, '
      'and it connects once that change is sent (#29)', () async {
    const four = 'ضریب مصرف NE 4 x';
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: four, type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
        ],
      ),
    ];
    final netherlands = Completer<void>();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name == 'هلند ۱') await netherlands.future;
      return Delay(name: name, url: '', value: name == four ? 60 : 90);
    });
    final held = proxies.gates[four] = Completer();
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    unawaited(controller.connect());
    await pumpEventQueue();
    await controller.disconnect();
    unawaited(controller.connect());
    await pumpEventQueue();

    netherlands.complete();
    await pumpEventQueue();
    var state = container.read(shikooStateProvider);
    expect((state.waiting, state.lastError), (true, null));
    held.complete();
    await pumpEventQueue();
    state = container.read(shikooStateProvider);
    expect(proxies.picked, [four, 'هلند ۱']);
    expect(
      (state.selected, state.connection),
      ('هلند ۱', ShikooConnection.connecting),
    );
    expect(setup.runs, [false, true]);

    await controller.disconnect();
  });

  test("a tap the core refuses while connect searches connects on the app's "
      'server it falls back to, and says the tap failed', () async {
    const four = 'ضریب مصرف NE 4 x';
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: four, type: 'Vless'),
          Proxy(name: 'آلمان ۱', type: 'Vless'),
        ],
      ),
    ];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: name == four ? 60 : -1);
    });
    final held = proxies.gates[four] = Completer();
    proxies.refused.add('آلمان ۱');
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    unawaited(controller.connect());
    await pumpEventQueue();

    unawaited(controller.selectServer('آلمان ۱'));
    await pumpEventQueue();
    held.complete();
    await pumpEventQueue();
    var state = container.read(shikooStateProvider);
    final id = container.read(currentProfileIdProvider);
    final prefs = await SharedPreferences.getInstance();
    expect(proxies.picked, [four, 'آلمان ۱']);
    expect(
      (state.selected, state.connection, state.lastError),
      (four, ShikooConnection.connecting, ShikooError.serverChange),
    );
    expect(setup.runs, [true]);
    expect(prefs.getString('shikoo.appPicks'), '{"$id":"$four"}');

    setup.tunnel = DateTime(2026);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    state = container.read(shikooStateProvider);
    expect(
      (state.connection, state.lastError),
      (ShikooConnection.on, ShikooError.serverChange),
      reason: 'still said once connected',
    );

    await controller.disconnect();
  });

  test('the app keeps its own pick across rounds: no change while only '
      'usage-multiplier servers answer, and the ordinary server it moves to '
      'is replaced when it goes silent (#29)', () async {
    const four = 'ضریب مصرف NE 4 x';
    const three = 'NL 3 x ضریب مصرف';
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: four, type: 'Vless'),
          Proxy(name: three, type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
          Proxy(name: 'آلمان ۱', type: 'Vless'),
        ],
      ),
    ];
    final pings = {four: 60};
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    final controller = container.read(shikooControllerProvider);
    await controller.pingAll();
    expect(proxies.picked, [four]);

    pings[three] = 40;
    await controller.pingAll();
    await pumpEventQueue();
    expect(proxies.picked, [four], reason: 'a change cuts every connection');

    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    pings['هلند ۱'] = 90;
    await controller.pingAll();
    await pumpEventQueue();
    expect(proxies.picked, [four, 'هلند ۱']);

    pings['هلند ۱'] = -1;
    pings['آلمان ۱'] = 50;
    await controller.pingAll();
    await pumpEventQueue();
    expect(proxies.picked, [four, 'هلند ۱', 'آلمان ۱']);
    expect(
      container.read(shikooStateProvider).notice,
      isA<SilentReplaced>().having((n) => n.silent, 'from', 'هلند ۱'),
    );
  });

  test(
    "connect sets aside the app's own usage-multiplier pick and searches "
    'as for a new customer, also when pressed before the servers are known: '
    'the first answer at once, then an ordinary server, now the pick (#29)',
    () async {
      const four = 'ضریب مصرف NE 4 x';
      const servers = [
        Group(
          type: GroupType.Selector,
          name: 'PROXY',
          hidden: false,
          all: [
            Proxy(name: four, type: 'Vless'),
            Proxy(name: 'هلند ۱', type: 'Vless'),
          ],
        ),
      ];
      for (final early in [false, true]) {
        final (:container, :core, :proxies, :setup) = _home();
        container.read(groupsProvider.notifier).value = early ? [] : servers;
        final id = container.read(currentProfileIdProvider);
        SharedPreferences.setMockInitialValues({
          'shikoo.appPicks': '{"$id":"$four"}',
        });
        container
            .read(profilesActionProvider.notifier)
            .updateCurrentSelectedMap('PROXY', four);
        when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
          final name = call.positionalArguments[1] as String;
          return Delay(name: name, url: '', value: name == four ? 60 : 90);
        });
        final controller = container.read(shikooControllerProvider);
        await pumpEventQueue();

        unawaited(controller.connect());
        await pumpEventQueue();
        if (early) container.read(groupsProvider.notifier).value = servers;
        await pumpEventQueue();
        expect(proxies.picked, [four, 'هلند ۱'], reason: 'early=$early');
        expect(setup.runs, [true]);
        expect(container.read(shikooStateProvider).selected, 'هلند ۱');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('shikoo.appPicks'), '{"$id":"هلند ۱"}');

        await controller.disconnect();
      }
    },
  );

  test('connect starts at once, with no search, on a usage-multiplier server '
      "the customer chose and on the app's own ordinary pick (#29)", () async {
    const four = 'ضریب مصرف NE 4 x';
    for (final (server, appPick) in [(four, null), ('هلند ۱', 'هلند ۱')]) {
      final (:container, :core, :proxies, :setup) = _home();
      container.read(groupsProvider.notifier).value = [
        const Group(
          type: GroupType.Selector,
          name: 'PROXY',
          hidden: false,
          all: [
            Proxy(name: four, type: 'Vless'),
            Proxy(name: 'هلند ۱', type: 'Vless'),
          ],
        ),
      ];
      final id = container.read(currentProfileIdProvider);
      SharedPreferences.setMockInitialValues({
        if (appPick != null) 'shikoo.appPicks': '{"$id":"$appPick"}',
      });
      container
          .read(profilesActionProvider.notifier)
          .updateCurrentSelectedMap('PROXY', server);
      when(() => core.asyncTestDelay(any(), any())).thenAnswer(
        (call) async => Delay(
          name: call.positionalArguments[1] as String,
          url: '',
          value: 60,
        ),
      );
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();

      unawaited(controller.connect());
      await pumpEventQueue();
      verifyNever(() => core.asyncTestDelay(any(), any()));
      expect(proxies.picked, isEmpty, reason: server);
      expect(setup.runs, [true]);
      expect(container.read(shikooStateProvider).selected, server);

      await controller.disconnect();
    }
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

  test('"no server answered" stays until the next try; a ping that finds '
      'one ends it without connecting', () async {
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
    expect(container.read(shikooStateProvider).pick, ShikooPick.none);

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
    expect(
      container.read(shikooStateProvider).lastError,
      ShikooError.noServer,
      reason: 'a new list is not a try: nothing is pinged by itself',
    );

    await controller.pingAll();
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
    await controller.pingAll();
    expect(proxies.picked, ['آلمان ۱'], reason: 'the app, in the first');
    final first = container.read(currentProfileIdProvider)!;
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    controller.selectService(second.id);
    await pumpEventQueue();
    await controller.selectServer('آلمان ۱');

    pings['آلمان ۱'] = -1;
    controller.selectService(first);
    await pumpEventQueue();
    await controller.pingAll();
    expect(
      proxies.picked.last,
      'هلند ۱',
      reason: "the user's pick in the second left the first one the app's",
    );

    final picks = proxies.picked.length;
    controller.selectService(second.id);
    await pumpEventQueue();
    await controller.pingAll();
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
      await controller.pingAll();
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
      controller.onBackground();
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
      await controller.pingAll();
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
      await controller.pingAll();
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
    await controller.pingAll();
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
    await controller.pingAll();
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
    await controller.pingAll();
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
    expect((await controller.pasteService(null)).error, ShikooPasteError.empty);
    expect(
      (await controller.pasteService(' \n ')).error,
      ShikooPasteError.empty,
    );
    expect(
      (await controller.pasteService('https://example.com/sub/token')).error,
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
        (await controller.pasteService(
          'سرویسم: https://4g3.uk/sub/mine.',
        )).error,
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
      await controller.pingAll();
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

  test(
    'another service starts with no numbers, no order and a pill at rest: '
    'two services may share server names, and nothing is pinged by itself',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final probes = <String>[];
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        probes.add(name);
        return Delay(name: name, url: '', value: -1);
      });
      final controller = container.read(shikooControllerProvider);
      await controller.pingAll();
      var state = container.read(shikooStateProvider);
      expect(state.pick, ShikooPick.none, reason: 'none answered the ping');
      expect(state.sorted, isTrue);

      final second = Profile.normal(url: 'https://panel.invalid/second');
      container.read(profilesProvider.notifier).put(second);
      probes.clear();
      controller.selectService(second.id);
      await pumpEventQueue();
      state = container.read(shikooStateProvider);
      expect(state.service!.id, second.id);
      expect(state.pick, ShikooPick.auto, reason: 'not none, not finding');
      expect(state.servers.map((s) => s.ping), everyElement(isNull));
      expect(state.sorted, isFalse);
      expect(probes, isEmpty);
      expect(proxies.picked, isEmpty);
    },
  );

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
      expect(state.selected, isNull, reason: 'nothing is measured by itself');
      expect(state.pick, ShikooPick.auto);
    },
  );

  test('only a ping sorts: a tap off measures nothing, and a server measured '
      'on its own once connected keeps its row', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
    final probes = <String>[];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      probes.add(name);
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    final controller = container.read(shikooControllerProvider);
    List<String> order() => [
      for (final server in container.read(shikooStateProvider).servers)
        server.name,
    ];
    await controller.pingAll();
    expect(order().take(2), ['آلمان ۱', 'هلند ۱']);

    pings['هلند ۱'] = 10;
    probes.clear();
    await controller.selectServer('هلند ۱');
    expect(probes, isEmpty, reason: 'off, a tap only chooses');

    setup.tunnel = DateTime(2026);
    await controller.connect();
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.connection, ShikooConnection.on);
    expect(probes, ['هلند ۱'], reason: 'connected: the selected server alone');
    expect(state.selectedServer?.ping, 10);
    expect(order().take(2), [
      'آلمان ۱',
      'هلند ۱',
    ], reason: 'faster now, yet its row stays until a ping');

    await controller.pingAll();
    expect(order().take(2), ['هلند ۱', 'آلمان ۱']);
    await controller.disconnect();
  });

  test("connected, a switch's own answer leaves the rows where they are and "
      'shows its fresh number; the next round puts them in order', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    final controller = container.read(shikooControllerProvider);
    await controller.pingAll();
    container.read(runTimeProvider.notifier).value = 1;
    await pumpEventQueue();
    List<String> order() => [
      for (final server in container.read(shikooStateProvider).servers)
        server.name,
    ];

    pings['هلند ۱'] = 10;
    await controller.selectServer('هلند ۱');
    final state = container.read(shikooStateProvider);
    expect(state.switching?.stage, ShikooSwitchStage.done);
    expect(state.selectedServer?.ping, 10, reason: "the switch's, not 90");
    expect(order().take(2), ['آلمان ۱', 'هلند ۱']);
    await controller.pingAll();
    expect(order().take(2), ['هلند ۱', 'آلمان ۱']);
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
    await controller.pingAll();
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

  test('connected, a tapped server that does not answer says so for a few '
      'seconds too, and the tunnel stays where it was (#32)', () async {
    final (:container, :core, :proxies, :setup) = _home();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: name == 'هلند ۱' ? -1 : 50);
    });
    final controller = container.read(shikooControllerProvider);
    await controller.pingAll();
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();

    await controller.selectServer('هلند ۱');
    expect(container.read(shikooStateProvider).switching, (
      to: 'هلند ۱',
      from: 'آلمان ۱',
      stage: ShikooSwitchStage.failed,
    ));

    await Future<void>.delayed(switchedFor);
    final state = container.read(shikooStateProvider);
    expect(state.switching, isNull);
    expect(state.selected, 'آلمان ۱');
    expect(proxies.picked, ['آلمان ۱']);
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
    await controller.pingAll();
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
    await controller.pingAll();
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

  /// Connected on آلمان ۱; هلند ۱ answers 90 once [gate] is completed.
  Future<
    ({
      ProviderContainer container,
      _Proxies proxies,
      _Setup setup,
      ShikooController controller,
      Completer<void> gate,
    })
  >
  connected() async {
    final (:container, :core, :proxies, :setup) = _home();
    final gate = Completer<void>();
    var armed = false;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (armed && name == 'هلند ۱') await gate.future;
      return Delay(name: name, url: '', value: name == 'هلند ۱' ? 90 : 50);
    });
    final controller = container.read(shikooControllerProvider);
    await controller.pingAll();
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();
    armed = true;
    return (
      container: container,
      proxies: proxies,
      setup: setup,
      controller: controller,
      gate: gate,
    );
  }

  /// Connected on آلمان ۱; آلمان ۳ is a WireGuard server whose ping fails and whose
  /// traffic check waits for `setup.trafficGate`.
  Future<
    ({
      ProviderContainer container,
      _Proxies proxies,
      _Setup setup,
      ShikooController controller,
    })
  >
  wireGuard({required bool traffic}) async {
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: 'آلمان ۱', type: 'Vless'),
          Proxy(name: 'آلمان ۳', type: 'WireGuard'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
        ],
      ),
    ];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: name == 'آلمان ۳' ? -1 : 60);
    });
    final controller = container.read(shikooControllerProvider);
    await controller.pingAll();
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();
    setup
      ..traffic = traffic
      ..trafficGate = Completer<void>();
    return (
      container: container,
      proxies: proxies,
      setup: setup,
      controller: controller,
    );
  }

  test('a tap while still connecting moves at once, as when off', () async {
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
    container.read(runTimeProvider.notifier).value = 1;
    unawaited(controller.connect());
    await pumpEventQueue();
    expect(
      container.read(shikooStateProvider).connection,
      ShikooConnection.connecting,
    );

    await controller.selectServer('هلند ۱');
    expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
    expect(container.read(shikooStateProvider).switching, isNull);
    await controller.disconnect();
  });

  test('a tunnel that drops by itself during a switch ends it at once, with '
      'no move and no news', () async {
    final (:container, :proxies, :setup, :controller, :gate) =
        await connected();
    final tap = controller.selectServer('هلند ۱');
    await pumpEventQueue();
    expect(
      container.read(shikooStateProvider).switching?.stage,
      ShikooSwitchStage.moving,
    );
    container.read(runTimeProvider.notifier).value = null;
    setup.tunnel = null;
    await pumpEventQueue();
    expect(container.read(shikooStateProvider).switching, isNull);

    gate.complete();
    await tap;
    expect(proxies.picked, ['آلمان ۱']);
    expect(container.read(shikooStateProvider).switching, isNull);
  });

  test('another service during a switch drops it', () async {
    final (:container, :proxies, :setup, :controller, :gate) =
        await connected();
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    final tap = controller.selectServer('هلند ۱');
    await pumpEventQueue();
    controller.selectService(second.id);
    await pumpEventQueue();
    expect(container.read(shikooStateProvider).switching, isNull);

    gate.complete();
    await tap;
    await pumpEventQueue();
    expect(proxies.picked, isNot(contains('هلند ۱')));
    expect(container.read(shikooStateProvider).switching, isNull);
  });

  test('leaving the app keeps a switch under way, which then lands', () async {
    final (:container, :proxies, :setup, :controller, :gate) =
        await connected();
    final tap = controller.selectServer('هلند ۱');
    await pumpEventQueue();
    controller.onBackground();
    expect(
      container.read(shikooStateProvider).switching?.stage,
      ShikooSwitchStage.moving,
    );

    gate.complete();
    await tap;
    expect(proxies.picked, ['آلمان ۱', 'هلند ۱']);
    expect(
      container.read(shikooStateProvider).switching?.stage,
      ShikooSwitchStage.done,
    );
  });

  test('a server an update takes away during its switch gets no traffic and '
      'no news', () async {
    final (:container, :proxies, :setup, :controller, :gate) =
        await connected();
    final tap = controller.selectServer('هلند ۱');
    await pumpEventQueue();
    container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: _version, type: 'Vless'),
          Proxy(name: 'آلمان ۱', type: 'Vless'),
        ],
      ),
    ];
    await pumpEventQueue();

    gate.complete();
    await tap;
    await pumpEventQueue();
    expect(proxies.picked, isNot(contains('هلند ۱')));
    expect(container.read(shikooStateProvider).switching, isNull);
  });

  test('a WireGuard check that ends after a newer tap landed changes nothing: '
      'no way back, no news over the newer one', () async {
    for (final traffic in [false, true]) {
      final (:container, :proxies, :setup, :controller) = await wireGuard(
        traffic: traffic,
      );
      final check = controller.selectServer('آلمان ۳');
      await pumpEventQueue();
      expect(proxies.picked, ['آلمان ۱', 'آلمان ۳'], reason: '$traffic');

      await controller.selectServer('هلند ۱');
      setup.trafficGate!.complete();
      await check;
      final state = container.read(shikooStateProvider);
      expect(proxies.picked, [
        'آلمان ۱',
        'آلمان ۳',
        'هلند ۱',
      ], reason: '$traffic');
      expect(state.selected, 'هلند ۱', reason: '$traffic');
      expect(state.switching, (
        to: 'هلند ۱',
        from: 'آلمان ۳',
        stage: ShikooSwitchStage.done,
      ), reason: '$traffic');
    }
  });

  test('tapping the row already on its way does nothing, also during the '
      'WireGuard check', () async {
    final (:container, :proxies, :setup, :controller) = await wireGuard(
      traffic: false,
    );
    final first = controller.selectServer('آلمان ۳');
    await pumpEventQueue();
    await controller.selectServer('آلمان ۳');
    expect(proxies.picked, ['آلمان ۱', 'آلمان ۳']);
    expect(container.read(shikooStateProvider).switching, (
      to: 'آلمان ۳',
      from: 'آلمان ۱',
      stage: ShikooSwitchStage.moving,
    ));

    setup.trafficGate!.complete();
    await first;
    expect(proxies.picked, ['آلمان ۱', 'آلمان ۳', 'آلمان ۱']);
    expect(container.read(shikooStateProvider).switching, (
      to: 'آلمان ۳',
      from: 'آلمان ۱',
      stage: ShikooSwitchStage.failed,
    ));
  });

  test('a failed switch stays through an update, unless the update takes '
      'one of its servers away', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    container
        .read(profilesProvider.notifier)
        .put(
          container
              .read(profilesProvider)
              .single
              .copyWith(url: '$panel/none/a'),
        );
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      return Delay(name: name, url: '', value: name == 'هلند ۱' ? -1 : 50);
    });
    final controller = container.read(shikooControllerProvider);
    await controller.pingAll();
    container.read(runTimeProvider.notifier).value = 1;
    await pumpEventQueue();
    await controller.selectServer('هلند ۱');
    final failed = container.read(shikooStateProvider).switching;
    expect(failed?.stage, ShikooSwitchStage.failed);

    await controller.refreshService(manual: false);
    var state = container.read(shikooStateProvider);
    expect(state.refresh, ShikooRefresh.idle, reason: 'it went through');
    expect(state.switching, failed);

    setup.onApply = () => container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [Proxy(name: 'آلمان ۱', type: 'Vless')],
      ),
    ];
    await controller.refreshService(manual: false);
    state = container.read(shikooStateProvider);
    expect(state.refresh, ShikooRefresh.idle);
    expect(state.switching, isNull, reason: 'هلند ۱ left with it');
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
    await controller.pingAll();
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
    'connected, another service with no server of its own connects to the '
    'first that answers now: never row 1, never a number from before',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final germany = Completer<void>();
      var switched = false;
      final probes = <String>[];
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        if (switched) probes.add(name);
        final netherlands = name == 'هلند ۱';
        if (!switched) {
          return Delay(name: name, url: '', value: netherlands ? 40 : 50);
        }
        if (!netherlands) await germany.future;
        return Delay(name: name, url: '', value: netherlands ? 3466 : 120);
      });
      final controller = container.read(shikooControllerProvider);
      await controller.pingAll();
      expect(proxies.picked, ['هلند ۱']);
      container.read(runTimeProvider.notifier).value = 1;
      setup.tunnel = DateTime(2026);
      await pumpEventQueue();
      final second = Profile.normal(url: 'https://panel.invalid/second');
      container.read(profilesProvider.notifier).put(second);
      Map<String, String>? held;
      container.listen(currentProfileIdProvider, (_, id) {
        held = container.read(profilesProvider).getProfile(id!)?.selectedMap;
      });
      switched = true;
      controller.selectService(second.id);
      await pumpEventQueue();
      expect(
        held,
        isEmpty,
        reason: 'no stale or blind pick handed to the core',
      );
      var state = container.read(shikooStateProvider);
      expect(proxies.picked, [
        'هلند ۱',
        'هلند ۱',
      ], reason: 'the first answer of this probe, slow as it is');
      expect(state.connection, ShikooConnection.on);
      expect(state.selected, 'هلند ۱');
      expect(
        state.selectedServer?.ping,
        3466,
        reason: 'not the 40 from before',
      );
      expect(setup.runs, isEmpty, reason: 'the tunnel stays up throughout');

      germany.complete();
      await pumpEventQueue();
      state = container.read(shikooStateProvider);
      expect(proxies.picked, hasLength(2), reason: 'the probe only connects');
      expect(
        state.servers.firstWhere((s) => s.name == 'آلمان ۱').ping,
        isNull,
        reason: 'a probe shows no other numbers',
      );
      expect(state.sorted, isFalse);
      expect(state.notice, isNull);
      expect(probes, isNot(contains(_version)));
    },
  );

  test('connected, another service with a server of its own measures that '
      "one alone: the customer's own stays though silent, the app's own gives "
      'way to the fastest after one round', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final pings = {'آلمان ۱': 50, 'هلند ۱': 90};
    final probes = <String>[];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      probes.add(name);
      return Delay(name: name, url: '', value: pings[name] ?? -1);
    });
    final controller = container.read(shikooControllerProvider);
    final first = container.read(currentProfileIdProvider)!;
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    await controller.pingAll();
    expect(proxies.picked, ['آلمان ۱'], reason: "the app's own, in the first");
    controller.selectService(second.id);
    await pumpEventQueue();
    await controller.selectServer('آلمان ۱');
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();

    pings['آلمان ۱'] = -1;
    probes.clear();
    controller.selectService(first);
    await pumpEventQueue();
    expect(probes.take(2), [
      'آلمان ۱',
      'آلمان ۱',
    ], reason: 'the selected server alone, in two passes');
    expect(probes.skip(2).toSet(), {
      'آلمان ۱',
      'هلند ۱',
    }, reason: 'then one round, for the silent pick of the app');
    var state = container.read(shikooStateProvider);
    expect(state.selected, 'هلند ۱');
    expect(
      state.notice,
      isA<SilentReplaced>().having((n) => n.moved, 'moved', isTrue),
    );

    probes.clear();
    controller.selectService(second.id);
    await pumpEventQueue();
    state = container.read(shikooStateProvider);
    expect(probes, ['آلمان ۱', 'آلمان ۱'], reason: 'one server, two passes');
    expect(state.selected, 'آلمان ۱', reason: "the customer's own stays");
    expect(state.selectedServer?.ping, -1, reason: 'with its warning');
    expect(state.connection, ShikooConnection.on);
  });

  test("connect's probe that answers after a switch picks nothing for the new "
      'service, whose servers share its names', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final first = Completer<void>();
    final second = Completer<void>();
    var calls = 0;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name != 'هلند ۱') return Delay(name: name, url: '', value: -1);
      await (++calls == 1 ? first : second).future;
      return Delay(name: name, url: '', value: 90);
    });
    final controller = container.read(shikooControllerProvider);
    unawaited(controller.connect());
    await pumpEventQueue();
    final other = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(other);
    controller.selectService(other.id);
    await pumpEventQueue();
    expect(container.read(shikooStateProvider).waiting, isTrue);

    first.complete();
    await pumpEventQueue();
    expect(proxies.picked, isEmpty, reason: "the first service's answer");

    second.complete();
    await pumpEventQueue();
    expect(proxies.picked, ['هلند ۱'], reason: 'its own probe');
    await controller.disconnect();
  });

  test("a round that ends after a switch writes nothing on the new service's "
      'servers, which share its names', () async {
    final (:container, :core, :proxies, :setup) = _home();
    Completer<void>? netherlands;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name == 'هلند ۱') await netherlands?.future;
      return Delay(name: name, url: '', value: 50);
    });
    final controller = container.read(shikooControllerProvider);
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    netherlands = Completer<void>();
    final round = controller.pingAll();
    await pumpEventQueue();
    controller.selectService(second.id);
    await pumpEventQueue();
    netherlands.complete();
    await round;
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.service!.id, second.id);
    expect(state.servers.map((s) => s.ping), everyElement(isNull));
    expect(state.pinging, isNull);
    expect(state.sorted, isFalse);
    expect(state.selected, isNull);
    expect(state.notice, isNull);
    expect(proxies.picked, isEmpty);
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
        (await controller.pasteService('$emulator/$link', debug: true)).error,
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

  test('nothing is pinged by itself: not on open, nor on coming back, nor on '
      'another service, nor after an update, nor with every card folded; '
      'opening a card pings it', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final first = container.read(profilesProvider).single;
    container
        .read(profilesProvider.notifier)
        .put(first.copyWith(url: '$panel/none/a'));
    final probes = <String>[];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      probes.add(name);
      return Delay(name: name, url: '', value: 50);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    expect(probes, isEmpty, reason: 'open');
    expect(container.read(shikooStateProvider).pick, ShikooPick.auto);

    controller.onForeground();
    await controller.refreshDue();
    await pumpEventQueue();
    expect(probes, isEmpty, reason: 'back in the app, and its update');

    final second = Profile.normal(url: '$panel/none/b');
    container.read(profilesProvider.notifier).put(second);
    controller.selectService(second.id);
    await pumpEventQueue();
    controller.selectService(first.id);
    await pumpEventQueue();
    expect(probes, isEmpty, reason: 'another service, and back');

    await controller.selectServer('آلمان ۱');
    setup.onApply = () => container.read(groupsProvider.notifier).value = [
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
    await controller.refreshService();
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.notice, isA<ServersChanged>());
    expect(state.selected, 'آلمان ۱');
    expect(probes, isEmpty, reason: 'after an update');

    controller.openService(null);
    await pumpEventQueue();
    expect(probes, isEmpty, reason: 'every card folded');
    controller.openService(first.id);
    await pumpEventQueue();
    expect(probes, unorderedEquals(['آلمان ۱', 'هلند ۱', 'ترکیه ۱']));
    expect(container.read(shikooStateProvider).sorted, isTrue);
  });

  test('an update that takes the selected server away pings that service once '
      'and names the fastest of this round, not of an older one; connected, '
      'the first answer takes the traffic and is then checked', () async {
    for (final mode in ['pinged', 'off', 'connected']) {
      final (:container, :core, :proxies, :setup) = _home();
      final panel = await _panel(container, core);
      container
          .read(profilesProvider.notifier)
          .put(
            container
                .read(profilesProvider)
                .single
                .copyWith(url: '$panel/none/a'),
          );
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
        group(['آلمان ۱', 'هلند ۱', 'ترکیه ۱']),
      ];
      final pings = {'آلمان ۱': 50, 'هلند ۱': 90, 'ترکیه ۱': 60};
      final probes = <String>[];
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        probes.add(name);
        return Delay(name: name, url: '', value: pings[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      if (mode == 'pinged') {
        await controller.pingAll();
      } else {
        await controller.selectServer('آلمان ۱');
      }
      if (mode == 'connected') {
        container.read(runTimeProvider.notifier).value = 1;
        setup.tunnel = DateTime(2026);
        await pumpEventQueue();
      }
      expect(container.read(shikooStateProvider).selected, 'آلمان ۱');
      probes.clear();
      pings['هلند ۱'] = 30;
      setup.onApply = () => container.read(groupsProvider.notifier).value = [
        group(['هلند ۱', 'ترکیه ۱']),
      ];
      await controller.refreshService();
      await pumpEventQueue();
      final state = container.read(shikooStateProvider);
      expect(state.selected, 'هلند ۱', reason: "$mode: this round's fastest");
      expect(probes.toSet(), {
        'هلند ۱',
        'ترکیه ۱',
      }, reason: '$mode: one round, never row 1');
      expect(state.sorted, isTrue, reason: mode);
      if (mode == 'connected') {
        expect(state.connection, ShikooConnection.on);
        expect(
          probes.where((name) => name == 'هلند ۱'),
          hasLength(2),
          reason: 'the round, then the check of the new server',
        );
        expect(
          state.notice,
          isA<SelectedReplaced>()
              .having((n) => n.fastest, 'fastest', false)
              .having((n) => n.moved, 'moved', true),
        );
      } else {
        expect(
          state.notice,
          isA<SelectedReplaced>()
              .having((n) => n.fastest, 'fastest', true)
              .having((n) => n.moved, 'moved', false),
        );
      }
    }
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

  test('a service the door says runs again skips the ten-minute wait, even '
      'named while a round is under way, at most once a minute', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    for (final user in ['user111', 'user222']) {
      await controller.addService('$panel/file/$user/a');
    }
    final profiles = container.read(profilesProvider.notifier);
    final [renewed, due] = _pasted(container);
    final now = DateTime.now();
    for (final profile in container.read(profilesProvider)) {
      profiles.put(
        profile.copyWith(
          lastUpdateDate: profile.id == due.id ? DateTime(2020) : now,
        ),
      );
    }
    Profile current() =>
        container.read(profilesProvider).getProfile(renewed.id)!;
    void endIt(DateTime at) => profiles.put(
      current().copyWith(
        lastUpdateDate: at,
        subscriptionInfo: const SubscriptionInfo(expire: 1),
      ),
    );
    endIt(now);
    _mostInFlight = 0;
    final round = controller.refreshDue();
    for (var i = 0; i < 200 && _inFlight == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    unawaited(controller.refreshDue(renewed: {renewed.id}));
    await round;
    for (var i = 0; i < 200 && profileFinished(current()); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(profileFinished(current()), isFalse);
    expect(_mostInFlight, 1);

    final marker = DateTime.now().subtract(const Duration(seconds: 1));
    endIt(marker);
    await controller.refreshDue(renewed: {renewed.id});
    expect(current().lastUpdateDate, marker);
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

  test('on the TV, which never pastes, a pasted link the panel stops '
      'knowing is not marked revoked', () async {
    final (:container, :core, :proxies, :setup) = _home([
      shikooTvProvider.overrideWithValue(true),
    ]);
    final port = Uri.parse(await _panel(container, core)).port;
    final controller = container.read(shikooControllerProvider);
    await controller.pasteService(
      'http://10.0.2.2:$port/file/user111/a',
      debug: true,
    );
    ShikooService pasted() => container
        .read(shikooStateProvider)
        .listed
        .firstWhere((s) => s.name == 'user111');

    _gone.add('/file/user111/a');
    await controller.refreshOther(pasted().id);
    expect(pasted().revoked, isFalse);
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
    await pumpEventQueue();
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

  test('the card order stays on this device: the one in use keeps its place, '
      'a new service comes last, a gone one is skipped, and a restart reads '
      'it back', () async {
    final (:container, :core, :proxies, :setup) = _home();
    container.read(shikooControllerProvider);
    final first = container.read(currentProfileIdProvider)!;
    final [second, third, fourth] = [
      for (final name in ['b', 'c', 'd'])
        Profile.normal(url: 'https://panel.invalid/$name'),
    ];
    final profiles = container.read(profilesProvider.notifier)
      ..put(second)
      ..put(third);
    await pumpEventQueue();
    List<int> cards() => [
      for (final s in container.read(shikooStateProvider).listed) s.id,
    ];
    expect(container.read(serviceOrderProvider), [first, second.id, third.id]);

    await container.read(savedOrderProvider.notifier).save([
      third.id,
      first,
      second.id,
    ]);
    expect(container.read(serviceOrderProvider), [third.id, first, second.id]);
    expect(cards(), [third.id, first, second.id]);
    expect(container.read(shikooStateProvider).service!.id, first);

    profiles.put(fourth);
    await profiles.del(second.id);
    expect(container.read(serviceOrderProvider), [third.id, first, fourth.id]);

    final stored = (await SharedPreferences.getInstance()).getStringList(
      shikooOrderKey,
    );
    final kept = container.read(profilesProvider);
    final again = _home().container;
    kept.forEach(again.read(profilesProvider.notifier).put);
    SharedPreferences.setMockInitialValues({shikooOrderKey: stored!});
    again.read(shikooControllerProvider);
    await pumpEventQueue();
    expect(again.read(serviceOrderProvider), [
      third.id,
      first,
      again.read(currentProfileIdProvider),
      fourth.id,
    ], reason: 'the saved ids first, the others as they come');
  });

  test('a used-up service that is renewed comes back at the end of the '
      'order', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    final controller = container.read(shikooControllerProvider);
    final first = container.read(currentProfileIdProvider)!;
    await controller.addService('$panel/file/user111/a', null, false);
    await controller.addService('$panel/file/user222/a', null, false);
    final [one, two] = _pasted(container);
    container
        .read(profilesProvider.notifier)
        .put(
          one.copyWith(
            subscriptionInfo: const SubscriptionInfo(download: 2, total: 1),
          ),
        );
    expect(
      profileFinished(container.read(profilesProvider).getProfile(one.id)!),
      isTrue,
    );
    await container.read(savedOrderProvider.notifier).save([
      one.id,
      first,
      two.id,
    ]);

    await controller.refreshOther(two.id);
    expect(container.read(serviceOrderProvider), [one.id, first, two.id]);
    await controller.refreshOther(one.id);
    expect(container.read(serviceOrderProvider), [first, two.id, one.id]);
  });

  test(
    "removing every service clears the order: it was the account's",
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final controller = container.read(shikooControllerProvider);
      await container.read(savedOrderProvider.notifier).save([3, 2, 1]);
      await controller.forgetServices();
      expect(container.read(savedOrderProvider), isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getStringList(shikooOrderKey),
        isEmpty,
      );
    },
  );

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
    await controller.pingAll();
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

  test('a connect still searching goes on with its own service when another '
      'card opens', () async {
    final (:container, :core, :proxies, :setup) = _home();
    var hold = Completer<void>()..complete();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      await hold.future;
      return Delay(name: name, url: '', value: 50);
    });
    final controller = container.read(shikooControllerProvider);
    final first = container.read(currentProfileIdProvider)!;
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    controller.selectService(second.id);
    await pumpEventQueue();
    await controller.selectServer('هلند ۱');
    controller.selectService(first);
    await pumpEventQueue();

    hold = Completer<void>();
    unawaited(controller.connect());
    await pumpEventQueue();
    controller.openService(second.id);
    await pumpEventQueue();
    hold.complete();
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(setup.runs, [true], reason: 'not stuck on connecting');
    expect((state.service!.id, state.open), (first, second.id));
    expect(
      state.selected,
      isIn(['آلمان ۱', 'هلند ۱']),
      reason: 'its first answer',
    );
    await controller.disconnect();
  });

  test('a search the tunnel started after an update ends when another '
      'service with its own server becomes the one in use', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    container
        .read(profilesProvider.notifier)
        .put(
          container
              .read(profilesProvider)
              .single
              .copyWith(url: '$panel/none/a'),
        );
    var hold = Completer<void>()..complete();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      await hold.future;
      return Delay(name: name, url: '', value: 50);
    });
    final controller = container.read(shikooControllerProvider);
    final first = container.read(currentProfileIdProvider)!;
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    controller.selectService(second.id);
    await pumpEventQueue();
    await controller.selectServer('هلند ۱');
    controller.selectService(first);
    await pumpEventQueue();
    await controller.selectServer('آلمان ۱');
    container.read(runTimeProvider.notifier).value = 1;
    setup.tunnel = DateTime(2026);
    await pumpEventQueue();

    hold = Completer<void>();
    setup.onApply = () => container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: _version, type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
        ],
      ),
    ];
    await controller.refreshService();
    await pumpEventQueue();
    expect(container.read(shikooStateProvider).waiting, isTrue);
    controller.selectService(second.id);
    await pumpEventQueue();
    hold.complete();
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.waiting, isFalse);
    expect(state.connection, ShikooConnection.on);
    expect(state.selected, 'هلند ۱');
  });

  test('a check of the selected server that answers after a switch writes '
      "nothing on the new service's server of the same name, and starts no "
      'round there', () async {
    final (:container, :core, :proxies, :setup) = _home();
    var record = false;
    final gate = Completer<void>();
    final after = <String>[];
    var calls = 0;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (!record) {
        return Delay(name: name, url: '', value: name == 'هلند ۱' ? 40 : 90);
      }
      if (++calls == 1) {
        await gate.future;
        return Delay(name: name, url: '', value: -1);
      }
      if (calls > 2) after.add(name);
      return Delay(name: name, url: '', value: 777);
    });
    final controller = container.read(shikooControllerProvider);
    final first = container.read(currentProfileIdProvider)!;
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    controller.selectService(second.id);
    await pumpEventQueue();
    await controller.pingAll();
    expect(container.read(shikooStateProvider).selected, 'هلند ۱');
    controller.selectService(first);
    await pumpEventQueue();
    await controller.selectServer('هلند ۱');
    setup.tunnel = DateTime(2026);
    record = true;
    unawaited(controller.connect());
    await pumpEventQueue();
    controller.selectService(second.id);
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.selected, 'هلند ۱');
    expect(state.selectedServer?.ping, isNot(-1), reason: 'not the first one');
    expect(after, isEmpty, reason: 'no round the customer did not ask for');
    await controller.disconnect();
  });

  test('an update that changes the list during a ping keeps the answers of '
      'the servers still in it', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final panel = await _panel(container, core);
    container
        .read(profilesProvider.notifier)
        .put(
          container
              .read(profilesProvider)
              .single
              .copyWith(url: '$panel/none/a'),
        );
    final gate = Completer<void>();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      await gate.future;
      return Delay(name: name, url: '', value: 50);
    });
    final controller = container.read(shikooControllerProvider);
    final round = controller.pingAll();
    await pumpEventQueue();
    setup.onApply = () => container.read(groupsProvider.notifier).value = [
      const Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          Proxy(name: _version, type: 'Vless'),
          Proxy(name: 'آلمان ۱', type: 'Vless'),
          Proxy(name: 'هلند ۱', type: 'Vless'),
          Proxy(name: 'ترکیه ۱', type: 'Vless'),
        ],
      ),
    ];
    await controller.refreshService();
    gate.complete();
    await round;
    await pumpEventQueue();
    final state = container.read(shikooStateProvider);
    expect(state.pick, isNot(ShikooPick.none), reason: 'both answered');
    expect(
      {for (final s in state.servers) s.name: s.ping},
      {'آلمان ۱': 50, 'هلند ۱': 50, 'ترکیه ۱': null},
    );
    expect(state.selected, 'آلمان ۱');
  });

  test("another service stops the old round's servers still queued", () async {
    final (:container, :core, :proxies, :setup) = _home();
    container.read(groupsProvider.notifier).value = [
      Group(
        type: GroupType.Selector,
        name: 'PROXY',
        hidden: false,
        all: [
          for (var i = 1; i <= 6; i++) Proxy(name: 'سرور $i', type: 'Vless'),
        ],
      ),
    ];
    final gate = Completer<void>();
    var calls = 0;
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      calls++;
      await gate.future;
      return Delay(
        name: call.positionalArguments[1] as String,
        url: '',
        value: 50,
      );
    });
    final controller = container.read(shikooControllerProvider);
    final round = controller.pingAll();
    await pumpEventQueue();
    expect(calls, 4);
    final second = Profile.normal(url: 'https://panel.invalid/second');
    container.read(profilesProvider.notifier).put(second);
    controller.selectService(second.id);
    await pumpEventQueue();
    gate.complete();
    await round;
    await pumpEventQueue();
    expect(calls, 4, reason: 'only those already under way');
  });

  test('a card opened while off whose service has not come yet leaves no ping '
      'behind for the service chosen next', () async {
    final (:container, :core, :proxies, :setup) = _home();
    final probes = <String>[];
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      probes.add(name);
      return Delay(name: name, url: '', value: 50);
    });
    final controller = container.read(shikooControllerProvider);
    await pumpEventQueue();
    final second = Profile.normal(url: 'https://panel.invalid/second');
    final third = Profile.normal(url: 'https://panel.invalid/third');
    container.read(profilesProvider.notifier)
      ..put(second)
      ..put(third);
    controller
      ..openService(second.id)
      ..selectService(third.id);
    await pumpEventQueue();
    expect(container.read(currentProfileIdProvider), third.id);
    expect(probes, isEmpty);
  });

  group('another card opened', () {
    const firstNames = [_version, 'آلمان ۱', 'هلند ۱'];
    const secondNames = ['هلند ۱', 'ترکیه ۱', 'WG ۱'];
    String typeOf(String name) => name.startsWith('WG') ? 'wireguard' : 'vless';
    Map<String, dynamic> config(List<String> names, String server) => {
      'proxies': [
        for (final name in names)
          {'name': name, 'type': typeOf(name), 'server': server, 'port': 443},
      ],
      'proxy-groups': [
        {'name': 'PROXY', 'type': 'select', 'proxies': names},
      ],
    };
    Group group(List<String> names) => Group(
      type: GroupType.Selector,
      name: 'PROXY',
      hidden: false,
      all: [
        for (final name in names)
          Proxy(
            name: name,
            type: typeOf(name) == 'wireguard' ? 'WireGuard' : 'Vless',
          ),
      ],
    );
    List<(String, int?)> pingsOf(List<ShikooServer> servers) => [
      for (final server in servers) (server.name, server.ping),
    ];

    setUpAll(() => registerFallbackValue(<String, dynamic>{}));

    Completer<void>? coreGate;
    Completer<void>? fileGate;
    Completer<void>? applyGate;

    /// Two services sharing «هلند ۱»; the core holds only the one in use, as FlClash's does.
    /// A test adds a third with [lists], [pings] and a profile.
    Future<
      ({
        ProviderContainer container,
        _Core core,
        _Proxies proxies,
        _Setup setup,
        ShikooController controller,
        int first,
        int second,
        Map<int, List<String>> lists,
        Map<int, Map<String, int>> pings,
        List<String> fromFile,
      })
    >
    twoServices({bool connected = true}) async {
      coreGate = null;
      fileGate = null;
      applyGate = null;
      final lists = <int, List<String>>{};
      final pings = <int, Map<String, int>>{};
      final fromFile = <String>[];
      final second = Profile.normal(url: 'https://panel.invalid/second');
      final (:container, :core, :proxies, :setup) = _home([
        serviceAppliedProvider.overrideWith(
          (ref) => () async {
            await applyGate?.future;
            ref.read(groupsProvider.notifier).value = [
              group(lists[ref.read(currentProfileIdProvider)]!),
            ];
          },
        ),
      ]);
      final first = container.read(currentProfileIdProvider)!;
      container.read(profilesProvider.notifier).put(second);
      lists
        ..[first] = firstNames
        ..[second.id] = secondNames;
      pings
        ..[first] = {'آلمان ۱': 50, 'هلند ۱': 40}
        ..[second.id] = {'هلند ۱': 300, 'ترکیه ۱': 80};
      when(() => core.getConfig(any())).thenAnswer((call) async {
        final path = '${call.positionalArguments.first}';
        final id = lists.keys.firstWhere((id) => path.endsWith('$id.yaml'));
        return config(lists[id]!, '$id.invalid');
      });
      when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
        final name = call.positionalArguments[1] as String;
        final inUse = container.read(currentProfileIdProvider);
        await coreGate?.future;
        return Delay(name: name, url: '', value: pings[inUse]?[name] ?? -1);
      });
      when(() => core.testProxyDelay(any(), any())).thenAnswer((call) async {
        final proxy = call.positionalArguments[1] as Map<String, dynamic>;
        final name = '${proxy['name']}';
        final service = int.parse('${proxy['server']}'.split('.').first);
        fromFile.add(name);
        await fileGate?.future;
        return Delay(name: name, url: '', value: pings[service]?[name] ?? -1);
      });
      final controller = container.read(shikooControllerProvider);
      await controller.pingAll();
      if (connected) {
        container.read(runTimeProvider.notifier).value = 1;
        setup.tunnel = DateTime(2026);
      }
      await pumpEventQueue();
      return (
        container: container,
        core: core,
        proxies: proxies,
        setup: setup,
        controller: controller,
        first: first,
        second: second.id,
        lists: lists,
        pings: pings,
        fromFile: fromFile,
      );
    }

    test('connected, it is measured from its own file and sorted on its own; '
        'the tunnel stays where it is', () async {
      final t = await twoServices();
      final moves = <int?>[];
      t.container.listen(currentProfileIdProvider, (_, id) => moves.add(id));
      fileGate = Completer<void>();
      t.controller.openService(t.second);
      await pumpEventQueue();
      var state = t.container.read(shikooStateProvider);
      expect(state.open, t.second);
      expect(state.opened?.pinging, (done: 0, total: 3));
      expect(state.opened!.servers.every((s) => s.testing), isTrue);

      fileGate!.complete();
      await pumpEventQueue();
      state = t.container.read(shikooStateProvider);
      expect(moves, isEmpty, reason: 'the service in use stays');
      expect(t.proxies.picked, ['هلند ۱'], reason: 'no server chosen anew');
      expect(t.setup.runs, isEmpty);
      expect(state.connection, ShikooConnection.on);
      expect(state.service!.id, t.first);
      expect(pingsOf(state.opened!.servers), [
        ('ترکیه ۱', 80),
        ('هلند ۱', 300),
        ('WG ۱', -1),
      ]);
      expect((state.opened!.sorted, state.opened!.pinging), (true, null));
      expect(
        t.fromFile,
        unorderedEquals(['هلند ۱', 'ترکیه ۱', 'WG ۱', 'WG ۱']),
      );
      verifyNever(() => t.core.asyncTestDelay(any(), 'ترکیه ۱'));
      expect(pingsOf(state.servers), [
        ('هلند ۱', 40),
        ('آلمان ۱', 50),
      ], reason: 'the name both have keeps this service its own number');
    });

    test('a server tapped there takes the tunnel with that service, loaded '
        'with it chosen; each service keeps its own numbers', () async {
      final t = await twoServices();
      t.controller.openService(t.second);
      await pumpEventQueue();
      final handed = <Map<String, String>>[];
      t.container.listen(currentProfileIdProvider, (_, id) {
        handed.add({
          ...?t.container.read(profilesProvider).getProfile(id!)?.selectedMap,
        });
      });
      await t.controller.selectServer('ترکیه ۱', service: t.second);
      await pumpEventQueue();
      var state = t.container.read(shikooStateProvider);
      expect(handed, [
        {'PROXY': 'ترکیه ۱'},
      ], reason: 'what setup hands the core: no other server first');
      expect(state.service!.id, t.second);
      expect(state.selected, 'ترکیه ۱');
      expect(state.switching?.stage, ShikooSwitchStage.done);
      expect(state.opened, isNull, reason: 'it is the service in use now');
      expect(t.setup.runs, isEmpty, reason: 'the tunnel stays up');
      expect(pingsOf(state.servers), [
        ('ترکیه ۱', 80),
        ('هلند ۱', 300),
        ('WG ۱', -1),
      ], reason: 'its numbers and order came along');

      t.controller.selectService(t.first);
      t.container.read(groupsProvider.notifier).value = [group(firstNames)];
      await pumpEventQueue();
      state = t.container.read(shikooStateProvider);
      expect(pingsOf(state.servers), [
        ('هلند ۱', 40),
        ('آلمان ۱', 50),
      ], reason: 'and the first one its own, measured before the switch');
    });

    test('off, it is the service connect uses and the core pings it', () async {
      final t = await twoServices(connected: false);
      t.controller.openService(t.second);
      await pumpEventQueue();
      t.container.read(groupsProvider.notifier).value = [group(secondNames)];
      await pumpEventQueue();
      final state = t.container.read(shikooStateProvider);
      expect(state.service!.id, t.second);
      expect((state.open, state.opened), (t.second, null));
      expect(state.sorted, isTrue);
      expect(pingsOf(state.servers), [
        ('ترکیه ۱', 80),
        ('هلند ۱', 300),
        ('WG ۱', -1),
      ]);
      expect(t.fromFile, isEmpty, reason: 'the core holds it');
    });

    /// A pasted service's file holds «سوئد ۱»; its id is known only once it is saved.
    Future<String> pasteable(
      ProviderContainer container,
      _Core core,
      Map<int, List<String>> lists,
    ) async {
      final port = Uri.parse(await _panel(container, core)).port;
      when(() => core.getConfig(any())).thenAnswer((call) async {
        final path = '${call.positionalArguments.first}';
        final id = lists.keys.firstWhere(
          (id) => path.endsWith('$id.yaml'),
          orElse: () => 0,
        );
        return config(lists[id] ?? const ['سوئد ۱'], '$id.invalid');
      });
      return 'http://10.0.2.2:$port';
    }

    test('a paste while connected opens its card last and measures it there; '
        'the tunnel stays, and the same account pasted again is no second '
        'card', () async {
      final t = await twoServices();
      final panel = await pasteable(t.container, t.core, t.lists);
      final moves = <int?>[];
      t.container.listen(currentProfileIdProvider, (_, id) => moves.add(id));
      final pasted = await t.controller.pasteService(
        '$panel/file/user333/a',
        debug: true,
      );
      await pumpEventQueue();
      var state = t.container.read(shikooStateProvider);
      expect((pasted.error, pasted.added), (null, true));
      expect(moves, isEmpty, reason: 'the service in use stays');
      expect(t.setup.runs, isEmpty);
      expect(
        (state.connection, state.service!.id),
        (ShikooConnection.on, t.first),
      );
      expect(state.others.last.id, pasted.id);
      expect((state.open, state.opened?.id), (pasted.id, pasted.id));
      expect(t.fromFile, contains('سوئد ۱'), reason: 'measured from its file');

      final again = await t.controller.pasteService(
        '$panel/file/user333/b',
        debug: true,
      );
      await pumpEventQueue();
      state = t.container.read(shikooStateProvider);
      expect((again.id, again.added), (pasted.id, false));
      expect(t.container.read(profilesProvider), hasLength(3));
      expect(state.open, pasted.id);
      expect(moves, isEmpty);
    });

    test('a paste while off makes the new service the one connect '
        'uses', () async {
      final t = await twoServices(connected: false);
      final panel = await pasteable(t.container, t.core, t.lists);
      final pasted = await t.controller.pasteService(
        '$panel/file/user333/a',
        debug: true,
      );
      await pumpEventQueue();
      final state = t.container.read(shikooStateProvider);
      expect(pasted.added, isTrue);
      expect(state.service!.id, pasted.id);
      expect(state.open, pasted.id);
      expect(t.setup.runs, isEmpty, reason: 'nothing connects by itself');
    });

    test('a late answer lands on no same-named server of the other '
        'service', () async {
      final t = await twoServices();
      coreGate = Completer<void>();
      final round = t.controller.pingAll();
      await pumpEventQueue();
      t.controller.openService(t.second);
      await pumpEventQueue();
      coreGate!.complete();
      await round;
      await pumpEventQueue();
      var state = t.container.read(shikooStateProvider);
      expect(
        state.opened!.servers.firstWhere((s) => s.name == 'هلند ۱').ping,
        300,
      );
      expect(state.servers.firstWhere((s) => s.name == 'هلند ۱').ping, 40);

      t.pings[t.second]!['هلند ۱'] = 999;
      fileGate = Completer<void>();
      t.controller.openService(t.second);
      await pumpEventQueue();
      t.controller.openService(t.first);
      await pumpEventQueue();
      fileGate!.complete();
      await pumpEventQueue();
      state = t.container.read(shikooStateProvider);
      expect(state.servers.firstWhere((s) => s.name == 'هلند ۱').ping, 40);
      t.controller.selectService(t.second);
      t.container.read(groupsProvider.notifier).value = [group(secondNames)];
      coreGate = Completer<void>();
      await pumpEventQueue();
      state = t.container.read(shikooStateProvider);
      expect(
        state.servers.firstWhere((s) => s.name == 'هلند ۱').ping,
        300,
        reason: 'a list folded before its answers came reads none of them',
      );
      coreGate!.complete();
      await pumpEventQueue();
      await t.controller.disconnect();
    });

    test('a tapped server there that does not answer gets no traffic; a '
        'WireGuard one is tried on real traffic, and the first service comes '
        'back if none passes', () async {
      final t = await twoServices();
      final moves = <int?>[];
      t.container.listen(currentProfileIdProvider, (_, id) => moves.add(id));
      t.controller.openService(t.second);
      await pumpEventQueue();
      t.pings[t.second]!['هلند ۱'] = -1;
      fileGate = Completer<void>();
      final tap = t.controller.selectServer('هلند ۱', service: t.second);
      await pumpEventQueue();
      var state = t.container.read(shikooStateProvider);
      bool spins(List<ShikooServer> servers) =>
          servers.firstWhere((s) => s.name == 'هلند ۱').testing;
      expect(state.switching?.stage, ShikooSwitchStage.moving);
      expect(spins(state.opened!.servers), isTrue);
      expect(spins(state.servers), isFalse, reason: 'the same name in use');
      fileGate!.complete();
      await tap;
      state = t.container.read(shikooStateProvider);
      expect(moves, isEmpty);
      expect(state.switching, (
        to: 'هلند ۱',
        from: 'هلند ۱',
        stage: ShikooSwitchStage.failed,
      ));
      expect(
        t.container.read(profilesProvider).getProfile(t.second)!.selectedMap,
        isEmpty,
      );

      t.setup.traffic = false;
      await t.controller.selectServer('WG ۱', service: t.second);
      t.container.read(groupsProvider.notifier).value = [group(firstNames)];
      await pumpEventQueue();
      state = t.container.read(shikooStateProvider);
      expect(moves, [t.second, t.first], reason: 'tried there, then back');
      expect((state.service!.id, state.selected), (t.first, 'هلند ۱'));
      expect(state.switching?.stage, ShikooSwitchStage.failed);

      t.controller.openService(t.second);
      await pumpEventQueue();
      t.setup.traffic = true;
      await t.controller.selectServer('WG ۱', service: t.second);
      state = t.container.read(shikooStateProvider);
      expect((state.service!.id, state.selected), (t.second, 'WG ۱'));
      expect(state.switching?.stage, ShikooSwitchStage.done);
      await pumpEventQueue();
    });

    test('once a tap there lands, the rest of that card\'s round probes '
        'nothing from its file: a WireGuard key would meet itself', () async {
      final t = await twoServices();
      final slow = Completer<void>();
      final landed = <String>[];
      when(() => t.core.testProxyDelay(any(), any())).thenAnswer((call) async {
        final proxy = call.positionalArguments[1] as Map<String, dynamic>;
        final name = '${proxy['name']}';
        if (t.container.read(currentProfileIdProvider) == t.second) {
          landed.add(name);
        }
        if (name == 'ترکیه ۱') await slow.future;
        final service = int.parse('${proxy['server']}'.split('.').first);
        return Delay(name: name, url: '', value: t.pings[service]?[name] ?? -1);
      });
      t.controller.openService(t.second);
      await pumpEventQueue();
      await t.controller.selectServer('هلند ۱', service: t.second);
      t.container.read(groupsProvider.notifier).value = [group(secondNames)];
      await pumpEventQueue();
      expect(t.container.read(currentProfileIdProvider), t.second);
      slow.complete();
      await pumpEventQueue();
      expect(landed, isEmpty);
    });

    test('a WireGuard server there that carries no traffic gives the tunnel '
        "back and leaves that service's own choice as it was", () async {
      final t = await twoServices();
      Profile second() =>
          t.container.read(profilesProvider).getProfile(t.second)!;
      t.container
          .read(profilesProvider.notifier)
          .put(second().copyWith(selectedMap: {'PROXY': 'ترکیه ۱'}));
      t.controller.openService(t.second);
      await pumpEventQueue();
      t.setup.traffic = false;
      await t.controller.selectServer('WG ۱', service: t.second);
      t.container.read(groupsProvider.notifier).value = [group(firstNames)];
      await pumpEventQueue();
      expect(t.container.read(currentProfileIdProvider), t.first);
      expect(second().selectedMap, {
        'PROXY': 'ترکیه ۱',
      }, reason: 'not the WireGuard server the next connect would land on');
    });

    test('a WireGuard check there that fails after a newer tap gives nothing '
        'back: the last tap decides', () async {
      final t = await twoServices();
      final third = Profile.normal(url: 'https://panel.invalid/third');
      t.lists[third.id] = ['سوئد ۱'];
      t.pings[third.id] = {'سوئد ۱': 70};
      t.container.read(profilesProvider.notifier).put(third);
      final moves = <int?>[];
      t.container.listen(currentProfileIdProvider, (_, id) => moves.add(id));
      t.controller.openService(t.second);
      await pumpEventQueue();
      t.setup
        ..traffic = false
        ..trafficGate = Completer<void>();
      final wireGuard = t.controller.selectServer('WG ۱', service: t.second);
      await pumpEventQueue();
      expect(moves, [t.second]);

      t.controller.openService(third.id);
      await pumpEventQueue();
      fileGate = Completer<void>();
      final sweden = t.controller.selectServer('سوئد ۱', service: third.id);
      await pumpEventQueue();
      t.setup.trafficGate!.complete();
      await wireGuard;
      await pumpEventQueue();
      expect(moves, [t.second], reason: 'the newer tap is still measured');

      fileGate!.complete();
      await sweden;
      await pumpEventQueue();
      expect(moves, [t.second, third.id]);
      expect(t.container.read(shikooStateProvider).selected, 'سوئد ۱');
    });

    test('an ended service only opens: off it never becomes the one connect '
        'uses, on it is not measured, and nothing is pinged', () async {
      for (final connected in [false, true]) {
        final t = await twoServices(connected: connected);
        final second = t.container.read(profilesProvider).getProfile(t.second)!;
        t.container
            .read(profilesProvider.notifier)
            .put(
              second.copyWith(
                subscriptionInfo: const SubscriptionInfo(expire: 1),
              ),
            );
        await pumpEventQueue();
        final moves = <int?>[];
        t.container.listen(currentProfileIdProvider, (_, id) => moves.add(id));
        clearInteractions(t.core);
        t.controller.openService(t.second);
        await pumpEventQueue();
        final state = t.container.read(shikooStateProvider);
        final where = connected ? 'connected' : 'off';
        expect((state.open, state.service!.id), (t.second, t.first));
        expect(moves, isEmpty, reason: where);
        expect(t.fromFile, isEmpty, reason: where);
        verifyNever(() => t.core.asyncTestDelay(any(), any()));
      }
    });

    test(
      'a tap there that moves the tunnel marks that card until it folds, the '
      'app leaves or the tunnel stops; while the core loads the service it '
      'keeps the list it showed',
      () async {
        final t = await twoServices();
        Future<void> land(int id, String name) async {
          t.controller.openService(id);
          await pumpEventQueue();
          await t.controller.selectServer(name, service: id);
          await pumpEventQueue();
        }

        t.controller.openService(t.second);
        await pumpEventQueue();
        applyGate = Completer<void>();
        final tap = t.controller.selectServer('ترکیه ۱', service: t.second);
        await pumpEventQueue();
        var state = t.container.read(shikooStateProvider);
        expect(state.service!.id, t.second, reason: 'moved, the core not yet');
        expect(state.landed, (id: t.second, arrived: false));
        expect(state.opened?.id, t.second);
        expect(
          [for (final s in state.opened!.servers) s.name],
          ['ترکیه ۱', 'هلند ۱', 'WG ۱'],
          reason: "its own list, not the first service's still in the core",
        );
        applyGate!.complete();
        await tap;
        state = t.container.read(shikooStateProvider);
        expect(state.landed, (id: t.second, arrived: true));
        expect(state.opened, isNull);

        t.controller.onBackground();
        expect(t.container.read(shikooStateProvider).landed, isNull);
        await land(t.first, 'آلمان ۱');
        expect(t.container.read(shikooStateProvider).landed?.id, t.first);
        t.controller.openService(null);
        expect(t.container.read(shikooStateProvider).landed, isNull);
        await land(t.second, 'ترکیه ۱');
        expect(t.container.read(shikooStateProvider).landed?.id, t.second);
        await t.controller.disconnect();
        expect(t.container.read(shikooStateProvider).landed, isNull);
      },
    );

    test('a WireGuard try there that gives the tunnel back leaves the card '
        'open with its list and unmarked', () async {
      final t = await twoServices();
      t.controller.openService(t.second);
      await pumpEventQueue();
      t.setup.traffic = false;
      await t.controller.selectServer('WG ۱', service: t.second);
      t.container.read(groupsProvider.notifier).value = [group(firstNames)];
      await pumpEventQueue();
      final state = t.container.read(shikooStateProvider);
      expect(state.service!.id, t.first);
      expect((state.open, state.landed), (t.second, null));
      expect(pingsOf(state.opened!.servers), [
        ('ترکیه ۱', 80),
        ('هلند ۱', 300),
        ('WG ۱', -1),
      ]);
    });
  });

  test(
    'the cards keep their order: the one in use stays where it is',
    () async {
      final (:container, :core, :proxies, :setup) = _home();
      final first = container.read(currentProfileIdProvider)!;
      final second = Profile.normal(url: 'https://panel.invalid/second');
      final third = Profile.normal(url: 'https://panel.invalid/third');
      container.read(profilesProvider.notifier)
        ..put(second)
        ..put(third);
      container.read(shikooControllerProvider).selectService(second.id);
      await pumpEventQueue();
      final state = container.read(shikooStateProvider);
      expect(state.service!.id, second.id);
      expect(
        [for (final s in state.listed) s.id],
        [first, second.id, third.id],
      );
    },
  );

  group('on Windows', () {
    var calls = <String>[];
    var portFree = true;
    var admin = ShikooAdmin.ready;
    Completer<ShikooAdmin>? prompt;
    Completer<void>? restarting;

    ({ProviderContainer container, _Setup setup}) windows({
      bool desktop = true,
      bool restartFails = false,
    }) {
      calls = [];
      portFree = true;
      admin = ShikooAdmin.ready;
      prompt = null;
      restarting = null;
      final (:container, :core, :proxies, :setup) = _home([
        shikooDesktopProvider.overrideWithValue(desktop),
        localPortFreeProvider.overrideWithValue((port) async {
          calls.add('port $port');
          return portFree;
        }),
        tunAuthorizeProvider.overrideWithValue(() async {
          calls.add('admin');
          return prompt?.future ?? admin;
        }),
        coreActionProvider.overrideWith(
          () => _Restart(
            calls,
            fails: restartFails,
            hold: () => restarting?.future,
          ),
        ),
      ]);
      container
          .read(profilesActionProvider.notifier)
          .updateCurrentSelectedMap('PROXY', 'هلند ۱');
      return (container: container, setup: setup);
    }

    bool systemProxy(ProviderContainer c) =>
        c.read(networkSettingProvider).systemProxy;

    bool tun(ProviderContainer c) =>
        c.read(patchClashConfigProvider).tun.enable;

    Future<ShikooController> ready(
      ProviderContainer container,
      _Setup setup,
    ) async {
      final controller = container.read(shikooControllerProvider);
      await pumpEventQueue();
      setup.tunnel = DateTime.now();
      return controller;
    }

    Future<void> done(ShikooController controller) async {
      await controller.disconnect();
      await pumpEventQueue();
    }

    test("the proxy mode turns Windows' proxy on and TUN off, and stops "
        'before the proxy while another program holds the port', () async {
      final (:container, :setup) = windows();
      final controller = await ready(container, setup);
      await controller.setMode(ShikooMode.proxy);
      container
          .read(networkSettingProvider.notifier)
          .update((s) => s.copyWith(systemProxy: false));
      container
          .read(patchClashConfigProvider.notifier)
          .update((c) => c.copyWith.tun(enable: true));

      portFree = false;
      await controller.connect();
      var state = container.read(shikooStateProvider);
      expect(state.busyPort, 7890);
      expect(state.connection, ShikooConnection.error);
      expect(setup.runs, isEmpty);
      expect(systemProxy(container), isFalse);

      portFree = true;
      await controller.connect();
      state = container.read(shikooStateProvider);
      expect(state.busyPort, isNull);
      expect(state.connection, ShikooConnection.on);
      expect(setup.runs, [true]);
      expect((systemProxy(container), tun(container)), (true, false));
      expect(calls, ['port 7890', 'port 7890']);

      portFree = false;
      await controller.connect();
      state = container.read(shikooStateProvider);
      expect(
        (state.connection, state.busyPort),
        (ShikooConnection.on, null),
        reason: "connected, the port is the core's own",
      );
      expect(calls, ['port 7890', 'port 7890']);
      await done(controller);
    });

    test('the tunnel mode asks for the helper service until it is there, '
        "then turns TUN on and Windows' proxy off; a refused prompt starts "
        'nothing and says so', () async {
      final (:container, :setup) = windows();
      final controller = await ready(container, setup);
      await controller.setMode(ShikooMode.tunnel);
      expect(setup.runs, isEmpty, reason: 'off, a mode change starts nothing');

      admin = ShikooAdmin.refused;
      await controller.connect();
      final refused = container.read(shikooStateProvider);
      expect(refused.lastError, ShikooError.vpnRefused);
      expect(refused.connection, ShikooConnection.error);
      expect(setup.runs, isEmpty);
      expect(tun(container), isFalse);

      admin = ShikooAdmin.installed;
      await controller.connect();
      expect(
        container.read(shikooStateProvider).connection,
        ShikooConnection.on,
      );
      expect((systemProxy(container), tun(container)), (false, true));
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.authorized,
      );

      await controller.disconnect();
      await controller.connect();
      expect(calls, ['admin', 'admin', 'restart']);
      expect(setup.runs, [true, false, true]);
      await done(controller);
    });

    test('a prompt accepted while the service still does not come up says '
        'so, apart from a refused one', () async {
      final (:container, :setup) = windows();
      final controller = await ready(container, setup);
      admin = ShikooAdmin.failed;
      await controller.connect();
      final state = container.read(shikooStateProvider);
      expect(state.helperFailed, isTrue);
      expect(state.lastError, isNull);
      expect(state.connection, ShikooConnection.error);
      expect(setup.runs, isEmpty);

      admin = ShikooAdmin.ready;
      await controller.connect();
      expect(container.read(shikooStateProvider).helperFailed, isFalse);
      await done(controller);
    });

    test('a core restart that throws after the service install fails the '
        'start, never stays connecting', () async {
      final (:container, :setup) = windows(restartFails: true);
      final controller = await ready(container, setup);
      admin = ShikooAdmin.installed;
      await controller.connect();
      expect(calls, ['admin', 'restart']);
      expect(
        container.read(shikooStateProvider).connection,
        isNot(ShikooConnection.connecting),
      );
      await done(controller);
    });

    test('the newest intent wins over a pending admin prompt: a mode change '
        'keeps its own flags and restarts nothing', () async {
      final (:container, :setup) = windows();
      final controller = await ready(container, setup);
      prompt = Completer();
      unawaited(controller.connect());
      await pumpEventQueue();
      expect(calls, ['admin']);
      await controller.setMode(ShikooMode.proxy);
      expect((systemProxy(container), tun(container)), (true, false));

      prompt!.complete(ShikooAdmin.installed);
      await pumpEventQueue();
      expect(container.read(shikooModeProvider), ShikooMode.proxy);
      expect((systemProxy(container), tun(container)), (true, false));
      expect(calls, ['admin', 'port 7890']);
      expect(setup.runs, [false, true]);

      await controller.setMode(ShikooMode.tunnel);
      expect(calls, ['admin', 'port 7890', 'restart']);
      expect(tun(container), isTrue);
      await done(controller);
    });

    test(
      'a disconnect during the admin prompt starts and restarts nothing',
      () async {
        final (:container, :setup) = windows();
        final controller = await ready(container, setup);
        prompt = Completer();
        unawaited(controller.connect());
        await pumpEventQueue();
        await controller.disconnect();
        prompt!.complete(ShikooAdmin.installed);
        await pumpEventQueue();
        expect(calls, ['admin']);
        expect(setup.runs, [false]);
        expect(tun(container), isFalse);
        await done(controller);
      },
    );

    test('a disconnect during the core restart after the install sets no '
        'flags and starts nothing', () async {
      final (:container, :setup) = windows();
      final controller = await ready(container, setup);
      admin = ShikooAdmin.installed;
      restarting = Completer();
      unawaited(controller.connect());
      await pumpEventQueue();
      expect(calls, ['admin', 'restart']);
      await controller.disconnect();
      restarting!.complete();
      await pumpEventQueue();
      expect(setup.runs, [false]);
      expect(tun(container), isFalse);
      await done(controller);
    });

    test(
      'connect again during the admin prompt waits on that one prompt',
      () async {
        final (:container, :setup) = windows();
        final controller = await ready(container, setup);
        prompt = Completer();
        unawaited(controller.connect());
        await pumpEventQueue();
        await controller.disconnect();
        unawaited(controller.connect());
        await pumpEventQueue();
        expect(calls, ['admin']);

        prompt!.complete(ShikooAdmin.installed);
        await pumpEventQueue();
        expect(calls, ['admin', 'restart']);
        expect(setup.runs, [false, true]);
        await done(controller);
      },
    );

    test('the tunnel is the first mode; a change while connected connects '
        'again in the new one, which the next launch keeps', () async {
      final (:container, :setup) = windows();
      final controller = await ready(container, setup);
      await controller.connect();
      expect((systemProxy(container), tun(container)), (false, true));
      await controller.setMode(ShikooMode.proxy);
      expect(setup.runs, [true, false, true]);
      expect((systemProxy(container), tun(container)), (true, false));
      expect(calls, ['admin', 'port 7890']);

      final next = ProviderContainer();
      addTearDown(next.dispose);
      expect(next.read(shikooModeProvider), ShikooMode.tunnel);
      await next.read(shikooModeProvider.notifier).load();
      expect(next.read(shikooModeProvider), ShikooMode.proxy);
      await done(controller);
    });

    test("Android has no modes: its connect leaves FlClash's flags and "
        'checks no port', () async {
      final (:container, :setup) = windows(desktop: false);
      final controller = await ready(container, setup);
      container
          .read(networkSettingProvider.notifier)
          .update((s) => s.copyWith(systemProxy: false));
      await controller.setMode(ShikooMode.proxy);
      expect(container.read(shikooModeProvider), ShikooMode.tunnel);

      await controller.connect();
      expect(setup.runs, [true]);
      expect((systemProxy(container), tun(container)), (false, false));
      expect(calls, isEmpty);
      await done(controller);
    });
  });
}
