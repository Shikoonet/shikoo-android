import 'package:fl_clash/providers/state.dart' show TunnelOwner;
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final shikooOwnerHeldOffProvider = NotifierProvider<ShikooCell<bool>, bool>(
  () => ShikooCell(false),
);

/// The pick, not the core the state shows, which turns to mihomo while the engine does not carry the server.
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
