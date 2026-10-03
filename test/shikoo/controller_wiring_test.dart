import 'dart:async';

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
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

class _Setup extends SetupAction {
  final runs = <bool>[];

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    runs.add(running);
    return true;
  }
}

const _version = 'V3.7.9 🆔 : (user123) 📊 (67 GB) ⏰ (23)';

void main() {
  test('connect before any answer waits, then starts on the first server that '
      'answered, never row 1', () async {
    SharedPreferences.setMockInitialValues({});
    final core = _Core();
    final netherlands = Completer<void>();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((call) async {
      final name = call.positionalArguments[1] as String;
      if (name != 'هلند ۱') return Delay(name: name, url: '', value: -1);
      await netherlands.future;
      return Delay(name: name, url: '', value: 90);
    });
    final profile = Profile.normal(url: 'https://panel.invalid/sub');
    final proxies = _Proxies();
    final setup = _Setup();
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        proxiesActionProvider.overrideWith(() => proxies),
        setupActionProvider.overrideWith(() => setup),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
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
}
