import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h4 of docs/multi-core.md: sing-box behind mihomo.
const ShikooCoreSpec singBoxSpec = (
  ready: false,
  shape: ShikooShape.behindMihomo,
  serves: _serves,
);

/// sing-box 1.14.3 has no XHTTP transport and no VLESS `encryption` field.
bool _serves(ShikooProtocol protocol, Map<String, dynamic> server) =>
    switch (protocol) {
      ShikooProtocol.vless =>
        server['network'] != 'xhttp' &&
            const {null, '', 'none'}.contains(server['encryption']),
      ShikooProtocol.other => false,
      _ => true,
    };
