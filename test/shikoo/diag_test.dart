import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

/// Fake values only; none of them was ever a real link, token or key.
const _subLink =
    'https://sub.plantedhost.ir/sub/PlantedPathToken?token=QueryTokenValue&target=clash'
    '&k8=Eightchr&k7=Sevench';
const _portUser = 'QwmZpLkr';
const _portPass = 'HvBnTyUiOpAsDfGh';
const _laterPass = 'JkLzXcVbNmQwErTy';
const _signInToken = 'TokenSecretAbcDefGhi';
const _pollSecret = 'PollSecretXyzUvwRst';
const _liveCode = '482913';

/// Each one goes into every source as a line of its own, so no source can pass without its filter.
/// Several come from the verifier's probe (`vdiag-logs/scripts/zz_verifier_test.dart`).
const _plants = [
  'see $_subLink now',
  'sub.schemeless.ir/sub/Qr7Tz2Wx9Kp4 here',
  'https%3A%2F%2Fpct.encoded.ir%2Fs%2FPc7Xq2Zm9',
  'Foo.bar(https://callhost.ir/s/Ab12,CdEfGh)',
  '#3      Fetch.get (https://framehost.ir/s/Fr4meTok3n:12:5)',
  'Fetch.get(https://fetchhost.ir/s/F3tchTok)',
  'server de1.servername.com up',
  'dial 185.199.110.153:8443 and [2a01:4f8:c0c:1234::1]:443',
  'uuid 3f2b9c1e-7a4d-4e8b-9c2f-1a2b3c4d5e6f and 9a8b7c6d5e4f40312a1b2c3d4e5f6a7b',
  'token Zk3Qp9Lx2Vb7Nc4Rt8Wy1Ha6Jd5Ks0Mf3Gq9Xe2Uo7_',
  'wg yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk=',
  'port $_portUser $_portPass',
  'secrets $_signInToken $_pollSecret $_liveCode',
  'path PlantedPathToken and QueryTokenValue alone',
  'query Eightchr alone',
  'xxPlantedPathTokenyy and querytokenvalue',
  'held host SUB.PLANTEDHOST.IR alone',
  'creds http://$_portUser:$_portPass@127.0.0.1:7890',
  'SUB.VHOSTONE.IR/sub/VtokAlpha77',
  'ساب.وهاست.ایران/sub/VtokBeta88',
  'vhosttwo.ir:2096/sub/VtokGamma99',
  r'https:\/\/vhostthree.ir\/sub\/VtokDelta11',
  '987654321:AAVrfBotTok3nQwErTyUiOpAsDfGhJkLzX',
  'vuser:vpass9X@10.20.30.40:7890',
  '?token=VtokEps123456&x=1',
  '["https://vhostfour.ir/s/VtokZeta22"]',
  'https:/​/vhostfive.ir/s/VtokEta33',
  'https&#58;//vhostsix.ir/s/VtokTheta44',
  'peer 10.11.12.13 up',
  'fe80::1ff:fe23:4567:890a',
  'HTTPS://VHOSTSEVEN.IR/S/VtokIota55',
  'server vhosteight.ir',
  'node de-1.vhostnine.com',
  'vless://11111111-2222-3333-4444-555555555555@vhostten.ir:443?pbk=VrfPbkKeyAbCdEfGh123&sid=6ba85179e30d#DE',
  'ss://YWVzLTI1Ni1nY206VnJmU3NQYXNz@1.2.3.4:8388',
  'sid ab12cd34 here',
  'https%3a%2f%2fvhosttwelve.ir',
  'Foo.bar(sub.vhostthirteen.ir/x,VtokMu88)',
];
const _needles = [
  'plantedhost',
  'PlantedPathToken',
  'QueryTokenValue',
  'Eightchr',
  'schemeless',
  'Qr7Tz2Wx9Kp4',
  'pct.encoded',
  'Pc7Xq2Zm9',
  'callhost',
  'Ab12',
  'CdEfGh',
  'framehost',
  'Fr4meTok3n',
  'fetchhost',
  'F3tchTok',
  'servername',
  '185.199',
  '110.153',
  '8443',
  '2a01',
  '4f8:c0c',
  '3f2b9c1e',
  '9a8b7c6d5e4f',
  'Zk3Qp9Lx2Vb7',
  'yAnz5TF',
  'Bmk=',
  _portUser,
  _portPass,
  _laterPass,
  _signInToken,
  _pollSecret,
  _liveCode,
  'vhostone',
  'VtokAlpha77',
  'وهاست',
  'VtokBeta88',
  'vhosttwo',
  'VtokGamma99',
  '2096',
  'vhostthree',
  'VtokDelta11',
  '987654321',
  'AAVrfBotTok3n',
  'vpass9X',
  '10.20.30.40',
  'VtokEps123456',
  'vhostfour',
  'VtokZeta22',
  'vhostfive',
  'VtokEta33',
  'vhostsix',
  'VtokTheta44',
  '10.11.12.13',
  'fe23:4567',
  'vhostseven',
  'VtokIota55',
  'vhosteight',
  'vhostnine',
  'vhostten',
  'VrfPbkKeyAbCdEfGh123',
  '6ba85179e30d',
  '55555555',
  'YWVzLTI1Ni1nY206',
  'ab12cd34',
  'vhosttwelve',
  'vhostthirteen',
  'VtokMu88',
  '://',
];

/// A number alone must not be found inside a longer one, as a time.
bool _leaked(String json, String needle) => RegExp(
  RegExp(r'^\d+$').hasMatch(needle)
      ? '(?<!\\d)${RegExp.escape(needle)}(?!\\d)'
      : RegExp.escape(needle),
  caseSensitive: false,
).hasMatch(json);

/// shikoo-platform's `appReport.ts` (draft PR 709): every key the door's `.strict()` sections name.
const _doorKeys = {
  'meta.schema', 'meta.device_time_ms', 'meta.trigger', //
  'app.version', 'app.build', 'app.core', 'app.abi', 'app.env', 'app.signed_in',
  'app.language', 'app.theme', //
  'device.tv',
  'device.manufacturer',
  'device.brand',
  'device.model',
  'device.device',
  'device.release',
  'device.sdk',
  'device.security_patch',
  'device.abis',
  'device.low_ram',
  'device.ram_total_mb',
  'device.ram_free_mb',
  'device.disk_free_mb',
  'device.time_zone',
  'device.tz_offset_min', 'device.locale', //
  'screen.width_dp',
  'screen.height_dp',
  'screen.pixel_ratio',
  'screen.text_scale',
  'screen.padding.top',
  'screen.padding.right',
  'screen.padding.bottom',
  'screen.padding.left',
  'screen.insets.top',
  'screen.insets.right',
  'screen.insets.bottom',
  'screen.insets.left',
  'screen.bold_text', 'screen.navigation_mode', //
  'graphics.backend', //
  'network.transports',
  'network.airplane',
  'network.sim_slots',
  'network.sims.slot',
  'network.sims.network_name',
  'network.sims.network_code',
  'network.sims.sim_name',
  'network.sims.sim_code', 'network.sims.data', 'network.private_dns_active',
  'network.private_dns_strict', 'network.data_saver', //
  'power.battery_saver', 'power.idle', 'power.battery_optimized',
  'power.background_restricted', 'power.standby_bucket', //
  'vpn.state', 'vpn.last_error', 'vpn.other_vpn', //
  'checks.domestic.result', 'checks.domestic.ms', 'checks.international.result',
  'checks.international.ms', 'checks.door.result', 'checks.door.ms', //
  'services.username',
  'services.status',
  'services.days_left',
  'services.used_gb',
  'services.total_gb',
  'services.last_refresh',
  'services.minutes_since_update', //
  'servers.label', 'servers.ping_ms', //
  'crashes.source',
  'crashes.time_ms',
  'crashes.reason',
  'crashes.status',
  'crashes.text', //
  'log', 'logcat', 'images.app', 'images.screen', 'images.note',
};

/// The door's caps (`appReport.ts`) and the app's 1.4 MiB under its 1.5, as literals: a raised cap fails.
const _doorLogLines = 700;
const _doorImageChars = 400 * 1024;
const _doorBytes = 1468006;

Set<String> _keysOf(Object? value, [String path = '']) => switch (value) {
  final Map<String, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries)
      ..._keysOf(value, path.isEmpty ? key : '$path.$key'),
  },
  final List<Object?> list when list.firstOrNull is Map => {
    for (final item in list) ..._keysOf(item, path),
  },
  _ => {path},
};

const _diagChannel = MethodChannel('shikoo/diag');
final _now = DateTime.now();

class _Harness {
  _Harness(this.home, this.container, this.diag, this.sent);

  final Directory home;
  final ProviderContainer container;
  final ShikooDiag diag;

  /// What reached `/report`, and the door's answer to the next one.
  final List<RequestOptions> sent;
  static var reportStatus = 200;

  String get dir => '${home.path}/shikoo';
}

Future<_Harness> _harness({
  ShikooState? state,
  List<String> plants = const [],
  Object? Function(MethodCall call)? native,
}) async {
  SharedPreferences.setMockInitialValues({
    'shikoo.account': jsonEncode({
      'token': _signInToken,
      'name': null,
      'username': null,
      'bot': null,
      'services': [],
    }),
  });
  final home = Directory.systemTemp.createTempSync('diag');
  addTearDown(() => home.deleteSync(recursive: true));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        _diagChannel,
        (call) async => native?.call(call),
      );
  final sent = <RequestOptions>[];
  final door = Dio(BaseOptions(validateStatus: (_) => true))
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          options.path.endsWith('/report')
              ? (sent..add(options), _reportAnswer(options)).$2
              : Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'code': _liveCode,
                    'poll_secret': _pollSecret,
                    'bot_url': 'https://t.me/test_bot?start=$_liveCode',
                    'expires_at': _now
                        .add(const Duration(minutes: 10))
                        .toUtc()
                        .toIso8601String(),
                  },
                ),
        ),
      ),
    );
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(
        () => TestProfiles([Profile.normal(label: 'x', url: _subLink)]),
      ),
      shikooStateProvider.overrideWithValue(
        state ??
            ShikooState(
              connection: ShikooConnection.off,
              connectedFor: Duration.zero,
              isTV: false,
              servers: [
                for (final plant in plants)
                  ShikooServer(name: plant, type: 'vless', ping: 120),
              ],
              others: [
                for (final (i, plant) in plants.indexed)
                  ShikooService(
                    id: i,
                    name: plant,
                    usedBytes: 1 << 30,
                    totalBytes: 10 << 30,
                  ),
              ],
            ),
      ),
      shikooApiProvider.overrideWithValue(
        ShikooApi(['http://door.test'], door),
      ),
      shikooDeviceProvider.overrideWithValue(
        () async => (name: 'Test', tv: false),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(networkSettingProvider, (_, _) {});
  container
      .read(networkSettingProvider.notifier)
      .update(
        (s) => s.copyWith(
          authentication: const AuthenticationProps(
            enable: true,
            username: _portUser,
            password: _portPass,
          ),
        ),
      );
  final signIn = container.read(shikooSignInProvider)
    ..pollEvery = const Duration(hours: 1);
  await signIn.load();
  await signIn.start();
  return _Harness(home, container, ShikooDiag(), sent);
}

Response<Object?> _reportAnswer(RequestOptions options) => Response(
  requestOptions: options,
  statusCode: _Harness.reportStatus,
  data: _Harness.reportStatus == 200
      ? {'ok': true, 'code': '48219037', 'linked': true}
      : {'error': 'contains_link'},
);

final _about = aboutSections(
  device: AndroidDeviceInfo.setMockInitialValues(
    version: AndroidBuildVersion.setMockInitialValues(
      baseOS: '',
      codename: 'REL',
      incremental: '1',
      previewSdkInt: 0,
      release: '15',
      sdkInt: 35,
      securityPatch: '2026-09-05',
    ),
    board: 'b',
    bootloader: 'b',
    brand: 'POCO',
    device: 'c85',
    display: 'd',
    fingerprint: 'f',
    hardware: 'h',
    host: 'h',
    id: 'i',
    manufacturer: 'Xiaomi',
    model: 'POCO C85',
    product: 'p',
    name: 'n',
    supported32BitAbis: const ['armeabi-v7a'],
    supported64BitAbis: const ['arm64-v8a'],
    supportedAbis: const ['arm64-v8a', 'armeabi-v7a'],
    tags: 't',
    type: 'user',
    isPhysicalDevice: true,
    freeDiskSize: 8 << 30,
    totalDiskSize: 64 << 30,
    systemFeatures: const [],
    isLowRamDevice: false,
    physicalRamSize: 4096,
    availableRamSize: 1024,
  ),
  tv: false,
  version: '1.0.3',
  build: 3,
  abi: 'arm64-v8a',
  signedIn: true,
  look: (theme: ThemeMode.system, language: 'fa'),
  media: const MediaQueryData(
    size: Size(393, 873),
    devicePixelRatio: 2.75,
    padding: EdgeInsets.only(top: 24),
  ),
  transports: const [ConnectivityResult.mobile, ConnectivityResult.vpn],
  native: const {
    'airplane': false,
    'simSlots': 2,
    'sims': [
      {
        'slot': 0,
        'network': 'MCI',
        'networkCode': '43211',
        'sim': 'MCI',
        'simCode': '43211',
        'data': true,
      },
    ],
    'privateDns': 'strict',
    'dataSaver': 3,
    'batterySaver': false,
    'idle': false,
    'ignoresOptimizations': false,
    'backgroundRestricted': false,
    'standbyBucket': 10,
    'navigation': 2,
  },
  backend: 'vulkan',
  now: _now,
  locale: 'fa-IR',
);

Future<Uint8List> _noisePng(int side) async {
  final noise = Random(side);
  // Opaque: random alpha would be premultiplied away and compress.
  final random = List<int>.generate(
    side * side * 4,
    (i) => i % 4 == 3 ? 255 : noise.nextInt(256),
  );
  final image = await () {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(random),
      side,
      side,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cleanLine keeps what support reads', () {
    test('Persian words, digits and the zero-width joiner', () {
      const ping = 'ping ۱۲ جواب، ۳ بی‌جواب، بهترین ۱۸۰';
      expect(cleanLine(ping, null), ping);
    });

    test('a core dial failure keeps its shape and loses its addresses', () {
      expect(
        cleanLine(
          '[TCP] dial 🦄 --> 185.199.110.153:443 error: Zk3Qp9Lx2Vb7Nc4Rt8 timeout',
          null,
        ),
        '[TCP] dial · --> · error: · timeout',
      );
    });

    test('a Dart frame and its closure stay whole', () {
      const frame =
          '#1      ShikooSignIn.start.<anonymous closure> '
          '(package:fl_clash/shikoo/engine/account.dart:611:9)';
      expect(cleanLine(frame, null), frame);
    });

    test('a TLS failure keeps its exception and its constant', () {
      final line = cleanLine(
        'HandshakeException: Handshake error in client (OS Error: '
        'CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate)',
        null,
      );
      expect(line, contains('HandshakeException: Handshake error'));
      expect(line, contains('CERTIFICATE_VERIFY_FAILED'));
      expect(cleanLine('status=404', null), 'status=404');
    });

    test('a mix of letters and digits stays only up to six', () {
      expect(cleanLine('DE-1 x1y2z3 sid ab12cd34', null), 'DE-1 x1y2z3 sid ·');
    });

    test('a Go frame keeps only its file and line', () {
      expect(
        cleanLine('\t/root/go/src/core/hub.go:636 +0x25', null, go: true),
        '\thub.go:636 ·',
      );
    });
  });

  test(
    'no planted link, address, token or key reaches the report from any source',
    () async {
      final now = _now.millisecondsSinceEpoch;
      final h = await _harness(
        plants: _plants,
        native: (call) => switch (call.method) {
          'exits' => [
            {
              'reason': 6,
              'status': 0,
              'time': now - 60000,
              'description': 'anr',
              'trace': [
                '"main" prio=5 tid=1 Blocked',
                for (final plant in _plants) '  at $plant',
              ].join('\n'),
            },
          ],
          'logTail' => [
            for (final plant in _plants)
              '10-07 14:58:05.381  1234  5678 D FlClash : $plant',
          ].join('\n'),
          'renderer' => 'Using the Impeller rendering backend (Vulkan).',
          _ => null,
        },
      );
      final diag = h.diag;
      for (final plant in _plants) {
        diag.add('A', 'before start $plant');
      }
      await diag.start(h.home.path);
      for (final plant in _plants) {
        diag.add('A', 'before attach $plant');
      }
      File('${h.dir}/events.txt').writeAsStringSync(
        [for (final plant in _plants) '$now revoked $plant'].join('\n'),
      );
      File('${h.dir}/java-crash.txt').writeAsStringSync(
        '--- $now main\n'
        '${[for (final plant in _plants) 'java.lang.IllegalStateException: $plant'].join('\n')}\n'
        '\tat com.follow.clash.Foo.bar(Foo.kt:12)\n',
      );
      File('${h.home.path}/go-crash.txt').writeAsStringSync(
        '${[for (final plant in _plants) 'panic: $plant'].join('\n')}\n\n'
        'goroutine 1 [running]:\nmain.handleCrash(...)\n'
        '\t/root/src/core/hub.go:636 +0x25\n',
      );
      await diag.attach(h.container);
      for (final plant in _plants) {
        diag
          ..add('A', 'after attach $plant')
          ..add('T', 'timeline $plant')
          ..add('U', 'push $plant')
          ..onLog(Log(logLevel: LogLevel.warning, payload: plant, dateTime: ''))
          ..error(
            StateError(plant),
            StackTrace.fromString('#0      Foo.bar ($plant)'),
          );
      }
      h.container
          .read(networkSettingProvider.notifier)
          .update(
            (s) => s.copyWith(
              authentication: s.authentication.copyWith(password: _laterPass),
            ),
          );
      diag.add('A', 'the new password is $_laterPass');

      final report = await diag.report(trigger: 'test', about: _about);
      final json = jsonEncode(report);

      expect([
        for (final n in _needles)
          if (_leaked(json, n)) n,
      ], isEmpty);
      final log = (report['log']! as List).cast<String>();
      for (final kind in ['A', 'T', 'C', 'E', 'U']) {
        expect(
          log.where((line) => line.split(' ')[1] == kind).length,
          greaterThanOrEqualTo(_plants.length),
          reason: kind,
        );
      }
      expect(report['crashes'], hasLength(3));
      expect(report['logcat'], hasLength(_plants.length));
      expect(report['servers'], hasLength(_plants.length));
      expect(json, contains('revoked'));
      expect(json, contains('hub.go:636'));
    },
  );

  testWidgets('a big record still fits the door: errors first, then the newest', (
    tester,
  ) async {
    final h = await tester.runAsync(_harness);
    final diag = h!.diag;
    await tester.runAsync(() => diag.start(h.home.path));
    await tester.runAsync(() => diag.attach(h.container));
    final errors = <String>[];
    final rest = <String>[];
    for (var i = 0; i < 2000; i++) {
      if (i % 20 < 3) {
        diag.add('E', 'boom $i');
        errors.add('E boom $i');
      } else {
        diag.add('A', 'line $i');
        rest.add('A line $i');
      }
    }
    diag.add('A', 'long ${'abc ' * 1250}');
    File('${h.dir}/java-crash.txt').writeAsStringSync(
      '--- ${_now.millisecondsSinceEpoch} main\nhead of the stack\n'
      '${'\tat com.example.Foo.bar(Foo.kt:1)\n' * 600}',
    );
    final big = await tester.runAsync(() => _noisePng(1100));
    // Over the door's 400 KiB as base64, under 500: the window a raised cap would let through.
    final medium = await tester.runAsync(() => _noisePng(314));

    final report = (await tester.runAsync(
      () => diag.report(
        trigger: 'test',
        about: _about,
        appImage: medium,
        screenImage: big,
      ),
    ))!;

    final log = (report['log']! as List).cast<String>();
    String body(String line) => line.substring(21);
    expect(log, hasLength(_doorLogLines));
    expect(log.every((line) => line.length <= 300), isTrue);
    expect(log.last.length, greaterThan(250));
    expect(body(log.last), startsWith('A long abc'));
    expect(log.map(body).where((l) => l.startsWith('E ')), errors);
    expect(
      log.map(body).where((l) => !l.startsWith('E ')).toList()..removeLast(),
      rest.sublist(rest.length - (_doorLogLines - errors.length - 1)),
    );
    final crash = (report['crashes']! as List).single as Map;
    expect((crash['text']! as String).length, 8192);
    expect(crash['text'], startsWith('head of the stack'));
    final images = report['images']! as Map;
    expect(big!.length, greaterThan(3 << 20));
    expect(
      base64.encode(medium!).length,
      allOf(greaterThan(_doorImageChars), lessThanOrEqualTo(500 * 1024)),
    );
    expect(
      (images['app']! as String).length,
      lessThanOrEqualTo(_doorImageChars),
    );
    expect(images.containsKey('screen'), isFalse);
    expect(images['note'], 'too_large');
    expect(
      utf8.encode(jsonEncode(report)).length,
      lessThanOrEqualTo(_doorBytes),
    );
  });

  test(
    'the 1.4 MB ceiling counts UTF-8 bytes, so Persian text drops the images',
    () {
      String persian(int n) => ('گزارش' * (n ~/ 5 + 1)).substring(0, n);
      final report = <String, Object?>{
        'meta': {'schema': 1, 'device_time_ms': 1, 'trigger': 'test'},
        'log': [for (var i = 0; i < 700; i++) persian(300)],
        'logcat': [for (var i = 0; i < 100; i++) persian(300)],
        'crashes': [
          for (var i = 0; i < 10; i++)
            {'source': 'java', 'time_ms': i, 'text': persian(8192)},
        ],
        'servers': [
          for (var i = 0; i < 300; i++) {'label': persian(100), 'ping_ms': i},
        ],
        'images': {
          'app': 'A' * _doorImageChars,
          'screen': 'B' * _doorImageChars,
        },
      };
      expect(jsonEncode(report).length, lessThan(_doorBytes));

      final fitted = fitReport(report);

      expect(fitted['images'], {'note': 'too_large'});
      expect(fitted['log'], hasLength(700));
      expect(
        utf8.encode(jsonEncode(fitted)).length,
        lessThanOrEqualTo(_doorBytes),
      );
    },
  );

  test('the report names exactly the keys the door takes', () async {
    final h = await _harness(
      state: ShikooState(
        connection: ShikooConnection.error,
        connectedFor: Duration.zero,
        isTV: false,
        lastError: ShikooError.connectTimeout,
        servers: const [
          ShikooServer(name: 'Germany 2', type: 'vless', ping: 1),
        ],
        service: ShikooService(
          id: 7,
          name: 'Shi · Gold',
          usedBytes: 1 << 30,
          totalBytes: 10 << 30,
          expire: _now.add(const Duration(days: 9)),
          updatedAt: _now,
        ),
      ),
      native: (call) => switch (call.method) {
        'exits' => [
          {
            'reason': 3,
            'status': 0,
            'time': _now.millisecondsSinceEpoch - 1000,
            'description': 'low memory',
          },
        ],
        'logTail' =>
          '10-07 14:58:05.381  1234  5678 D FlClash : VPN permission revoked',
        _ => null,
      },
    );
    final diag = h.diag;
    await diag.start(h.home.path);
    await diag.attach(h.container);
    diag.refreshed(7, null);
    File(
      '${h.dir}/java-crash.txt',
    ).writeAsStringSync('--- ${_now.millisecondsSinceEpoch} main\nboom\n');
    File('${h.home.path}/go-crash.txt').writeAsStringSync('panic: boom\n');

    final report = await diag.report(
      trigger: 'test',
      about: _about,
      appImage: Uint8List.fromList(List.filled(64, 1)),
      screenImage: Uint8List.fromList(List.filled(64, 2)),
    );

    final keys = _keysOf(report);
    expect(_doorKeys, containsAll(keys));
    expect(_doorKeys.difference(keys), {
      'checks.domestic.result', 'checks.domestic.ms',
      'checks.international.result', 'checks.international.ms',
      'checks.door.result', 'checks.door.ms', // the probes are WP5
      'images.note', // only when an image is dropped or switched off
    });
  });

  test(
    'a sent report goes with the Bearer and clears the crash files it carried',
    () async {
      final h = await _harness(
        native: (call) => switch (call.method) {
          // As ShikooDiag.kt: only the records newer than the argument.
          'exits' => [
            if ((call.arguments as int) < _now.millisecondsSinceEpoch - 5)
              {
                'reason': 4,
                'status': 0,
                'time': _now.millisecondsSinceEpoch - 5,
              },
          ],
          _ => null,
        },
      );
      final diag = h.diag;
      await diag.start(h.home.path);
      await diag.attach(h.container);
      final javaText = '--- ${_now.millisecondsSinceEpoch} main\nboom\n';
      final java = File('${h.dir}/java-crash.txt')..writeAsStringSync(javaText);
      final go = File('${h.home.path}/go-crash.txt')
        ..writeAsStringSync('panic: boom\n');
      // The Go core's own descriptor, opened at its init and kept for the process.
      final held = go.openSync(mode: FileMode.append);
      final report = await diag.report(trigger: 'test', about: _about);

      _Harness.reportStatus = 422;
      addTearDown(() => _Harness.reportStatus = 200);
      await expectLater(diag.send(report), throwsA(isA<ShikooApiFailure>()));
      expect(
        [java.readAsStringSync(), go.readAsStringSync()],
        [javaText, 'panic: boom\n'],
      );

      _Harness.reportStatus = 200;
      expect(await diag.send(report), (code: '48219037', linked: true));

      final request = h.sent.last;
      expect(request.uri.path, '/api/v1/app/report');
      expect(request.headers['Authorization'], 'Bearer $_signInToken');
      expect(request.sendTimeout, const Duration(seconds: 60));
      expect(request.data, report);
      expect([java.readAsStringSync(), go.readAsStringSync()], ['', '']);
      final again = await diag.report(trigger: 'test', about: _about);
      expect(again['crashes'], isEmpty);

      // O_APPEND, as Go opens it: the next panic of this process lands in the same file.
      held
        ..setPositionSync(held.lengthSync())
        ..writeStringSync('panic: after the send\n')
        ..closeSync();
      expect(go.readAsStringSync(), 'panic: after the send\n');
      final next = await diag.report(trigger: 'test', about: _about);
      expect(
        [for (final c in next['crashes']! as List) (c as Map)['source']],
        ['go'],
      );
    },
  );

  test(
    'a service keeps the panel username a log line loses, never a link, token or secret',
    () async {
      ShikooService named(int id, String name) =>
          ShikooService(id: id, name: name, usedBytes: 0, totalBytes: 0);
      final longest = '${'a' * 60}_123';
      final h = await _harness(
        state: ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: false,
          servers: const [],
          service: named(1, 'ali_2024 · Gold'),
          others: [
            named(2, longest),
            named(3, 'clash'),
            named(4, '${longest}x'),
            named(5, 'https://x.ir/s/abc'),
            named(6, 'sub.schemeless.ir/sub/Qr7Tz2Wx9Kp4'),
            named(8, _portUser),
            named(9, _portPass.toLowerCase()),
            named(10, _signInToken),
            named(11, _liveCode),
            named(12, 'PlantedPathToken'),
            named(13, 'QueryTokenValue'),
            named(14, 'x-shelf-1'),
            named(15, 'vhosteight.ir'),
            named(16, '185.199.110.153'),
            const ShikooService(
              id: 17,
              name: 'ali_2024 ۲',
              account: 'ali_2024',
              usedBytes: 0,
              totalBytes: 0,
            ),
            const ShikooService(
              id: 18,
              name: 'Gold',
              account: 'PlantedPathToken',
              usedBytes: 0,
              totalBytes: 0,
            ),
          ],
        ),
      );
      final diag = h.diag;
      await diag.start(h.home.path);
      await diag.attach(h.container);
      diag
        ..add('A', 'service ali_2024 refreshed')
        ..add('A', 'Sevench stays, Eightchr goes')
        ..add('A', 'FlClash core up');

      final report = await diag.report(trigger: 'test', about: _about);

      expect(
        [for (final s in report['services']! as List) (s as Map)['username']],
        [
          'ali_2024',
          longest,
          'clash',
          ...List.filled(9, '·'),
          'x-shelf-1',
          '·',
          '·',
          'ali_2024',
          '·',
        ],
      );
      final log = (report['log']! as List).cast<String>();
      expect(log, contains(endsWith(' A service · refreshed')));
      expect(log, contains(endsWith(' A Sevench stays, · goes')));
      expect(log.last, endsWith(' A FlClash core up'));
    },
  );

  test('the report keeps the door caps on crashes and servers', () async {
    final now = _now.millisecondsSinceEpoch;
    final h = await _harness(
      plants: [for (var i = 0; i < 301; i++) 'Germany $i'],
    );
    final diag = h.diag;
    await diag.start(h.home.path);
    await diag.attach(h.container);
    File('${h.dir}/java-crash.txt').writeAsStringSync(
      [for (var i = 0; i < 12; i++) '--- ${now - i} main\nboom $i\n'].join(),
    );

    final report = await diag.report(trigger: 'test', about: _about);

    expect(report['crashes'], hasLength(10));
    expect(report['servers'], hasLength(300));
    expect(report['services'], hasLength(20));
  });

  testWidgets('a slow frame is summed up every 10 minutes, not every minute', (
    tester,
  ) async {
    final h = await tester.runAsync(_harness);
    final diag = h!.diag;
    await tester.runAsync(() => diag.start(h.home.path));
    await tester.runAsync(() => diag.attach(h.container));
    final frames = diag.watchUi();
    final slow = ui.FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: 1000,
      rasterStart: 1000,
      rasterFinish: 51000,
      rasterFinishWallTime: 51000,
    );
    String ring() => File('${h.dir}/diag.log').readAsStringSync();

    tester.binding.platformDispatcher.onReportTimings!([slow, slow]);
    await tester.pump(const Duration(minutes: 9));
    expect(ring(), isNot(contains(' T frames ')));
    await tester.pump(const Duration(minutes: 1));
    expect(ring(), contains(' T frames 2 slow 2 build 1ms raster 50ms'));
    frames.cancel();
  });

  test('a minute of frames is written only when one was slow', () {
    expect(frameSummary(60, 0, 4, 15), isNull);
    expect(
      frameSummary(60, 2, 9, 45),
      'frames 60 slow 2 build 9ms raster 45ms',
    );
  });
}
