import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h3 of docs/multi-core.md: the official OpenVPN 3 engine, owning the tunnel.
const ShikooCoreSpec openvpnSpec = (
  ready: false,
  shape: ShikooShape.ownsTunnel,
  serves: _serves,
);

bool _serves(ShikooProtocol protocol, Map<String, dynamic> _) =>
    protocol == ShikooProtocol.openvpn;
