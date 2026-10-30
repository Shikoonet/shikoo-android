import 'package:fl_clash/shikoo/engine/core_openvpn.dart';
import 'package:fl_clash/shikoo/engine/core_sing_box.dart';
import 'package:fl_clash/shikoo/engine/core_wireguard.dart';
import 'package:fl_clash/shikoo/engine/core_xray.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ShikooCore { mihomo, xray, singBox, wireguard, openvpn }

enum ShikooShape { mihomo, behindMihomo, ownsTunnel }

enum ShikooProtocol { vless, wireguard, openvpn, ssh, other }

enum ShikooPlatform { android, windows }

typedef ShikooChoices = Map<ShikooProtocol, ShikooCore>;

typedef ShikooCoreSpec = ({
  bool ready,
  ShikooShape shape,
  bool Function(ShikooProtocol protocol, Map<String, dynamic> server) serves,
});

typedef ShikooCoreOption = ({ShikooCore core, bool ready});

/// [chosen] and [defaultCore] (what a protocol gets with no pick of the user's) are mihomo while not ready.
/// [carrier] and [defaultCore] follow the current mode, as `markCores` does; [chosen] keeps a pick in proxy mode.
typedef ShikooCoreRow = ({
  ShikooProtocol protocol,
  ShikooCore chosen,
  ShikooCore defaultCore,
  ShikooCore carrier,
  List<ShikooCoreOption> options,
});

/// The one core a protocol runs on: no pick, and no mihomo where it cannot run (Sam, 2026-10-30).
const shikooOnlyCores = <ShikooProtocol, ShikooCore>{
  ShikooProtocol.openvpn: ShikooCore.openvpn,
};

/// The proxy key `shikooCoresRewrite` (core/shikoo_cores.go) reads and removes.
const shikooCoreKey = 'shikoo-core';

const shikooOwnerKey = 'shikoo-owner';

/// `shikooCoresRewrite` writes the name of the core it starts here, in the home folder, and removes it once started.
const shikooCoreStartingFile = 'shikoo-core-starting';

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

/// A ready core whose engine runs on some platforms only; one missing here is ready on every platform.
const shikooReadyOn = <ShikooCore, Set<ShikooPlatform>>{
  ShikooCore.wireguard: {ShikooPlatform.android},
  ShikooCore.openvpn: {ShikooPlatform.android},
};

final shikooReadyOnProvider = Provider<Map<ShikooCore, Set<ShikooPlatform>>>(
  (_) => shikooReadyOn,
);

final shikooCoreSpecsProvider = Provider<Map<ShikooCore, ShikooCoreSpec>>(
  (ref) => readyHere(
    ref.watch(shikooDesktopProvider)
        ? ShikooPlatform.windows
        : ShikooPlatform.android,
    readyOn: ref.watch(shikooReadyOnProvider),
  ),
);

final shikooTunnelProvider = Provider<bool>(
  (ref) =>
      !ref.watch(shikooDesktopProvider) || ref.watch(shikooModeProvider).tun,
);

Map<ShikooCore, ShikooCoreSpec> readyHere(
  ShikooPlatform platform, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
  Map<ShikooCore, Set<ShikooPlatform>> readyOn = shikooReadyOn,
}) => {
  for (final MapEntry(key: core, value: spec) in specs.entries)
    core: readyOn[core]?.contains(platform) ?? true
        ? spec
        : (ready: false, shape: spec.shape, serves: spec.serves),
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

bool offeredHere(
  Map<String, dynamic> server,
  Map<ShikooCore, ShikooCoreSpec> specs, {
  bool tunnel = true,
}) {
  final spec = specs[shikooOnlyCores[protocolOf(server)]];
  return spec == null ||
      spec.ready && (tunnel || spec.shape != ShikooShape.ownsTunnel);
}

/// [tunnel] false is Windows' proxy mode: no tunnel for a core to own, so such a pick falls back to mihomo.
ShikooCore coreFor(
  Map<String, dynamic> server,
  ShikooChoices choices, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
  bool tunnel = true,
}) {
  final protocol = protocolOf(server);
  if (shikooOnlyCores[protocol] case final only?) return only;
  final core = choices[protocol] ?? ShikooCore.mihomo;
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
  bool tunnel = true,
}) {
  ShikooCoreRow row(ShikooProtocol protocol) {
    final server = {'type': protocol.name};
    final defaultCore = coreFor(server, const {}, specs: specs, tunnel: tunnel);
    return (
      protocol: protocol,
      chosen: choices.containsKey(protocol)
          ? coreFor(server, choices, specs: specs)
          : defaultCore,
      defaultCore: defaultCore,
      carrier: coreFor(server, choices, specs: specs, tunnel: tunnel),
      options: [
        for (final MapEntry(key: core, value: spec) in specs.entries)
          if (spec.serves(protocol, const {}) &&
              (shikooOnlyCores[protocol] ?? core) == core)
            (core: core, ready: spec.ready),
      ],
    );
  }

  return [
    for (final protocol in ShikooProtocol.values)
      if (protocol != ShikooProtocol.other &&
          present.contains(protocol) &&
          offeredHere({'type': protocol.name}, specs, tunnel: tunnel))
        row(protocol),
  ];
}

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
  bool tunnel = true,
}) {
  final proxies = config['proxies'];
  if (proxies is! List) return config;
  var marked = false;
  Object? mark(Object? proxy) {
    if (proxy is! Map) return proxy;
    final server = Map<String, dynamic>.from(proxy);
    final core = coreFor(server, choices, specs: specs, tunnel: tunnel);
    final shape = specs[core]!.shape;
    if (shape == ShikooShape.mihomo ||
        !offeredHere(server, specs, tunnel: tunnel)) {
      return proxy;
    }
    marked = true;
    final key = shape == ShikooShape.ownsTunnel
        ? shikooOwnerKey
        : shikooCoreKey;
    return {...server, key: core.name};
  }

  final out = [for (final proxy in proxies) mark(proxy)];
  return marked ? {...config, 'proxies': out} : config;
}
