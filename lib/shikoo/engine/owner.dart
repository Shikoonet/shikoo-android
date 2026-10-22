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
  if (server == null ||
      core == null ||
      !ownsTunnel(core, ref.watch(shikooCoreSpecsProvider))) {
    return null;
  }
  return (
    core: core.name,
    server: server,
    iranDirect: ref.watch(shikooIranDirectProvider),
  );
});

bool ownsTunnel(ShikooCore core, Map<ShikooCore, ShikooCoreSpec> specs) =>
    specs[core]!.shape == ShikooShape.ownsTunnel;
