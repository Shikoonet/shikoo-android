import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h2 of docs/multi-core.md: the official WireGuard engine, owning the tunnel.
const ShikooCoreSpec wireguardSpec = (
  ready: false,
  shape: ShikooShape.ownsTunnel,
  serves: _serves,
);

bool _serves(ShikooProtocol protocol, Map<String, dynamic> _) =>
    protocol == ShikooProtocol.wireguard;
