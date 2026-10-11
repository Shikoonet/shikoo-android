import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart'
    show BaseOptions, Dio, DioException, InterceptorsWrapper;
import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

/// What the server takes (`appApi.ts`, `DeviceName`).
final _serverName = RegExp(r'^[A-Za-z0-9 _()-]{1,40}$');

class _Code {
  _Code(this.secret, this.expires);

  final String secret;
  final DateTime expires;
  ({String? name, String? username})? approvedBy;
  bool refused = false;
  bool used = false;

  /// What a server with shikoo-platform #687 says in its 410; merged main says `gone`.
  String? reason;
}

/// shikoo-platform's app door as `apps/ingest-worker/test/app-login.test.ts` pins it.
class _FakeAppApi {
  late final HttpServer _server;
  final _random = Random.secure();
  final codes = <String, _Code>{};
  final live = <String, bool>{};
  final loggedOut = <String>[];
  final names = <String>[];
  Duration life = const Duration(minutes: 10);
  int startStatus = 200;
  bool startHangs = false;
  int servicesStatus = 200;
  int rateLimitedPolls = 0;
  int polls = 0;
  int listed = 0;
  List<Map<String, Object?>> services = [];
  DateTime Function()? clock;

  DateTime _now() => clock?.call() ?? DateTime.now();

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> open() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) => unawaited(_handle(request)));
  }

  Future<void> close() => _server.close(force: true);

  String _secret() => base64Url
      .encode(List.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  String get lastCode => codes.keys.last;

  Iterable<String> get secrets => [
    for (final code in codes.values) code.secret,
    ...live.keys,
  ];

  Future<void> _handle(HttpRequest request) async {
    final text = await utf8.decodeStream(request);
    final json = text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>;
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    final token = auth != null && auth.startsWith('Bearer ')
        ? auth.substring(7)
        : null;
    Future<void> reply(int status, Map<String, Object?> body) async {
      if (clock case final at?) request.response.headers.date = at();
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    }

    switch ('${request.method} ${request.uri.path}') {
      case 'POST /api/v1/app/login/start':
        if (startHangs) return;
        final name = json?['device_name'];
        if (startStatus != 200) return reply(startStatus, {'ok': false});
        if (name is! String ||
            !_serverName.hasMatch(name.trim()) ||
            !{'phone', 'tv'}.contains(json!['device_kind']) ||
            json.length != 2) {
          return reply(400, {'ok': false, 'error': 'invalid_body'});
        }
        names.add(name);
        final code = '${482915 + codes.length}';
        final expires = _now().add(life);
        codes[code] = _Code(_secret(), expires);
        return reply(200, {
          'ok': true,
          'code': code,
          'poll_secret': codes[code]!.secret,
          'expires_at': expires.toUtc().toIso8601String(),
          'bot_url': 'https://t.me/Test_Shikoo_bot?start=app_$code',
        });
      case 'POST /api/v1/app/login/poll':
        polls++;
        if (rateLimitedPolls > 0) {
          rateLimitedPolls--;
          return reply(429, {'ok': false, 'error': 'rate_limited'});
        }
        final code = codes[json?['code']];
        if (code == null || code.secret != json?['poll_secret']) {
          return reply(404, {'ok': false, 'error': 'not_found'});
        }
        if (code.used || code.refused || !_now().isBefore(code.expires)) {
          return reply(410, {'ok': false, 'error': code.reason ?? 'gone'});
        }
        final who = code.approvedBy;
        if (who == null) return reply(202, {'ok': true, 'status': 'waiting'});
        code.used = true;
        final issued = _secret();
        live[issued] = true;
        return reply(200, {
          'ok': true,
          'token': issued,
          'account': {'name': who.name, 'username': who.username},
        });
      case 'GET /api/v1/app/services':
        listed++;
        if (live[token] != true) {
          return reply(401, {'ok': false, 'error': 'unauthorized'});
        }
        if (servicesStatus != 200) return reply(servicesStatus, {'ok': false});
        return reply(200, {
          'ok': true,
          'bot': 'Test_Shikoo_bot',
          'services': services,
        });
      case 'POST /api/v1/app/logout':
        if (token == null || !live.containsKey(token)) {
          return reply(401, {'ok': false, 'error': 'unauthorized'});
        }
        live[token] = false;
        loggedOut.add(token);
        return reply(200, {'ok': true});
    }
    return reply(404, {'ok': false});
  }
}

Map<String, Object?> _service(
  int id,
  String title, {
  String status = 'active',
  String? url,
  bool noUrl = false,
}) => {
  'id': id,
  'title': title,
  'location': 'الماس',
  'status': status,
  'expires_at': null,
  'sub_url': noUrl ? null : (url ?? 'https://sub.4g3.uk/$title'),
};

const _state = ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: true,
  servers: [],
);

class _Controller extends Mock implements ShikooController {}

/// Holds the next delete until completed.
Completer<void>? _deleteGate;

/// Runs before the fake controller adds [url]: a test holds an add here.
Future<void> Function(String url)? _beforeAdd;

bool _failNextDelete = false;

/// FlClash's own delete also clears files and the core, which a unit test has neither of.
class _Profiles extends ProfilesAction {
  @override
  Future<void> deleteProfile(int id) async {
    if (_failNextDelete) {
      _failNextDelete = false;
      throw const FileSystemException('disk full');
    }
    final gate = _deleteGate;
    _deleteGate = null;
    await gate?.future;
    await ref.read(profilesProvider.notifier).del(id);
  }
}

typedef _Harness = ({
  ProviderContainer container,
  ShikooSignIn signIn,
  _FakeAppApi api,
  _Controller controller,
});

Future<_Harness> _harness({
  List<String>? bases,
  List<Profile> pasted = const [],
  Dio? dio,
}) async {
  SharedPreferences.setMockInitialValues({
    if (pasted.isNotEmpty)
      'shikoo.pasted': [for (final profile in pasted) '${profile.id}'],
  });
  final api = _FakeAppApi();
  await api.open();
  addTearDown(api.close);
  final controller = _Controller();
  late final ProviderContainer container;
  when(() => controller.addService(any(), any(), any())).thenAnswer((
    call,
  ) async {
    final url = call.positionalArguments[0] as String;
    await _beforeAdd?.call(url);
    if (url.contains('dead')) return null;
    final existing = container
        .read(profilesProvider)
        .where((p) => p.url == url)
        .firstOrNull;
    container
        .read(profilesProvider.notifier)
        .put(
          existing ??
              Profile.normal(
                url: url,
                label: call.positionalArguments[1] as String?,
              ),
        );
    return null;
  });
  when(controller.disconnect).thenAnswer((_) async {});
  when(
    () => controller.refreshDue(renewed: any(named: 'renewed')),
  ).thenAnswer((_) async {});
  when(() => controller.renameFromPanel(any())).thenAnswer((_) async {});
  when(controller.forgetServices).thenAnswer((_) async {
    for (final profile in [...container.read(profilesProvider)]) {
      await container.read(profilesProvider.notifier).del(profile.id);
    }
  });
  container = ProviderContainer(
    overrides: [
      shikooApiProvider.overrideWithValue(ShikooApi(bases ?? [api.base], dio)),
      shikooDeviceProvider.overrideWithValue(
        () async => (name: 'Xiaomi MIBOX4', tv: true),
      ),
      shikooControllerProvider.overrideWithValue(controller),
      shikooStateProvider.overrideWithValue(_state),
      profilesProvider.overrideWith(() => TestProfiles(pasted)),
      profilesActionProvider.overrideWith(_Profiles.new),
    ],
  );
  addTearDown(container.dispose);
  final signIn = container.read(shikooSignInProvider)
    ..pollEvery = const Duration(milliseconds: 20);
  return (
    container: container,
    signIn: signIn,
    api: api,
    controller: controller,
  );
}

Future<ShikooLogin?> _until(
  ProviderContainer container,
  bool Function(ShikooLogin? login) done,
) async {
  for (var i = 0; i < 300; i++) {
    final login = container.read(shikooLoginProvider);
    if (done(login)) return login;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('the sign-in stayed at ${container.read(shikooLoginProvider)?.phase}');
}

bool Function(ShikooLogin?) _at(LoginPhase phase) =>
    (login) => login?.phase == phase;

Future<ShikooLogin?> _signedIn(_Harness h, {String? name = 'مریم'}) async {
  await h.signIn.start();
  h.api.codes[h.api.lastCode]!.approvedBy = (name: name, username: 'maryam_k');
  return _until(
    h.container,
    (login) => const {
      LoginPhase.approved,
      LoginPhase.noService,
      LoginPhase.servicesFailed,
    }.contains(login?.phase),
  );
}

List<String> _urls(ProviderContainer container) => [
  for (final profile in container.read(profilesProvider)) profile.url,
];

void main() {
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<int>{});
  });

  group('the device name the bot shows', () {
    test('is the maker and the model, in what the server takes', () {
      final cases = {
        ('Xiaomi', 'MIBOX4'): 'Xiaomi MIBOX4',
        ('HMD Global', 'Nokia 7.2'): 'HMD Global Nokia 7 2',
        ('Xiaomi', 'Xiaomi Redmi Note 8'): 'Xiaomi Redmi Note 8',
        ('samsung', 'SM-G991B (S21_Ultra)'): 'samsung SM-G991B (S21_Ultra)',
        ('سامسونگ', 'a+b@c/d:e'): 'a b c d e',
        ('Google', 'sdk_gphone64_x86_64'): 'Google sdk_gphone64_x86_64',
        ('Google', 'Pixel 😀 7'): 'Google Pixel 7',
        ('Xiaomi', '小米盒子4'): 'Xiaomi 4',
        ('😀', '🔥🔥'): 'Android phone',
        ('小米', '盒子'): 'Android phone',
      };
      for (final MapEntry(key: (maker, model), value: name) in cases.entries) {
        final made = deviceName(maker, model, tv: false);
        expect(made, name);
        expect(_serverName.hasMatch(made), isTrue, reason: made);
      }
    });

    test('is cut to 40 and never empty', () {
      final long = deviceName(
        'Very Long Manufacturer',
        'Model ' * 20,
        tv: true,
      );
      expect(long.length, lessThanOrEqualTo(40));
      expect(_serverName.hasMatch(long), isTrue);
      expect(deviceName('تلویزیون', '۴۳ اینچ', tv: true), 'Android TV');
      expect(deviceName('', '...', tv: false), 'Android phone');
    });
  });

  group('signing in', () {
    test('a code shows, waits, and once approved brings the account and its '
        'services; the device and its kind reach the server', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'user123'), _service(2, 'user789')];
      final link = await h.signIn.start();
      final waiting = h.container.read(shikooLoginProvider)!;
      expect(waiting.phase, LoginPhase.waiting);
      expect(waiting.code, h.api.lastCode);
      expect(link, 'https://t.me/Test_Shikoo_bot?start=app_${h.api.lastCode}');
      expect(h.api.names, ['Xiaomi MIBOX4']);
      await _until(h.container, (_) => h.api.polls > 1);
      expect(h.container.read(shikooLoginProvider)?.phase, LoginPhase.waiting);

      h.api.codes[h.api.lastCode]!.approvedBy = (
        name: 'مریم',
        username: 'maryam_k',
      );
      final approved = await _until(h.container, _at(LoginPhase.approved));
      expect(approved!.account?.name, 'مریم');
      expect(approved.account?.username, 'maryam_k');
      expect(approved.services, ['user123 · الماس', 'user789 · الماس']);
      expect(_urls(h.container), [
        'https://sub.4g3.uk/user123',
        'https://sub.4g3.uk/user789',
      ]);
      verify(
        () => h.controller.addService(any(), 'user123 · الماس', false),
      ).called(1);
      final saved = (await SharedPreferences.getInstance()).getString(
        'shikoo.account',
      );
      expect(saved, contains(h.api.live.keys.single));

      h.signIn.finish();
      expect(h.container.read(shikooLoginProvider), isNull);
      expect(h.container.read(shikooAccountProvider).who?.name, 'مریم');
    });

    test(
      'a start the server never answers gives up within its limit',
      () async {
        final h = await _harness();
        h.api.startHangs = true;
        h.signIn.startLimit = const Duration(milliseconds: 100);
        await h.signIn.start().timeout(const Duration(seconds: 3));
        final failed = h.container.read(shikooLoginProvider);
        expect(failed?.phase, LoginPhase.startFailed);
        expect(failed?.clock, isFalse);
      },
    );

    test('a start whose certificate is not valid yet blames the clock', () async {
      final h = await _harness(
        bases: ['http://127.0.0.1:1'],
        dio: Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) => handler.reject(
                DioException(
                  requestOptions: options,
                  error: const HandshakeException(
                    'Handshake error in client',
                    OSError(
                      'CERTIFICATE_VERIFY_FAILED: certificate is not yet valid',
                    ),
                  ),
                ),
              ),
            ),
          ),
      );
      await h.signIn.start();
      final failed = h.container.read(shikooLoginProvider);
      expect(failed?.phase, LoginPhase.startFailed);
      expect(failed?.clock, isTrue);
    });

    test('the clock an answer carries is learned, and a services list refused '
        'for an expired certificate blames the clock', () async {
      const years14 = Duration(days: 14 * 365);
      addTearDown(() => shikooSkew = Duration.zero);
      final h = await _harness(
        dio: Dio(BaseOptions(validateStatus: (_) => true))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) =>
                  options.path.endsWith('/services')
                  ? handler.reject(
                      DioException(
                        requestOptions: options,
                        error: const HandshakeException(
                          'Handshake error in client',
                          OSError(
                            'CERTIFICATE_VERIFY_FAILED: certificate has expired',
                          ),
                        ),
                      ),
                    )
                  : handler.next(options),
            ),
          ),
      );
      h.api.services = [_service(1, 'user123')];
      h.api.clock = () => DateTime.now().subtract(years14);
      await h.signIn.start();
      expect(shikooSkew.inDays, closeTo(-years14.inDays, 1));

      h.api.codes[h.api.lastCode]!.approvedBy = (name: 'مریم', username: null);
      final failed = await _until(h.container, _at(LoginPhase.servicesFailed));
      expect(failed!.clock, isTrue);
    });

    test('a code lives as long as the server says on a box whose clock is '
        'hours behind', () async {
      addTearDown(() => shikooSkew = Duration.zero);
      final h = await _harness();
      h.api.clock = () => DateTime.now().add(const Duration(hours: 3));
      final code = await h.container
          .read(shikooApiProvider)
          .start(deviceName: 'Xiaomi MIBOX4', tv: true);
      expect(code.lifetime.inSeconds, closeTo(h.api.life.inSeconds, 2));
    });

    test(
      'the reason a newer server gives with its 410 wins over the clock',
      () async {
        final h = await _harness();
        await h.signIn.start();
        h.api.codes[h.api.lastCode]!
          ..used = true
          ..reason = 'used';
        await _until(h.container, _at(LoginPhase.expired));
        // Refused in the code's last poll interval, where the clock alone says expired.
        h.signIn.pollEvery = const Duration(milliseconds: 100);
        h.api.life = const Duration(milliseconds: 150);
        await h.signIn.start();
        h.api.codes[h.api.lastCode]!
          ..refused = true
          ..reason = 'refused';
        await _until(h.container, _at(LoginPhase.rejected));
      },
    );

    test('a refusal before the code runs out reads as refused', () async {
      final h = await _harness();
      await h.signIn.start();
      h.api.codes[h.api.lastCode]!.refused = true;
      await _until(h.container, _at(LoginPhase.rejected));
    });

    test('the code expires on screen at the server\'s time, and is never '
        'swapped for a new one by itself', () async {
      final h = await _harness();
      h.api.life = const Duration(milliseconds: 1500);
      await h.signIn.start();
      final code = h.api.lastCode;
      final expired = await _until(h.container, _at(LoginPhase.expired));
      expect(expired!.code, code);
      final polls = h.api.polls;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.api.polls, polls, reason: 'an expired code is not asked about');
      expect(h.api.codes, hasLength(1));
      await h.signIn.start();
      expect(h.container.read(shikooLoginProvider)?.code, isNot(code));
    });

    test('a sign-in the app let go of stops asking', () async {
      final h = await _harness();
      h.api.life = const Duration(milliseconds: 100);
      await h.signIn.start();
      h.container.dispose();
      final polls = h.api.polls;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(h.api.polls, polls);
    });

    test('a code the server no longer knows starts over as expired', () async {
      final h = await _harness();
      await h.signIn.start();
      h.api.codes.remove(h.api.lastCode);
      await _until(h.container, _at(LoginPhase.expired));
    });

    test('a rate limit only means asking again later', () async {
      final h = await _harness();
      h.api.rateLimitedPolls = 3;
      await h.signIn.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(h.container.read(shikooLoginProvider)?.phase, LoginPhase.waiting);
      h.api.codes[h.api.lastCode]!.approvedBy = (name: 'مریم', username: null);
      await _until(h.container, _at(LoginPhase.noService));
    });

    test('no polling while the app is not on screen', () async {
      final h = await _harness();
      await h.signIn.start();
      h.signIn.foreground = false;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final polls = h.api.polls;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(h.api.polls, polls);
      h.signIn.foreground = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.api.polls, greaterThan(polls));
    });

    test('no code, from the server or the network, says so', () async {
      final h = await _harness();
      h.api.startStatus = 503;
      expect(await h.signIn.start(), isNull);
      expect(
        h.container.read(shikooLoginProvider)?.phase,
        LoginPhase.startFailed,
      );
      await h.api.close();
      expect(await h.signIn.start(), isNull);
      expect(
        h.container.read(shikooLoginProvider)?.phase,
        LoginPhase.startFailed,
      );
    });

    test(
      'a blocked address falls back to the second, which then goes first',
      () async {
        final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        var knocks = 0;
        dead.listen((socket) {
          knocks++;
          socket.destroy();
        });
        addTearDown(dead.close);
        final api = _FakeAppApi();
        await api.open();
        addTearDown(api.close);
        final client = ShikooApi(['http://127.0.0.1:${dead.port}', api.base]);
        await client.start(deviceName: 'x', tv: false);
        await client.start(deviceName: 'x', tv: false);
        expect(api.names, ['x', 'x']);
        expect(knocks, 1);
      },
    );
  });

  group('after approval', () {
    test('an account without services says so', () async {
      final h = await _harness();
      expect((await _signedIn(h))?.phase, LoginPhase.noService);
    });

    test('a list that did not come can be asked for again', () async {
      final h = await _harness();
      h.api.servicesStatus = 500;
      h.api.services = [_service(1, 'user123')];
      expect((await _signedIn(h))?.phase, LoginPhase.servicesFailed);
      h.api.servicesStatus = 200;
      await h.signIn.retry();
      expect(h.container.read(shikooLoginProvider)?.phase, LoginPhase.approved);
    });

    test(
      '«این حساب من نیست» signs the token out and takes only that account\'s '
      'services off the device',
      () async {
        final pasted = Profile.normal(url: 'https://4g3.uk/sub/pasted');
        final h = await _harness(pasted: [pasted]);
        h.api.services = [_service(1, 'user123')];
        await _signedIn(h);
        final token = h.api.live.keys.single;
        await h.signIn.notMine();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(h.api.loggedOut, [token]);
        expect(_urls(h.container), ['https://4g3.uk/sub/pasted']);
        expect(h.container.read(shikooAccountProvider).who, isNull);
        expect(h.container.read(shikooLoginProvider), isNull);
        expect(
          (await SharedPreferences.getInstance()).getString('shikoo.account'),
          isNull,
        );
      },
    );

    test(
      'signing out from settings leaves the server and takes off what the '
      'account brought; without an account it removes what was pasted',
      () async {
        final h = await _harness(
          pasted: [Profile.normal(url: 'https://4g3.uk/sub/pasted')],
        );
        h.api.services = [_service(1, 'user123')];
        await _signedIn(h);
        await h.signIn.signOut();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(h.api.loggedOut, hasLength(1));
        verify(h.controller.disconnect).called(1);
        expect(_urls(h.container), ['https://4g3.uk/sub/pasted']);
        await h.signIn.signOut();
        expect(_urls(h.container), isEmpty);
      },
    );

    test(
      'a pasted link the account also holds stays when the account goes',
      () async {
        final h = await _harness(
          pasted: [Profile.normal(url: 'https://sub.4g3.uk/user123')],
        );
        h.api.services = [_service(1, 'user123'), _service(2, 'user789')];
        await _signedIn(h);
        expect(_urls(h.container), hasLength(2));
        final pasted = h.container.read(profilesProvider).first;
        await h.signIn.notMine();
        expect(_urls(h.container), ['https://sub.4g3.uk/user123']);
        verify(() => h.controller.renameFromPanel(pasted.id)).called(1);
      },
    );

    test(
      'a sign-out while a sync takes services off leaves no account behind',
      () async {
        final h = await _harness();
        h.api.services = [_service(1, 'stays'), _service(2, 'leaves')];
        await _signedIn(h);
        h.signIn.finish();
        h.api.services = [_service(1, 'stays')];
        final gate = _deleteGate = Completer<void>();
        final syncing = h.signIn.sync();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await h.signIn.signOut();
        gate.complete();
        await syncing;
        final account = h.container.read(shikooAccountProvider);
        expect(account.who, isNull);
        expect(account.services, isEmpty);
        expect(_urls(h.container), isEmpty);
      },
    );

    test(
      'an expired or used-up service with no link still comes, to renew',
      () async {
        final h = await _harness();
        h.api.services = [
          _service(51, 'user555', status: 'expired', noUrl: true),
          _service(52, 'user666', status: 'exhausted', noUrl: true),
        ];
        final login = await _signedIn(h);
        expect(login?.phase, LoginPhase.approved);
        expect(login?.services, ['user555 · الماس', 'user666 · الماس']);
        final unlinked = h.container.read(shikooAccountProvider).withoutLink;
        expect([for (final s in unlinked) s.renews], [true, true]);
        verifyNever(() => h.controller.addService(any(), any(), any()));
      },
    );

    test(
      'renewed, a service without a link gets one on the next sync',
      () async {
        final h = await _harness();
        h.api.services = [
          _service(41, 'user123', status: 'expired', noUrl: true),
          _service(42, 'user789'),
        ];
        await _signedIn(h);
        expect(_urls(h.container), ['https://sub.4g3.uk/user789']);
        h.api.services = [_service(41, 'user123'), _service(42, 'user789')];
        expect(await h.signIn.sync(), isTrue);
        expect(_urls(h.container), hasLength(2));
        expect(h.container.read(shikooAccountProvider).withoutLink, isEmpty);
      },
    );

    test('with a service to renew every return asks the door, a settled '
        'account only every ten minutes', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'user123')];
      await _signedIn(h);
      h.signIn.finish();
      final asked = h.api.listed;
      h.signIn.onForeground();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.api.listed, asked);
      h.api.services = [_service(1, 'user123', status: 'expired', noUrl: true)];
      await h.signIn.sync();
      h.signIn.onForeground();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.api.listed, asked + 2);
    });

    test('the minute timer asks the door only for a while after a QR or a '
        'bot link opened, and only while something waits', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'user123')];
      await _signedIn(h);
      h.signIn
        ..finish()
        ..botWindow = const Duration(milliseconds: 300)
        ..botOpened();
      Future<int> minute() async {
        final asked = h.api.listed;
        h.signIn.onMinute();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return h.api.listed - asked;
      }

      expect(await minute(), 0, reason: 'nothing to renew');
      h.api.services = [_service(1, 'user123', status: 'expired', noUrl: true)];
      await h.signIn.sync();
      expect(await minute(), 1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await minute(), 0, reason: 'the QR opened too long ago');
    });

    test('a service the door says runs while its own update says ended is '
        'updated now; one both call running, or the door calls ended, '
        'waits', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'user123')];
      await _signedIn(h);
      h.signIn.finish();
      final profile = h.container.read(profilesProvider).single;
      void subscription(SubscriptionInfo info) => h.container
          .read(profilesProvider.notifier)
          .put(profile.copyWith(subscriptionInfo: info));
      subscription(const SubscriptionInfo(total: 1 << 30));
      await h.signIn.sync();
      verifyNever(
        () => h.controller.refreshDue(renewed: any(named: 'renewed')),
      );
      subscription(const SubscriptionInfo(expire: 1));
      h.signIn.onForeground();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verify(() => h.controller.refreshDue(renewed: {profile.id})).called(1);
      h.api.services = [_service(1, 'user123', status: 'expired', noUrl: true)];
      await h.signIn.sync();
      verifyNever(
        () => h.controller.refreshDue(renewed: any(named: 'renewed')),
      );
    });

    test('a link the paste would refuse never reaches the device: it counts as '
        'none', () async {
      final h = await _harness();
      h.api.services = [
        _service(2, 'foreign', url: 'https://evil.example/sub/x'),
        _service(3, 'empty', url: ''),
        _service(4, 'long', url: 'https://sub.4g3.uk/${'a' * 5000}'),
      ];
      expect((await _signedIn(h))?.phase, LoginPhase.approved);
      verifyNever(() => h.controller.addService(any(), any(), any()));
      expect(_urls(h.container), isEmpty);
      expect(
        [
          for (final s in h.container.read(shikooAccountProvider).withoutLink)
            s.id,
        ],
        [2, 3, 4],
      );
    });

    test('a token that stopped working signs this device out', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'user123')];
      await _signedIn(h);
      h.signIn.finish();
      h.api.live.updateAll((_, _) => false);
      expect(await h.signIn.sync(), isNull);
      expect(_urls(h.container), isEmpty);
      expect(h.container.read(shikooAccountProvider).who, isNull);
    });

    test(
      'a sync adds new links, keeps an expired service for renewal, keeps '
      'a removed one without its link and drops what left the list',
      () async {
        final h = await _harness();
        h.api.services = [
          _service(1, 'stays'),
          _service(2, 'expires'),
          _service(3, 'removed'),
          _service(4, 'leaves'),
          _service(5, 'relinked'),
        ];
        await _signedIn(h);
        h.api.services = [
          _service(1, 'stays'),
          _service(2, 'expires', status: 'expired', noUrl: true),
          _service(3, 'removed', status: 'removed', noUrl: true),
          _service(5, 'relinked', url: 'https://sub.4g3.uk/new-link'),
          _service(6, 'botFirst', noUrl: true),
          _service(7, 'fresh'),
        ];
        expect(await h.signIn.sync(), isTrue);
        expect(
          _urls(h.container),
          unorderedEquals([
            'https://sub.4g3.uk/stays',
            'https://sub.4g3.uk/expires',
            'https://sub.4g3.uk/new-link',
            'https://sub.4g3.uk/fresh',
          ]),
        );
        final account = h.container.read(shikooAccountProvider);
        expect(account.withoutLink.map((s) => s.title), [
          'removed · الماس',
          'botFirst · الماس',
        ]);
        expect(account.withoutLink.map((s) => s.renews), [true, false]);
        expect(account.bot, 'Test_Shikoo_bot');
        final expired = h.container
            .read(profilesProvider)
            .firstWhere((p) => p.url.endsWith('expires'));
        expect(account.serviceOf(expired.id), 2);
      },
    );

    test('a link that would not load stays, without a link, for the next sync '
        'to load; alone it fails the sign-in', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'gone', url: 'https://sub.4g3.uk/dead')];
      expect((await _signedIn(h))?.phase, LoginPhase.servicesFailed);
      List<int> unlinked() => [
        for (final s in h.container.read(shikooAccountProvider).withoutLink)
          s.id,
      ];
      expect(unlinked(), [1]);
      final asked = h.api.listed;
      h.signIn.onForeground();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.api.listed, asked + 1, reason: 'a return asks again at once');
      h.api.services = [
        _service(1, 'gone'),
        _service(2, 'next', url: 'https://sub.4g3.uk/dead2'),
      ];
      expect(await h.signIn.sync(), isTrue);
      expect(_urls(h.container), ['https://sub.4g3.uk/gone']);
      expect(unlinked(), [2], reason: 'kept beside a service that loaded');
    });

    test('a link that did not load is told apart from one the bot has not '
        'made, also after a restart, until it loads', () async {
      final h = await _harness();
      h.api.services = [
        _service(1, 'gone', url: 'https://sub.4g3.uk/dead'),
        _service(2, 'botFirst', noUrl: true),
      ];
      await _signedIn(h);
      Map<int, bool> failed(ProviderContainer container) => {
        for (final s in container.read(shikooAccountProvider).withoutLink)
          s.id: s.loadFailed,
      };
      expect(failed(h.container), {1: true, 2: false});

      final restarted = ProviderContainer(
        overrides: [
          shikooApiProvider.overrideWithValue(ShikooApi([h.api.base])),
          shikooStateProvider.overrideWithValue(_state),
          shikooControllerProvider.overrideWithValue(h.controller),
          profilesProvider.overrideWith(
            () => TestProfiles(h.container.read(profilesProvider)),
          ),
          profilesActionProvider.overrideWith(_Profiles.new),
        ],
      );
      addTearDown(restarted.dispose);
      await restarted.read(shikooSignInProvider).load();
      expect(failed(restarted), {1: true, 2: false}, reason: 'offline restart');

      h.api.services = [
        _service(1, 'gone'),
        _service(2, 'botFirst', noUrl: true),
      ];
      await h.signIn.sync();
      expect(failed(h.container), {2: false}, reason: '1 loaded this time');
    });

    test(
      'a service whose link the bot has not made yet still counts',
      () async {
        final h = await _harness();
        h.api.services = [_service(1, 'botFirst', noUrl: true)];
        final login = await _signedIn(h);
        expect(login?.phase, LoginPhase.approved);
        expect(login?.services, ['botFirst · الماس']);
      },
    );

    for (final leave in ['«این حساب من نیست»', 'signing out']) {
      test(
        '$leave during the first sync takes off what that sync added',
        () async {
          final h = await _harness();
          h.api.services = [_service(1, 'A'), _service(2, 'B')];
          final reachedB = Completer<void>();
          final releaseB = Completer<void>();
          _beforeAdd = (url) async {
            if (!url.endsWith('/B')) return;
            reachedB.complete();
            await releaseB.future;
          };
          addTearDown(() => _beforeAdd = null);
          await h.signIn.start();
          h.api.codes[h.api.lastCode]!.approvedBy = (
            name: 'Stranger',
            username: 's',
          );
          await reachedB.future.timeout(const Duration(seconds: 5));
          expect(_urls(h.container), ['https://sub.4g3.uk/A']);
          await (leave == 'signing out'
              ? h.signIn.signOut()
              : h.signIn.notMine());
          expect(_urls(h.container), isEmpty);
          releaseB.complete();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(_urls(h.container), isEmpty);
          expect(h.container.read(shikooAccountProvider).who, isNull);
          expect(h.container.read(shikooLoginProvider), isNull);
        },
      );
    }

    test('a sign-in while the stranger sync still adds waits for it, then '
        'brings its own services', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'A'), _service(2, 'B')];
      final reachedB = Completer<void>();
      final releaseB = Completer<void>();
      _beforeAdd = (url) async {
        if (!url.endsWith('/B')) return;
        reachedB.complete();
        await releaseB.future;
      };
      addTearDown(() => _beforeAdd = null);
      await h.signIn.start();
      h.api.codes[h.api.lastCode]!.approvedBy = (
        name: 'Stranger',
        username: 's',
      );
      await reachedB.future.timeout(const Duration(seconds: 5));
      await h.signIn.notMine();
      h.api.services = [_service(3, 'C')];
      await h.signIn.start();
      h.api.codes[h.api.lastCode]!.approvedBy = (name: 'مریم', username: 'm');
      await _until(h.container, _at(LoginPhase.syncing));
      releaseB.complete();
      await _until(h.container, _at(LoginPhase.approved));
      expect(_urls(h.container), ['https://sub.4g3.uk/C']);
      expect(h.container.read(shikooAccountProvider).who?.name, 'مریم');
    });

    test('a sync that fails halfway leaves nothing a sign-out keeps', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'A')];
      await _signedIn(h);
      h.signIn.finish();
      h.api.services = [
        _service(2, 'B'),
        _service(1, 'A', status: 'removed', noUrl: true),
      ];
      _failNextDelete = true;
      await expectLater(h.signIn.sync(), throwsA(isA<FileSystemException>()));
      h.api.services = [_service(2, 'B')];
      await h.signIn.sync();
      await h.signIn.notMine();
      expect(_urls(h.container), isEmpty);
    });

    test('an app killed during the first sync leaves nothing a sign-out '
        'keeps', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'A'), _service(2, 'B')];
      final reachedB = Completer<void>();
      _beforeAdd = (url) async {
        if (!url.endsWith('/B')) return;
        reachedB.complete();
        await Completer<void>().future;
      };
      addTearDown(() => _beforeAdd = null);
      await h.signIn.start();
      h.api.codes[h.api.lastCode]!.approvedBy = (
        name: 'Stranger',
        username: 's',
      );
      await reachedB.future.timeout(const Duration(seconds: 5));
      final restarted = ProviderContainer(
        overrides: [
          shikooApiProvider.overrideWithValue(ShikooApi([h.api.base])),
          shikooStateProvider.overrideWithValue(_state),
          profilesProvider.overrideWith(
            () => TestProfiles([...h.container.read(profilesProvider)]),
          ),
          profilesActionProvider.overrideWith(_Profiles.new),
        ],
      );
      addTearDown(restarted.dispose);
      final signIn = restarted.read(shikooSignInProvider);
      await signIn.load();
      expect(_urls(restarted), ['https://sub.4g3.uk/A']);
      expect(restarted.read(shikooAccountProvider).who?.name, 'Stranger');
      await signIn.notMine();
      expect(_urls(restarted), isEmpty);
    });

    test('the first start with the pasted list counts what the stored account '
        'did not bring as pasted', () async {
      final brought = Profile.normal(url: 'https://sub.4g3.uk/brought');
      final adopted = Profile.normal(url: 'https://sub.4g3.uk/adopted');
      final pasted = Profile.normal(url: 'https://4g3.uk/sub/pasted');
      SharedPreferences.setMockInitialValues({
        'shikoo.account': jsonEncode({
          'token': 't',
          'services': [
            {
              'id': 1,
              'title': 'a',
              'status': 'active',
              'profileId': brought.id,
              'owned': true,
            },
            {
              'id': 2,
              'title': 'b',
              'status': 'active',
              'profileId': adopted.id,
              'owned': false,
            },
          ],
        }),
      });
      final controller = _Controller();
      when(() => controller.renameFromPanel(any())).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [
          shikooApiProvider.overrideWithValue(
            ShikooApi(['http://127.0.0.1:9']),
          ),
          shikooControllerProvider.overrideWithValue(controller),
          shikooStateProvider.overrideWithValue(_state),
          profilesProvider.overrideWith(
            () => TestProfiles([brought, adopted, pasted]),
          ),
          profilesActionProvider.overrideWith(_Profiles.new),
        ],
      );
      addTearDown(container.dispose);
      final signIn = container.read(shikooSignInProvider);
      await signIn.load();
      await signIn.notMine();
      expect(_urls(container), [adopted.url, pasted.url]);
      verify(() => controller.renameFromPanel(adopted.id)).called(1);
    });

    test('an account this version cannot read is signed out, and the services '
        'stay', () async {
      for (final stored in [
        'not json',
        '{"token": "t", "name": "مریم", "services": [{"id": 1, "title": "a"}]}',
        '{"token": 7, "services": []}',
      ]) {
        SharedPreferences.setMockInitialValues({'shikoo.account': stored});
        final pasted = Profile.normal(url: 'https://4g3.uk/sub/pasted');
        final container = ProviderContainer(
          overrides: [
            shikooStateProvider.overrideWithValue(_state),
            profilesProvider.overrideWith(() => TestProfiles([pasted])),
          ],
        );
        addTearDown(container.dispose);
        await container.read(shikooSignInProvider).load();
        expect(
          container.read(shikooAccountProvider).who,
          isNull,
          reason: stored,
        );
        expect(container.read(profilesProvider), [pasted]);
        expect(await pastedProfiles(), {pasted.id}, reason: stored);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('shikoo.account'), isNull, reason: stored);
      }
    });

    test('the account and its token survive a restart', () async {
      final h = await _harness();
      h.api.services = [_service(1, 'user123')];
      await _signedIn(h);
      final restarted = ProviderContainer(
        overrides: [
          shikooApiProvider.overrideWithValue(ShikooApi([h.api.base])),
          shikooStateProvider.overrideWithValue(_state),
          shikooControllerProvider.overrideWithValue(h.controller),
          profilesProvider.overrideWith(
            () => TestProfiles(h.container.read(profilesProvider)),
          ),
          profilesActionProvider.overrideWith(_Profiles.new),
        ],
      );
      addTearDown(restarted.dispose);
      final signIn = restarted.read(shikooSignInProvider);
      await signIn.load();
      expect(restarted.read(shikooAccountProvider).who?.name, 'مریم');
      expect(await signIn.sync(), isTrue);
      expect(
        restarted.read(shikooAccountProvider).services.single.profileId,
        isNotNull,
      );
    });
  });

  test('the API goes direct in every profile, the rule written once', () async {
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
    await keepApiDirect();
    final rules = await database.rulesDao.queryAddedRules(1).get();
    expect(rules.map((rule) => rule.rawValue), [
      'DOMAIN,app.chopon.uk,DIRECT',
      'DOMAIN,www.aparat.com,DIRECT',
      'DOMAIN,www.digikala.com,DIRECT',
      'DOMAIN,connectivitycheck.gstatic.com,DIRECT',
    ]);
    expect(
      apiDirectRule('http://10.0.2.2:18790', 1).rawValue,
      'IP-CIDR,10.0.2.2/32,DIRECT,no-resolve',
    );
  });

  test('a service of the account reads its end from expires_at; a broken or '
      'missing one is no date, never an error', () {
    DateTime? at(Object? value) => AccountServiceRow.fromJson({
      'id': 1,
      'title': 'user1',
      'location': null,
      'status': 'expired',
      'sub_url': null,
      'expires_at': value,
    }).expiresAt;
    expect(at('2026-10-13T12:00:00.000Z'), DateTime.utc(2026, 10, 13, 12));
    expect(at(null), isNull);
    expect(at('soon'), isNull);
    expect(at(1760356800), isNull);
  });

  test('no token, poll secret or code reaches a log', () async {
    final printed = <String>[];
    final saved = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = saved);
    await runZoned(
      () async {
        debugPrint('probe');
        final h = await _harness();
        h.api.services = [_service(1, 'user123')];
        await _signedIn(h);
        await h.signIn.sync();
        h.api.live.updateAll((_, _) => false);
        await h.signIn.sync();
        final everything = printed.join('\n');
        expect(everything, contains('probe'));
        expect(h.api.secrets, hasLength(2));
        for (final secret in [...h.api.secrets, ...h.api.codes.keys]) {
          expect(everything, isNot(contains(secret)));
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );
  });
}
