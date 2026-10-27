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
      ],
      'mode': 'rule',
    };

    test('off, the config is the same object, untouched', () {
      expect(markWarp(config, on: false), same(config));
    });

    test('on, every server leaves through the bridge, a chain from its first '
        'hop, and a core behind mihomo gives its server back; a direct one '
        'stays direct, never free WARP', () {
      final marked = markWarp(config, on: true);
      final proxies = (marked['proxies'] as List).cast<Map>();
      expect(marked['mode'], 'rule');
      expect(proxies.map((p) => p['dialer-proxy']), [
        warpProxyName,
        warpProxyName,
        'B',
        null,
        null,
      ]);
      expect(proxies[3], {'name': 'D', 'type': 'Direct'});
      expect(proxies[0].containsKey('shikoo-core'), isFalse);
      expect(proxies[1]['shikoo-owner'], 'wireguard');
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

    test('a config without servers still gets the bridge', () {
      expect(markWarp({}, on: true)['proxies'], hasLength(1));
    });
  });

  test('with no service the core gets the bridge alone, or nothing', () {
    expect(warpOnlyProfile(on: false), (yaml: '', md5: ''));
    final only = warpOnlyProfile(on: true);
    expect(json.decode(only.yaml), {
      'proxies': [markWarp({}, on: true)['proxies'][0]],
    });
    expect(only.md5, only.yaml.toMd5());
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
    Future<String> written({required bool bridge, int? profileId = 1}) async {
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
      await container.read(shikooWarpProvider.notifier).set(bridge);
      final made = await container
          .read(setupActionProvider.notifier)
          .getProfile(
            setupState: _setup.copyWith(profileId: profileId),
            patchConfig: const PatchClashConfig(),
          );
      return made.yaml;
    }

    test('sends the servers through the bridge only while it is on', () async {
      final on = await written(bridge: true);
      expect(on, contains('dialer-proxy: "$warpProxyName"'));
      expect(on, contains('$shikooCoreKey: "warp"'));
      expect(
        shikooCoreKey.allMatches(on),
        hasLength(1),
        reason: 'xray gives its server back',
      );

      final off = await written(bridge: false);
      expect(off, isNot(contains(warpProxyName)));
      expect(off, contains('$shikooCoreKey: "xray"'));
    });

    test('with no service yet, the bridge alone while it is on', () async {
      expect(await written(bridge: false, profileId: null), isEmpty);
      expect(
        await written(bridge: true, profileId: null),
        contains('"$shikooCoreKey":"warp"'),
      );
    });
  });
}
