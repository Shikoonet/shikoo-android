import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h2 of docs/multi-core.md: the official WireGuard engine, owning the tunnel.
const ShikooCoreSpec wireguardSpec = (
  ready: true,
  shape: ShikooShape.ownsTunnel,
  serves: _serves,
);

/// AmneziaWG, WARP's reserved bytes and a dialer chain are mihomo's alone (core/shikoo_wg.go refuses them).
bool _serves(ShikooProtocol protocol, Map<String, dynamic> server) =>
    protocol == ShikooProtocol.wireguard &&
    !server.containsKey('amnezia-wg-option') &&
    !server.containsKey('reserved') &&
    !server.containsKey('dialer-proxy');
