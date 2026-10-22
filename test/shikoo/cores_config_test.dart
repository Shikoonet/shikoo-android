import 'dart:io';

import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
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

  test('the config FlClash writes for the core marks the servers a ready core '
      'behind mihomo carries, and no other', () async {
    SharedPreferences.setMockInitialValues({});
    final core = _Core();
    when(() => core.getConfig(any())).thenAnswer(
      (_) async => {
        'proxies': [
          {'name': 'A', 'type': 'vless', 'server': '1.1.1.1', 'port': 443},
          {'name': 'W', 'type': 'wireguard', 'server': '1.1.1.2', 'port': 1},
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

    expect(made.yaml, contains('$shikooCoreKey: "xray"'));
    expect(
      shikooCoreKey.allMatches(made.yaml),
      hasLength(1),
      reason: 'WireGuard stays on mihomo',
    );
  });
}
