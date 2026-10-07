import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:yaml/yaml.dart';

/// Plain `test`s only: TestWidgetsFlutterBinding would answer every request itself with a 400.

/// A site answering every request with [status]; [asked] counts what reached it.
Future<({String url, List<String> asked})> _site(int status) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final asked = <String>[];
  server.listen((request) {
    asked.add('${request.method} ${request.uri.path}');
    request.response.statusCode = status;
    unawaited(request.response.close());
  });
  return (url: 'http://127.0.0.1:${server.port}', asked: asked);
}

/// Takes the connection and then [onSocket] decides: never answer, or hang up at once.
Future<String> _socket(void Function(Socket socket) onSocket) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final held = <Socket>[];
  addTearDown(() async {
    for (final socket in held) {
      socket.destroy();
    }
    await server.close();
  });
  server.listen((socket) {
    held.add(socket..listen((_) {}));
    onSocket(socket);
  });
  return 'http://127.0.0.1:${server.port}';
}

Future<String> _nobody() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return 'http://127.0.0.1:$port';
}

const _dns = 'http://nohost.invalid';
const _short = Duration(milliseconds: 400);

Probe _p(String result) => (result: result, ms: 1);

ProbeChecks _checks(String domestic, String international, String door) =>
    (domestic: _p(domestic), international: _p(international), door: _p(door));

const _answering = [ShikooServer(name: 'a', type: 'vless', ping: 90)];
const _silent = [
  ShikooServer(name: 'a', type: 'vless', ping: -1),
  ShikooServer(name: 'b', type: 'vless', ping: -1),
];

/// Every request through FlClash's local proxy, as the app's HttpClient is while connected.
class _ThroughProxy extends HttpOverrides {
  _ThroughProxy(this.port);

  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
}

void main() {
  group('each probe names what it met', () {
    test('any answer from the Iranian site, a 204 abroad, a 200 from the '
        'door', () async {
      final home = await _site(301);
      final abroad = await _site(204);
      final door = await _site(200);
      final checks = await runProbes(
        domestic: [home.url],
        international: '${abroad.url}/generate_204',
        doors: [door.url],
      );
      expect(checks.domestic.result, 'ok');
      expect(checks.international.result, 'ok');
      expect(checks.door.result, 'ok');
      expect(home.asked, ['HEAD /']);
      expect(abroad.asked, ['GET /generate_204']);
      expect(door.asked, ['GET /health']);
    });

    test('a page in place of the 204, and a door that is not well, by their '
        'codes', () async {
      final portal = await _site(302);
      final door = await _site(503);
      final checks = await runProbes(
        domestic: [portal.url],
        international: '${portal.url}/generate_204',
        doors: [door.url],
      );
      expect(checks.domestic.result, 'ok');
      expect(checks.international.result, 'http_302');
      expect(checks.door.result, 'http_503');
    });

    test('a name with no address is dns, a refused or dropped connection '
        'tcp, a failed handshake tls', () async {
      final dropped = await _socket((socket) => socket.destroy());
      final plain = await _site(200);
      final checks = await runProbes(
        domestic: [_dns],
        international: await _nobody(),
        doors: [plain.url.replaceFirst('http:', 'https:')],
      );
      expect(checks.domestic.result, 'dns');
      expect(checks.international.result, 'tcp');
      expect(checks.door.result, 'tls');
      expect(
        (await runProbes(
          domestic: [dropped],
          international: dropped,
          doors: [dropped],
        )).door.result,
        'tcp',
      );
    });

    test('one that never answers ends at the limit, and all three wait '
        'together', () async {
      final silent = await _socket((_) {});
      final watch = Stopwatch()..start();
      final checks = await runProbes(
        domestic: [silent],
        international: silent,
        doors: [silent],
        limit: _short,
      );
      expect(checks.international.result, 'timeout');
      expect(checks.door.result, 'timeout');
      expect(checks.door.ms, greaterThanOrEqualTo(_short.inMilliseconds));
      expect(watch.elapsed, lessThan(_short * 2));
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('the app waits five seconds at most for one', () {
      expect(probeLimit, lessThanOrEqualTo(const Duration(seconds: 5)));
    });

    test('the second Iranian site is asked only when the first is down, and '
        'the next door only when the first is', () async {
      final aparat = await _site(200);
      final digikala = await _site(200);
      final door = await _site(200);
      final backup = await _site(200);
      final dead = await _nobody();
      await runProbes(
        domestic: [aparat.url, digikala.url],
        international: aparat.url,
        doors: [door.url, backup.url],
      );
      expect(digikala.asked, isEmpty);
      expect(backup.asked, isEmpty);
      final checks = await runProbes(
        domestic: [dead, digikala.url],
        international: aparat.url,
        doors: [dead, backup.url],
      );
      expect(checks.domestic.result, 'ok');
      expect(checks.door.result, 'ok');
      expect(digikala.asked, ['HEAD /']);
      expect(backup.asked, ['GET /health']);
    });
  });

  test('the probes pass by the local proxy, which a connected app uses for '
      'every other request', () async {
    final proxy = await _site(502);
    final target = await _site(204);
    final saved = HttpOverrides.current;
    HttpOverrides.global = _ThroughProxy(Uri.parse(proxy.url).port);
    addTearDown(() => HttpOverrides.global = saved);
    final checks = await runProbes(
      domestic: [target.url],
      international: '${target.url}/generate_204',
      doors: [target.url],
    );
    expect(proxy.asked, isEmpty);
    expect(checks.international.result, 'ok');
    expect(target.asked, hasLength(3));
  });

  test('with the VPN on, the core sends the three sites and the door DIRECT, '
      'ahead of the subscription', () async {
    final before = database;
    database = Database(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      database = before;
    });
    await database.profilesDao.putAll([
      const Profile(id: 1, autoUpdateDuration: Duration.zero).toCompanion(),
    ]);
    await keepApiDirect();
    final config = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 1,
        rawConfig: {
          'proxies': [],
          'rules': ['MATCH,PROXY'],
        },
        realPatchConfig: const PatchClashConfig(),
        overrideDns: false,
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: await database.rulesDao.queryAddedRules(1).get(),
        defaultUA: 'FlClash-Test',
      ),
    );
    final rules = (loadYaml(config.yaml) as YamlMap)['rules'] as List;
    expect(
      rules.take(4),
      unorderedEquals([
        'DOMAIN,app.chopon.uk,DIRECT',
        'DOMAIN,www.aparat.com,DIRECT',
        'DOMAIN,www.digikala.com,DIRECT',
        'DOMAIN,connectivitycheck.gstatic.com,DIRECT',
      ]),
    );
    expect(rules.skip(4), ['MATCH,PROXY']);
  });

  group('the card says one sentence, the door first', () {
    test('door not reached: nothing answered means no internet at all', () {
      for (final (domestic, international, reading) in [
        ('dns', 'dns', ProbeReading.offline),
        ('timeout', 'tcp', ProbeReading.offline),
        ('ok', 'timeout', ProbeReading.noDoor),
        ('dns', 'ok', ProbeReading.noDoor),
        ('ok', 'http_302', ProbeReading.noDoor),
      ]) {
        for (final door in ['timeout', 'tls', 'http_502']) {
          expect(
            readProbes(_checks(domestic, international, door), _answering),
            reading,
            reason: '$domestic $international $door',
          );
        }
      }
    });

    test('door reached: abroad cut, then every server silent, else all '
        'well; the Iranian site changes none', () {
      for (final domestic in ['ok', 'dns']) {
        expect(
          readProbes(_checks(domestic, 'timeout', 'ok'), _silent),
          ProbeReading.noAbroad,
        );
        expect(
          readProbes(_checks(domestic, 'http_302', 'ok'), _answering),
          ProbeReading.noAbroad,
        );
        expect(
          readProbes(_checks(domestic, 'ok', 'ok'), _silent),
          ProbeReading.noServer,
        );
        expect(
          readProbes(_checks(domestic, 'ok', 'ok'), [
            ..._silent,
            ..._answering,
          ]),
          ProbeReading.ok,
        );
        expect(
          readProbes(_checks(domestic, 'ok', 'ok'), const []),
          ProbeReading.ok,
        );
        expect(
          readProbes(_checks(domestic, 'ok', 'ok'), const [
            ShikooServer(name: 'a', type: 'vless'),
          ]),
          ProbeReading.ok,
        );
      }
      expect(readProbes(null, _silent), ProbeReading.checking);
    });
  });

  group('the card comes after a failed connect and goes with the next', () {
    late StreamController<ShikooState> states;
    late ProviderContainer container;
    late List<Completer<ProbeChecks>> runs;

    ShikooState state(ShikooConnection connection, [ShikooError? error]) =>
        ShikooState(
          connection: connection,
          connectedFor: Duration.zero,
          isTV: false,
          servers: const [],
          lastError: error,
        );

    setUp(() {
      var now = state(ShikooConnection.off);
      states = StreamController.broadcast();
      runs = [];
      container = ProviderContainer(
        overrides: [
          shikooStateProvider.overrideWith((ref) {
            final listen = states.stream.listen((next) {
              now = next;
              ref.invalidateSelf();
            });
            ref.onDispose(listen.cancel);
            return now;
          }),
          shikooProbeProvider.overrideWith(
            () => ShikooProbes(() {
              runs.add(Completer());
              return runs.last.future;
            }),
          ),
        ],
      );
      container.listen(shikooProbeProvider, (_, _) {});
      addTearDown(() async {
        container.dispose();
        await states.close();
      });
    });

    Future<AsyncValue<ProbeChecks>?> go(ShikooState next) async {
      states.add(next);
      await pumpEventQueue();
      container.read(shikooStateProvider);
      await pumpEventQueue();
      return container.read(shikooProbeProvider);
    }

    test('a connect that timed out or found no server is checked; a refused '
        'or missing VPN permission is not', () async {
      final done = _checks('ok', 'ok', 'ok');
      for (final error in [ShikooError.connectTimeout, ShikooError.noServer]) {
        await go(state(ShikooConnection.connecting));
        expect(
          await go(state(ShikooConnection.error, error)),
          isA<AsyncLoading<ProbeChecks>>(),
        );
        runs.last.complete(done);
        await pumpEventQueue();
        expect(container.read(shikooProbeProvider)?.value, done);
      }
      for (final error in [ShikooError.vpnRefused, ShikooError.vpnMissing]) {
        await go(state(ShikooConnection.connecting));
        expect(await go(state(ShikooConnection.error, error)), isNull);
      }
      expect(runs, hasLength(2));
    });

    test('the next connect takes the card away, and a check still running '
        'then never brings it back', () async {
      await go(state(ShikooConnection.connecting));
      await go(state(ShikooConnection.error, ShikooError.connectTimeout));
      expect(await go(state(ShikooConnection.connecting)), isNull);
      runs.single.complete(_checks('ok', 'ok', 'ok'));
      await pumpEventQueue();
      expect(container.read(shikooProbeProvider), isNull);
    });

    test(
      'a server answering later keeps the card until the next connect',
      () async {
        await go(state(ShikooConnection.connecting));
        await go(state(ShikooConnection.error, ShikooError.noServer));
        runs.single.complete(_checks('ok', 'ok', 'ok'));
        expect(await go(state(ShikooConnection.off)), isNotNull);
      },
    );
  });
}
