import 'package:fl_clash/shikoo/engine/core_openvpn.dart';
import 'package:fl_clash/shikoo/engine/core_sing_box.dart';
import 'package:fl_clash/shikoo/engine/core_wireguard.dart';
import 'package:fl_clash/shikoo/engine/core_xray.dart';

enum ShikooCore { mihomo, xray, singBox, wireguard, openvpn }

enum ShikooShape { mihomo, behindMihomo, ownsTunnel }

enum ShikooProtocol { vless, wireguard, openvpn, ssh, other }

typedef ShikooChoices = Map<ShikooProtocol, ShikooCore>;

typedef ShikooCoreSpec = ({
  bool ready,
  ShikooShape shape,
  bool Function(ShikooProtocol protocol, Map<String, dynamic> server) serves,
});

typedef ShikooCoreOption = ({ShikooCore core, bool ready});

/// [chosen] is mihomo while the user's pick is not ready in this build.
typedef ShikooCoreRow = ({
  ShikooProtocol protocol,
  ShikooCore chosen,
  List<ShikooCoreOption> options,
});

/// The proxy key `shikooCoresRewrite` (core/shikoo_cores.go) reads and removes.
const shikooCoreKey = 'shikoo-core';

const ShikooCoreSpec _mihomo = (
  ready: true,
  shape: ShikooShape.mihomo,
  serves: _any,
);

bool _any(ShikooProtocol _, Map<String, dynamic> _) => true;

const shikooCoreSpecs = <ShikooCore, ShikooCoreSpec>{
  ShikooCore.mihomo: _mihomo,
  ShikooCore.xray: xraySpec,
  ShikooCore.singBox: singBoxSpec,
  ShikooCore.wireguard: wireguardSpec,
  ShikooCore.openvpn: openvpnSpec,
};

/// Read from the profile's own mapping: mihomo names a server it handed to Xray `Socks5`.
ShikooProtocol protocolOf(Map<String, dynamic> server) =>
    switch ('${server['type']}'.toLowerCase()) {
      'vless' => ShikooProtocol.vless,
      'wireguard' => ShikooProtocol.wireguard,
      'openvpn' => ShikooProtocol.openvpn,
      'ssh' => ShikooProtocol.ssh,
      _ => ShikooProtocol.other,
    };

/// [tunnel] false is Windows' proxy mode: no tunnel for a core to own, so such a pick falls back to mihomo.
ShikooCore coreFor(
  Map<String, dynamic> server,
  ShikooChoices choices, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
  bool tunnel = true,
}) {
  final protocol = protocolOf(server);
  final core = choices[protocol] ?? ShikooCore.mihomo;
  final spec = specs[core]!;
  return spec.ready &&
          spec.serves(protocol, server) &&
          (tunnel || spec.shape != ShikooShape.ownsTunnel)
      ? core
      : ShikooCore.mihomo;
}

/// Go replaces a server it handed to a core, so one it left to mihomo still has its own type.
ShikooCore runningCore(
  Map<String, dynamic>? source,
  String runningType,
  ShikooChoices choices, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
  bool tunnel = true,
}) {
  final server = source ?? {'type': runningType};
  final core = coreFor(server, choices, specs: specs, tunnel: tunnel);
  if (specs[core]!.shape != ShikooShape.behindMihomo) return core;
  return '${server['type']}'.toLowerCase() == runningType.toLowerCase()
      ? ShikooCore.mihomo
      : core;
}

List<ShikooCoreRow> coreRows(
  Set<ShikooProtocol> present,
  ShikooChoices choices, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
}) => [
  for (final protocol in ShikooProtocol.values)
    if (protocol != ShikooProtocol.other && present.contains(protocol))
      (
        protocol: protocol,
        chosen: coreFor({'type': protocol.name}, choices, specs: specs),
        options: [
          for (final MapEntry(key: core, value: spec) in specs.entries)
            if (spec.serves(protocol, const {}))
              (core: core, ready: spec.ready),
        ],
      ),
];

/// A change of server or core takes the tunnel down only when this changes: an owner core holds it per server.
String tunnelKey(
  ShikooCore core,
  String server, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
}) => specs[core]!.shape == ShikooShape.ownsTunnel
    ? '${core.name}/$server'
    : ShikooCore.mihomo.name;

Map<String, dynamic> markCores(
  Map<String, dynamic> config,
  ShikooChoices choices, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
}) {
  final proxies = config['proxies'];
  if (proxies is! List) return config;
  var marked = false;
  Object? mark(Object? proxy) {
    if (proxy is! Map) return proxy;
    final server = Map<String, dynamic>.from(proxy);
    final core = coreFor(server, choices, specs: specs);
    if (specs[core]!.shape != ShikooShape.behindMihomo) return proxy;
    marked = true;
    return {...server, shikooCoreKey: core.name};
  }

  final out = [for (final proxy in proxies) mark(proxy)];
  return marked ? {...config, 'proxies': out} : config;
}
