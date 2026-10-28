import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/warp.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Core extends Mock implements CoreHandlerInterface {}

const _setup = SetupState(
  profileId: 1,
  profileLastUpdateDate: null,
  overwriteType: OverwriteType.standard,
  rules: [],
  proxyGroups: [],
  addedRules: [],
  script: null,
  overrideDns: false,
  dns: defaultDns,
);

void main() {
  final files = Directory.systemTemp.createTempSync('shikoo-warp-');

  setUpAll(() {
    AppPath.supportDirectory = AppPath.temporaryDirectory =
        AppPath.cacheDirectory = () async => files;
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: '0.8.98',
      buildNumber: '1',
    );
  });

  test(
    "the bridge's license and where its source is travel with the app",
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerWarpLicenses();
      final entries = await LicenseRegistry.licenses
          .where((entry) => entry.packages.contains('aether'))
          .map((entry) => entry.paragraphs.map((p) => p.text).join(' '))
          .toList();
      expect(entries, hasLength(2));
      expect(entries[0], contains('https://github.com/patterniha/Aether'));
      expect(entries[0], contains('aether-proxy-auth.patch'));
      expect(entries[0], contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
      expect(entries[1], contains('boring-sys'));
    },
  );

  group('markWarp', () {
    final config = <String, dynamic>{
      'proxies': [
        {
          'name': 'A',
          'type': 'vless',
          'server': '1.1.1.1',
          'shikoo-core': 'xray',
        },
        {
          'name': 'B',
          'type': 'wireguard',
          'server': '1.1.1.2',
          'shikoo-owner': 'wireguard',
        },
        {
          'name': 'C',
          'type': 'vless',
          'server': '1.1.1.3',
          'dialer-proxy': 'B',
        },
        {'name': 'D', 'type': 'Direct'},
        {'name': 'E', 'type': 'vless', 'shikoo-core': 'xray'},
      ],
      'mode': 'rule',
    };

    test('nothing needs the bridge: the config is the same object, without '
        'the bridge', () {
      expect(markWarp(config, noWarp), same(config));
    });

    test('only the servers on the route leave through it, a chain from its '
        'first hop; a core behind mihomo gives such a server back; a direct '
        'one stays direct, never free WARP', () {
      final marked = markWarp(config, (via: {'A', 'C', 'D'}, app: false));
      final proxies = (marked['proxies'] as List).cast<Map>();
      expect(marked['mode'], 'rule');
      expect(proxies.map((p) => p['dialer-proxy']), [
        warpProxyName,
        null,
        'B',
        null,
        null,
        null,
      ]);
      expect(proxies[0].containsKey('shikoo-core'), isFalse);
      expect(proxies[1], config['proxies'][1], reason: 'not on the route');
      expect(proxies[3], {'name': 'D', 'type': 'Direct'});
      expect(proxies[4]['shikoo-core'], 'xray', reason: 'not on the route');
      expect(proxies.last, {
        'name': warpProxyName,
        'type': 'socks5',
        'server': '127.0.0.1',
        'port': 1,
        'shikoo-core': 'warp',
      });
      expect(
        (config['proxies'] as List).first,
        containsPair('shikoo-core', 'xray'),
        reason: 'the input is not changed',
      );
    });

    test('the app alone needs it: the bridge joins, every server stays '
        'direct', () {
      final marked = markWarp(config, (via: const {}, app: true));
      final proxies = (marked['proxies'] as List).cast<Map>();
      expect(proxies.take(5), config['proxies']);
      expect(proxies.last['name'], warpProxyName);
      expect(markWarp({}, (via: const {}, app: true))['proxies'], hasLength(1));
    });
  });

  group('the route', () {
    test('off, nothing at all, whatever is remembered or tried', () {
      expect(
        warpRoute(on: false, remembered: {'A'}, trial: {'B'}, app: true),
        noWarp,
      );
    });

    test('on, what this network remembers and what is on trial', () {
      final route = warpRoute(
        on: true,
        remembered: {'A'},
        trial: {'B'},
        app: true,
      );
      expect(route.via, {'A', 'B'});
      expect(route.app, isTrue);
      expect(sameRoute(route, (via: {'B', 'A'}, app: true)), isTrue);
      expect(sameRoute(route, (via: {'A'}, app: true)), isFalse);
      expect(sameRoute(route, (via: {'A', 'B'}, app: false)), isFalse);
    });

    test('the silent servers not already on the bridge, and only while on', () {
      expect(bridgeCandidates(on: true, silent: ['A', 'B'], via: {'B'}), {'A'});
      expect(bridgeCandidates(on: false, silent: ['A'], via: {}), isEmpty);
    });
  });

  test('with no service the core gets the bridge alone, only for the app', () {
    expect(warpOnlyProfile(noWarp), (yaml: '', md5: ''));
    expect(warpOnlyProfile((via: {'A'}, app: false)), (yaml: '', md5: ''));
    final only = warpOnlyProfile((via: const {}, app: true));
    expect(json.decode(only.yaml), {
      'proxies': [markWarp({}, (via: const {}, app: true))['proxies'][0]],
    });
    expect(only.md5, only.yaml.toMd5());
  });

  test('each network keeps its own servers, on this device', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final memory = container.read(shikooWarpMemoryProvider.notifier);
    await memory.set('mobile', {'A'});
    await memory.set('wifi', {'B'});
    await memory.set('wifi', {});
    final again = ProviderContainer();
    addTearDown(again.dispose);
    await again.read(shikooWarpMemoryProvider.notifier).load();
    expect(again.read(shikooWarpMemoryProvider), {
      'mobile': {'A'},
    });
  });

  group('warpLegWanted', () {
    final refused = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionError,
    );
    final answered = DioException(
      requestOptions: RequestOptions(),
      response: Response(requestOptions: RequestOptions(), statusCode: 404),
    );

    test('only on, on the untold way, and only once nothing answered', () {
      expect(warpLegWanted(on: true, chosen: false, error: refused), isTrue);
      expect(
        warpLegWanted(on: true, chosen: false, error: StateError('x')),
        isTrue,
      );
      expect(warpLegWanted(on: false, chosen: false, error: refused), isFalse);
      expect(warpLegWanted(on: true, chosen: true, error: refused), isFalse);
      expect(warpLegWanted(on: true, chosen: false, error: answered), isFalse);
    });
  });

  group('warpProxy', () {
    late ProviderContainer container;
    final endpoint = File('${files.path}/warp/endpoint.json');

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(() {
        if (endpoint.existsSync()) endpoint.deleteSync();
      });
    });

    test("names the bridge's http port and password while it runs", () async {
      endpoint
        ..createSync(recursive: true)
        ..writeAsStringSync('{"http":"127.0.0.1:4321","auth":"u:p"}');
      expect(await warpProxy(container.read), isNull, reason: 'switched off');
      await container.read(shikooWarpProvider.notifier).set(true);
      expect(await warpProxy(container.read), 'PROXY u:p@127.0.0.1:4321');
      endpoint.deleteSync();
      expect(await warpProxy(container.read), isNull, reason: 'not running');
    });

    test('the switch is kept on this device', () async {
      await container.read(shikooWarpProvider.notifier).set(true);
      final again = ProviderContainer();
      addTearDown(again.dispose);
      expect(again.read(shikooWarpProvider), isFalse);
      await again.read(shikooWarpProvider.notifier).load();
      expect(again.read(shikooWarpProvider), isTrue);
    });
  });

  group('the config FlClash writes for the core', () {
    Future<String> written({
      required WarpRoute route,
      int? profileId = 1,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final core = _Core();
      when(() => core.getConfig(any())).thenAnswer(
        (_) async => {
          'proxies': [
            {'name': 'A', 'type': 'vless', 'server': '1.1.1.1', 'port': 443},
          ],
        },
      );
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          shikooCoreSpecsProvider.overrideWithValue({
            for (final MapEntry(key: core, value: spec)
                in shikooCoreSpecs.entries)
              core: (
                ready: core == ShikooCore.mihomo || core == ShikooCore.xray,
                shape: spec.shape,
                serves: spec.serves,
              ),
          }),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(shikooCoresProvider.notifier)
          .set(ShikooProtocol.vless, ShikooCore.xray);
      await container.read(shikooWarpProvider.notifier).set(true);
      container.read(warpTrialProvider.notifier).set(route.via);
      container.read(warpAppProvider.notifier).set(route.app);
      final made = await container
          .read(setupActionProvider.notifier)
          .getProfile(
            setupState: _setup.copyWith(profileId: profileId),
            patchConfig: const PatchClashConfig(),
          );
      return made.yaml;
    }

    test(
      'sends a server through the bridge only while it is on the route',
      () async {
        final on = await written(route: (via: {'A'}, app: false));
        expect(on, contains('dialer-proxy: "$warpProxyName"'));
        expect(on, contains('$shikooCoreKey: "warp"'));
        expect(
          shikooCoreKey.allMatches(on),
          hasLength(1),
          reason: 'xray gives its server back',
        );

        final off = await written(route: noWarp);
        expect(off, isNot(contains(warpProxyName)));
        expect(off, contains('$shikooCoreKey: "xray"'));
      },
    );

    test(
      'with no service yet, the bridge alone when the app needs it',
      () async {
        expect(await written(route: noWarp, profileId: null), isEmpty);
        expect(
          await written(route: (via: const {}, app: true), profileId: null),
          contains('"$shikooCoreKey":"warp"'),
        );
      },
    );
  });
}
