import 'dart:io' show InternetAddress;

import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h4 of docs/multi-core.md: sing-box behind mihomo.
const ShikooCoreSpec singBoxSpec = (
  ready: true,
  shape: ShikooShape.behindMihomo,
  serves: _serves,
);

/// The rules of `singBoxServes` (core/shikoo_singbox.go); core/testdata/sing_box_serves.json holds both to them.
/// sing-box 1.14.3 has no XHTTP transport and no VLESS `encryption` field.
const _keys = {
  ShikooProtocol.vless:
      'uuid flow tls alpn packet-addr xudp packet-encoding encryption network '
      'reality-opts ws-opts grpc-opts skip-cert-verify servername '
      'client-fingerprint',
  ShikooProtocol.wireguard:
      'ip ipv6 private-key public-key pre-shared-key reserved allowed-ips mtu '
      'persistent-keepalive peers remote-dns-resolve dns',
  ShikooProtocol.openvpn:
      'proto dev cipher data-ciphers data-ciphers-fallback auth comp-lzo ca '
      'cert key tls-auth key-direction tls-crypt tls-crypt-v2 username '
      'password ping ping-restart mtu remote-dns-resolve dns',
  ShikooProtocol.ssh:
      'username password private-key private-key-passphrase host-key '
      'host-key-algorithms',
};

const _optKeys = {
  'reality-opts': 'public-key short-id',
  'ws-opts':
      'path headers max-early-data early-data-header-name v2ray-http-upgrade',
  'grpc-opts': 'grpc-service-name',
};

const _fingerprints = 'none chrome firefox safari ios android edge 360 qq';

final _wireGuardKey = RegExp(r'^[A-Za-z0-9+/]{43}=$');

/// `singBoxTunnelDNS`: the first of the server's dns is an address, which sing-box asks through the server.
bool _tunnelDns(Map<String, dynamic> server) =>
    server['dns'] is List &&
    (server['dns'] as List).isNotEmpty &&
    InternetAddress.tryParse('${(server['dns'] as List).first}') != null;

bool _serves(ShikooProtocol protocol, Map<String, dynamic> server) {
  final keys = '${_keys[protocol]} name type server port udp'.split(' ');
  if (!_keys.containsKey(protocol) ||
      !server.keys.every(keys.contains) ||
      server['remote-dns-resolve'] == true &&
          (protocol != ShikooProtocol.wireguard || !_tunnelDns(server))) {
    return false;
  }
  for (final MapEntry(:key, :value) in server.entries) {
    final inner = (_optKeys[key] ?? '').split(' ');
    if (value is Map && !value.keys.every(inner.contains)) {
      return false;
    }
  }
  bool oneOf(Object? value, String values) =>
      ' $values'.split(' ').contains('${value ?? ''}');
  bool wireGuardKey(Object? value) =>
      value == null || _wireGuardKey.hasMatch('$value');
  Map<dynamic, dynamic> opts(String key) =>
      server[key] is Map ? server[key] as Map : const {};
  final ws = opts('ws-opts');
  final peers = server['peers'] is List && (server['peers'] as List).isNotEmpty
      ? server['peers'] as List
      : [server];
  final mtu = int.tryParse('${server['mtu']}');
  final mtuFits =
      server['mtu'] == null ||
      mtu != null && (mtu == 0 || mtu >= 68 && mtu <= 65535);
  return switch (protocol) {
    ShikooProtocol.vless =>
      oneOf(server['encryption'], 'none') &&
          oneOf(server['network'], 'tcp ws grpc') &&
          oneOf(server['flow'], 'xtls-rprx-vision') &&
          oneOf(server['client-fingerprint'], _fingerprints) &&
          !(ws['v2ray-http-upgrade'] == true &&
              ('${ws['path']}'.contains('?') ||
                  !oneOf(ws['max-early-data'], '0'))),
    ShikooProtocol.wireguard =>
      wireGuardKey(server['private-key']) &&
          peers.every(
            (peer) =>
                peer is Map &&
                wireGuardKey(peer['public-key']) &&
                (oneOf(peer['pre-shared-key'], '') ||
                    wireGuardKey(peer['pre-shared-key'])),
          ) &&
          mtuFits,
    ShikooProtocol.openvpn => oneOf(server['dev'], 'tun') && mtuFits,
    _ => true,
  };
}
