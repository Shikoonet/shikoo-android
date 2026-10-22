import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/owner.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Locale;
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

class _Core extends Mock implements CoreHandlerInterface {}

ShikooState _state(ShikooCore core, {String? selected = 'Germany 5'}) =>
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
          core: core,
        ),
      ],
    );

ProviderContainer _container(ShikooState state, [_Core? core]) {
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(TestProfiles.new),
      shikooStateProvider.overrideWithValue(state),
      if (core != null)
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the server in use names its core only when that core owns the '
      'tunnel', () {
    expect(_container(_state(ShikooCore.wireguard)).read(shikooOwnerProvider), (
      core: 'wireguard',
      server: 'Germany 5',
      iranDirect: true,
    ));
    expect(
      _container(_state(ShikooCore.mihomo)).read(shikooOwnerProvider),
      isNull,
    );
    expect(
      _container(
        _state(ShikooCore.wireguard, selected: null),
      ).read(shikooOwnerProvider),
      isNull,
    );
  });

  test(
    'VpnOptions carry the owner, and the Iranian-sites switch with it',
    () async {
      await AppLocalizations.load(const Locale('en'));
      tunnelOwner = (ref) => ref.watch(shikooOwnerProvider);
      addTearDown(() => tunnelOwner = null);
      final owner = _container(_state(ShikooCore.wireguard));
      owner.listen(sharedStateProvider, (_, _) {});
      await owner.read(shikooIranDirectProvider.notifier).set(false);
      final options = owner.read(sharedStateProvider).vpnOptions!;
      expect(
        (options.core, options.server, options.iranDirect),
        ('wireguard', 'Germany 5', false),
      );

      final mihomo = _container(_state(ShikooCore.mihomo));
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
    final container = _container(_state(ShikooCore.wireguard), core);
    expect(await container.read(trafficPassesProvider)(), isTrue);
    verify(() => core.asyncTestDelay('', 'Germany 5')).called(1);

    when(() => core.asyncTestDelay(any(), any())).thenAnswer(
      (_) async => const Delay(name: 'Germany 5', url: '', value: -1),
    );
    expect(await container.read(trafficPassesProvider)(), isFalse);
  });

  test('a server the official engine cannot carry stays on mihomo', () {
    final choices = {ShikooProtocol.wireguard: ShikooCore.wireguard};
    final specs = {
      ...shikooCoreSpecs,
      ShikooCore.wireguard: (
        ready: true,
        shape: ShikooShape.ownsTunnel,
        serves: shikooCoreSpecs[ShikooCore.wireguard]!.serves,
      ),
    };
    ShikooCore of(Map<String, dynamic> extra) =>
        coreFor({'type': 'wireguard', ...extra}, choices, specs: specs);
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
