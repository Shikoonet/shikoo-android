import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h1 of docs/multi-core.md: Xray inside the Go core, behind mihomo.
const ShikooCoreSpec xraySpec = (
  ready: true,
  shape: ShikooShape.behindMihomo,
  serves: _serves,
);

bool _serves(ShikooProtocol protocol, Map<String, dynamic> _) =>
    protocol == ShikooProtocol.vless || protocol == ShikooProtocol.wireguard;
