import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h3 of docs/multi-core.md: the official OpenVPN 3 engine, owning the tunnel.
const ShikooCoreSpec openvpnSpec = (
  ready: true,
  shape: ShikooShape.ownsTunnel,
  serves: _serves,
);

/// How long the official engine waits for its server before the start fails: OpenVpn.kt's CONNECT_SECONDS.
const openvpnConnectLimit = Duration(seconds: 20);

/// OpenVPN's only core: a dialer chain or extra peer info, which core/shikoo_ovpn.go refuses, fails its start.
bool _serves(ShikooProtocol protocol, Map<String, dynamic> _) =>
    protocol == ShikooProtocol.openvpn;
