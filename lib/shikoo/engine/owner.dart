import 'package:fl_clash/providers/state.dart' show TunnelOwner;
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The owner core picked for the server in use, for VpnOptions (docs/multi-core.md §4). The pick, not the core the
/// state shows: that turns to mihomo while the engine does not carry the server, and VpnOptions must not follow it.
/// Set for the rest of a connection whose engine died twice in a minute: mihomo carries it (Sam, 2026-10-23).
final shikooOwnerHeldOffProvider = NotifierProvider<ShikooCell<bool>, bool>(
  () => ShikooCell(false),
);

final shikooOwnerProvider = Provider<TunnelOwner?>((ref) {
  if (ref.watch(shikooOwnerHeldOffProvider)) return null;
  final (:server, :type) = ref.watch(
    shikooStateProvider.select(
      (state) => (server: state.selected, type: state.selectedServer?.type),
    ),
  );
  if (server == null || type == null) return null;
  final specs = ref.watch(shikooCoreSpecsProvider);
  final core = coreFor(
    ref.watch(shikooSelectedSourceProvider) ?? {'type': type},
    ref.watch(shikooCoresProvider),
    specs: specs,
    tunnel: ref.watch(shikooTunnelProvider),
  );
  if (!ownsTunnel(core, specs)) return null;
  return (
    core: core.name,
    server: server,
    iranDirect: ref.watch(shikooIranDirectProvider),
  );
});

bool ownsTunnel(ShikooCore core, Map<ShikooCore, ShikooCoreSpec> specs) =>
    specs[core]!.shape == ShikooShape.ownsTunnel;
