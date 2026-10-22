import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/providers/state.dart' show TunnelOwner;
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The owner core of the server in use, for VpnOptions (docs/multi-core.md §4); null while mihomo holds the tunnel.
final shikooOwnerProvider = Provider<TunnelOwner?>((ref) {
  final (:server, :core) = ref.watch(
    shikooStateProvider.select(
      (state) => (server: state.selected, core: state.selectedServer?.core),
    ),
  );
  final down = ref.watch(shikooOwnerDownProvider);
  final picked = down != null && down.server == server ? down.core : core;
  if (server == null ||
      picked == null ||
      !ownsTunnel(picked, ref.watch(shikooCoreSpecsProvider))) {
    return null;
  }
  return (
    core: picked.name,
    server: server,
    iranDirect: ref.watch(shikooIranDirectProvider),
  );
});

bool ownsTunnel(ShikooCore core, Map<ShikooCore, ShikooCoreSpec> specs) =>
    specs[core]!.shape == ShikooShape.ownsTunnel;

typedef ShikooOwnerDown = ({String server, ShikooCore core});

/// An owner engine that did not start this connection: mihomo carries the server, the pick stays (Sam, 2026-10-23).
final shikooOwnerDownProvider =
    NotifierProvider<ShikooOwnerDownNotifier, ShikooOwnerDown?>(
      ShikooOwnerDownNotifier.new,
    );

class ShikooOwnerDownNotifier extends Notifier<ShikooOwnerDown?> {
  @override
  ShikooOwnerDown? build() => null;

  void set(ShikooOwnerDown? down) => state = down;
}

final shikooOwnerQuery = '${String.fromCharCode(0)}shikoo-owner';

Future<String?> ownerCarries(CoreController core) async =>
    (await core.getDelay('', shikooOwnerQuery))?.name;
