import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h3 of docs/multi-core.md: the official OpenVPN 3 engine, owning the tunnel.
const ShikooCoreSpec openvpnSpec = (
  ready: true,
  shape: ShikooShape.ownsTunnel,
  serves: _serves,
);

/// A dialer chain and extra peer info are mihomo's alone (core/shikoo_ovpn.go refuses them).
bool _serves(ShikooProtocol protocol, Map<String, dynamic> server) =>
    protocol == ShikooProtocol.openvpn &&
    !server.containsKey('dialer-proxy') &&
    !server.containsKey('peer-info');
