import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/owner.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Locale;
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

class _Core extends Mock implements CoreHandlerInterface {}

const _germany = {'name': 'Germany 5', 'type': 'wireguard'};

/// [shown] is the core the state shows for the server, mihomo while the engine does not carry it.
ShikooState _state(ShikooCore shown, {String? selected = 'Germany 5'}) =>
    ShikooState(
      connection: ShikooConnection.on,
      connectedFor: Duration.zero,
      isTV: false,
      selected: selected,
      servers: [
        ShikooServer(
          name: 'Germany 5',
          type: 'WireGuard',
          protocol: ShikooProtocol.wireguard,
          core: shown,
        ),
      ],
    );

Future<ProviderContainer> _container(
  ShikooState state, {
  ShikooCore? pick,
  bool desktop = false,
  _Core? core,
}) async {
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(TestProfiles.new),
      shikooStateProvider.overrideWithValue(state),
      shikooSelectedSourceProvider.overrideWithValue(_germany),
      shikooDesktopProvider.overrideWithValue(desktop),
      if (core != null)
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
    ],
  );
  addTearDown(container.dispose);
  if (pick != null) {
    await container
        .read(shikooCoresProvider.notifier)
        .set(ShikooProtocol.wireguard, pick);
  }
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('VpnOptions ask for the picked owner core, even while the state shows '
      'the server on mihomo because the engine does not carry it', () async {
    const wanted = (core: 'wireguard', server: 'Germany 5', iranDirect: true);
    for (final shown in [ShikooCore.wireguard, ShikooCore.mihomo]) {
      final container = await _container(
        _state(shown),
        pick: ShikooCore.wireguard,
      );
      expect(container.read(shikooOwnerProvider), wanted, reason: '$shown');
    }
    expect(
      (await _container(_state(ShikooCore.mihomo))).read(shikooOwnerProvider),
      isNull,
      reason: 'no pick: mihomo',
    );
    expect(
      (await _container(
        _state(ShikooCore.wireguard, selected: null),
        pick: ShikooCore.wireguard,
      )).read(shikooOwnerProvider),
      isNull,
    );
  });

  test('the official engine is ready on Android only, so Windows keeps its '
      'servers on mihomo and asks for no owner', () async {
    final android = await _container(
      _state(ShikooCore.wireguard),
      pick: ShikooCore.wireguard,
    );
    final windows = await _container(
      _state(ShikooCore.wireguard),
      pick: ShikooCore.wireguard,
      desktop: true,
    );
    expect(
      android.read(shikooCoreSpecsProvider)[ShikooCore.wireguard]!.ready,
      isTrue,
    );
    expect(
      windows.read(shikooCoreSpecsProvider)[ShikooCore.wireguard]!.ready,
      isFalse,
    );
    expect(windows.read(shikooOwnerProvider), isNull);
  });

  test(
    'VpnOptions carry the owner, and the Iranian-sites switch with it',
    () async {
      await AppLocalizations.load(const Locale('en'));
      tunnelOwner = (ref) => ref.watch(shikooOwnerProvider);
      addTearDown(() => tunnelOwner = null);
      final owner = await _container(
        _state(ShikooCore.wireguard),
        pick: ShikooCore.wireguard,
      );
      owner.listen(sharedStateProvider, (_, _) {});
      await owner.read(shikooIranDirectProvider.notifier).set(false);
      final options = owner.read(sharedStateProvider).vpnOptions!;
      expect(
        (options.core, options.server, options.iranDirect),
        ('wireguard', 'Germany 5', false),
      );

      final mihomo = await _container(_state(ShikooCore.mihomo));
      expect(
        mihomo.read(sharedStateProvider).vpnOptions!.toJson(),
        containsPair('core', ''),
      );
    },
  );

  test("an owner's traffic is its server's handshake, not the app's own IP "
      'lookup, which goes around that VPN', () async {
    final core = _Core();
    when(() => core.asyncTestDelay(any(), any())).thenAnswer(
      (_) async => const Delay(name: 'Germany 5', url: '', value: 41),
    );
    final container = await _container(
      _state(ShikooCore.wireguard),
      core: core,
    );
    expect(await container.read(trafficPassesProvider)(), isTrue);
    verify(() => core.asyncTestDelay('', 'Germany 5')).called(1);

    when(() => core.asyncTestDelay(any(), any())).thenAnswer(
      (_) async => const Delay(name: 'Germany 5', url: '', value: -1),
    );
    expect(await container.read(trafficPassesProvider)(), isFalse);
  });

  test('a server the official engine cannot carry stays on mihomo', () {
    final choices = {ShikooProtocol.wireguard: ShikooCore.wireguard};
    ShikooCore of(Map<String, dynamic> extra) =>
        coreFor({'type': 'wireguard', ...extra}, choices);
    expect(of({}), ShikooCore.wireguard);
    expect(
      of({
        'reserved': [1, 2, 3],
      }),
      ShikooCore.mihomo,
    );
    expect(
      of({
        'amnezia-wg-option': {'jc': 4},
      }),
      ShikooCore.mihomo,
    );
    expect(of({'dialer-proxy': 'other'}), ShikooCore.mihomo);
  });
}
