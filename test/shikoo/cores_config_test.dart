import 'dart:io';

import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/owner.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Core extends Mock implements CoreHandlerInterface {}

void main() {
  setUpAll(() {
    final files = Directory.systemTemp.createTempSync('shikoo-cores-config-');
    AppPath.supportDirectory = AppPath.temporaryDirectory =
        AppPath.cacheDirectory = () async => files;
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: '0.8.98',
      buildNumber: '1',
    );
  });

  /// The yaml FlClash writes for the core, with xray picked for VLESS and the official engine for WireGuard.
  Future<String> written({
    bool windowsProxyMode = false,
    bool heldOff = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final core = _Core();
    when(() => core.getConfig(any())).thenAnswer(
      (_) async => {
        'proxies': [
          {
            'name': 'A',
            'type': 'vless',
            'server': '1.1.1.1',
            'port': 443,
            'tls': true,
          },
          {'name': 'W', 'type': 'wireguard', 'server': '1.1.1.2', 'port': 1},
        ],
      },
    );
    final container = ProviderContainer(
      overrides: [
        shikooDesktopProvider.overrideWithValue(windowsProxyMode),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        shikooCoreSpecsProvider.overrideWithValue({
          for (final MapEntry(key: core, value: spec)
              in shikooCoreSpecs.entries)
            core: (
              ready: const {
                ShikooCore.mihomo,
                ShikooCore.xray,
                ShikooCore.wireguard,
              }.contains(core),
              shape: spec.shape,
              serves: spec.serves,
            ),
        }),
      ],
    );
    addTearDown(container.dispose);
    final picks = container.read(shikooCoresProvider.notifier);
    await picks.set(ShikooProtocol.vless, ShikooCore.xray);
    await picks.set(ShikooProtocol.wireguard, ShikooCore.wireguard);
    if (windowsProxyMode) {
      await container.read(shikooModeProvider.notifier).save(ShikooMode.proxy);
    }
    container.read(shikooOwnerHeldOffProvider.notifier).set(heldOff);

    final made = await container
        .read(setupActionProvider.notifier)
        .getProfile(
          setupState: const SetupState(
            profileId: 1,
            profileLastUpdateDate: null,
            overwriteType: OverwriteType.standard,
            rules: [],
            proxyGroups: [],
            addedRules: [],
            script: null,
            overrideDns: false,
            dns: defaultDns,
          ),
          patchConfig: const PatchClashConfig(),
        );
    return made.yaml;
  }

  test('the config FlClash writes for the core marks the servers a ready core '
      'behind mihomo carries, and those an owner core takes, apart', () async {
    final yaml = await written();

    expect(yaml, contains('$shikooCoreKey: "xray"'));
    expect(yaml, contains('$shikooOwnerKey: "wireguard"'));
    expect(
      [shikooCoreKey, shikooOwnerKey].map((key) => key.allMatches(yaml)),
      everyElement(hasLength(1)),
      reason: 'one server each',
    );
  });

  test("in Windows' proxy mode the owner core's server goes unmarked: mihomo "
      'carries it', () async {
    final yaml = await written(windowsProxyMode: true);

    expect(yaml, isNot(contains(shikooOwnerKey)));
    expect(yaml, contains('$shikooCoreKey: "xray"'));
  });

  test("after an engine died twice the owner core's server goes unmarked, so "
      'no apply until the disconnect (an Iranian-switch tap, a subscription '
      'update) hands it back to the engine on Windows', () async {
    final yaml = await written(heldOff: true);

    expect(yaml, isNot(contains(shikooOwnerKey)));
    expect(yaml, contains('$shikooCoreKey: "xray"'));
  });
}
