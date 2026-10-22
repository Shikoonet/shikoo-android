import 'dart:io' show InternetAddress, InternetAddressType;

import 'package:fl_clash/shikoo/engine/cores.dart';

/// Package h1 of docs/multi-core.md: Xray inside the Go core, behind mihomo.
const ShikooCoreSpec xraySpec = (
  ready: true,
  shape: ShikooShape.behindMihomo,
  serves: _serves,
);

/// `xrayKeys` and the refusals of core/shikoo_xray.go, Xray's own among them;
/// core/testdata/xray_serves.json holds both to them.
const _keys = {
  ShikooProtocol.vless:
      'uuid flow tls alpn servername client-fingerprint reality-opts network '
      'ws-opts grpc-opts xhttp-opts encryption packet-encoding xudp '
      'packet-addr skip-cert-verify smux',
  ShikooProtocol.wireguard:
      'ip ipv6 private-key public-key pre-shared-key reserved allowed-ips mtu '
      'persistent-keepalive dns remote-dns-resolve',
};

const _fingerprints =
    'none chrome firefox safari ios android edge 360 qq random randomized';

bool _serves(ShikooProtocol protocol, Map<String, dynamic> server) {
  final keys = '${_keys[protocol]} name type server port udp'.split(' ');
  if (!_keys.containsKey(protocol) || !server.keys.every(keys.contains)) {
    return false;
  }
  return protocol == ShikooProtocol.vless ? _vless(server) : _wireguard(server);
}

bool _vless(Map<String, dynamic> server) {
  bool oneOf(String key, String values) =>
      ' $values'.split(' ').contains(server[key] ?? '');
  final ws = server['ws-opts'] as Map? ?? const {};
  final xhttp = server['xhttp-opts'] as Map? ?? const {};
  final tls = server['tls'] == true;
  final reality = '${(server['reality-opts'] as Map?)?['public-key'] ?? ''}';
  final encrypted = !oneOf('encryption', 'none');
  final host = server['server'];
  return server['skip-cert-verify'] != true &&
      (server['smux'] as Map?)?['enabled'] != true &&
      oneOf('network', 'tcp ws grpc xhttp') &&
      oneOf('flow', 'xtls-rprx-vision xtls-rprx-vision-udp443') &&
      oneOf('client-fingerprint', _fingerprints) &&
      (!encrypted ||
          '${server['encryption']}'.startsWith('mlkem768x25519plus.')) &&
      !(tls && reality.isNotEmpty && server['network'] == 'ws') &&
      !(server['network'] == 'ws' &&
          (ws['max-early-data'] as num? ?? 0) > 0 &&
          ws['early-data-header-name'] != 'Sec-WebSocket-Protocol') &&
      !xhttp.containsKey('download-settings') &&
      !_fromZero(xhttp['sc-max-each-post-bytes']) &&
      (tls || encrypted || host is! String || _private(host));
}

bool _wireguard(Map<String, dynamic> server) {
  bool ip(Object? value) => InternetAddress.tryParse('$value') != null;
  final reserved = server['reserved'];
  final dns = server['dns'];
  return (reserved == null || reserved is List && reserved.length == 3) &&
      (dns == null || dns is List && dns.every(ip)) &&
      [
        server['ip'],
        server['ipv6'],
      ].every((address) => address == null || ip('$address'.split('/').first));
}

/// Xray panics at its first dial on a post size whose range starts at 0.
bool _fromZero(Object? range) {
  final ends = '${range ?? ''}'.split('-').map(int.tryParse).toList();
  if (ends.contains(null)) return false;
  final values = ends.cast<int>()..sort();
  return values.first <= 0 && values.last > 0;
}

/// Xray carries VLESS in the clear only to a private address.
bool _private(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null) return false;
  final b = address.rawAddress;
  return address.isLoopback ||
      address.isLinkLocal ||
      (address.type == InternetAddressType.IPv4
          ? b[0] == 10 ||
                (b[0] == 172 && b[1] & 0xf0 == 16) ||
                (b[0] == 192 && b[1] == 168)
          : b[0] & 0xfe == 0xfc);
}
