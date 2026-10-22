import 'package:fl_clash/shikoo/engine/core_openvpn.dart';
import 'package:fl_clash/shikoo/engine/core_sing_box.dart';
import 'package:fl_clash/shikoo/engine/core_wireguard.dart';
import 'package:fl_clash/shikoo/engine/core_xray.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// [chosen] and [defaultCore] (what a protocol gets with no pick of the user's) are mihomo while not ready.
typedef ShikooCoreRow = ({
  ShikooProtocol protocol,
  ShikooCore chosen,
  ShikooCore defaultCore,
  List<ShikooCoreOption> options,
});

/// A protocol not listed defaults to mihomo. OpenVPN: Sam, 2026-10-23.
const shikooDefaultCores = <ShikooProtocol, ShikooCore>{
  ShikooProtocol.openvpn: ShikooCore.openvpn,
};

/// The proxy key `shikooCoresRewrite` (core/shikoo_cores.go) reads and removes.
const shikooCoreKey = 'shikoo-core';

const shikooOwnerKey = 'shikoo-owner';

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

final shikooCoreSpecsProvider = Provider<Map<ShikooCore, ShikooCoreSpec>>(
  (_) => shikooCoreSpecs,
);

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
  final core =
      choices[protocol] ?? shikooDefaultCores[protocol] ?? ShikooCore.mihomo;
  final spec = specs[core]!;
  return spec.ready &&
          spec.serves(protocol, server) &&
          (tunnel || spec.shape != ShikooShape.ownsTunnel)
      ? core
      : ShikooCore.mihomo;
}

/// Go swaps a server it hands behind mihomo, so a kept type means mihomo; [carried]: the owner Go reports ('' none).
ShikooCore runningCore(
  Map<String, dynamic>? source,
  String runningType,
  ShikooChoices choices, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
  bool tunnel = true,
  String? carried,
}) {
  final server = source ?? {'type': runningType};
  final core = coreFor(server, choices, specs: specs, tunnel: tunnel);
  return switch (specs[core]!.shape) {
    ShikooShape.mihomo => core,
    ShikooShape.ownsTunnel =>
      carried == null || carried == core.name ? core : ShikooCore.mihomo,
    ShikooShape.behindMihomo =>
      '${server['type']}'.toLowerCase() == runningType.toLowerCase()
          ? ShikooCore.mihomo
          : core,
  };
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
        defaultCore: coreFor({'type': protocol.name}, const {}, specs: specs),
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
    final shape = specs[core]!.shape;
    if (shape == ShikooShape.mihomo) return proxy;
    marked = true;
    final key = shape == ShikooShape.ownsTunnel
        ? shikooOwnerKey
        : shikooCoreKey;
    return {...server, key: core.name};
  }

  final out = [for (final proxy in proxies) mark(proxy)];
  return marked ? {...config, 'proxies': out} : config;
}
