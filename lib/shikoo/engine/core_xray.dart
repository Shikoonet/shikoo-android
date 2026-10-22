import 'dart:convert' show base64Url;
import 'dart:io' show InternetAddress, InternetAddressType;
import 'dart:math' show max;

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

const _int32 = 2147483647;

bool _serves(ShikooProtocol protocol, Map<String, dynamic> server) {
  final keys = '${_keys[protocol]} name type server port udp'.split(' ');
  if (!_keys.containsKey(protocol) ||
      !server.keys.every(keys.contains) ||
      !_number(server['port'], 1, 65535)) {
    return false;
  }
  return protocol == ShikooProtocol.vless ? _vless(server) : _wireguard(server);
}

bool _oneOf(Map server, String key, String values) =>
    ' $values'.split(' ').contains(server[key] ?? '');

bool _vless(Map<String, dynamic> server) {
  final ws = server['ws-opts'] as Map? ?? const {};
  final tls = server['tls'] == true;
  final reality = '${(server['reality-opts'] as Map?)?['public-key'] ?? ''}';
  final encrypted = !_oneOf(server, 'encryption', 'none');
  final host = server['server'];
  return server['skip-cert-verify'] != true &&
      (server['smux'] as Map?)?['enabled'] != true &&
      _oneOf(server, 'network', 'tcp ws grpc xhttp') &&
      _oneOf(server, 'flow', 'xtls-rprx-vision xtls-rprx-vision-udp443') &&
      _oneOf(server, 'client-fingerprint', _fingerprints) &&
      _encryption(server['encryption']) &&
      !(tls && reality.isNotEmpty && server['network'] == 'ws') &&
      !(server['network'] == 'ws' &&
          (ws['max-early-data'] as num? ?? 0) > 0 &&
          ws['early-data-header-name'] != 'Sec-WebSocket-Protocol') &&
      _xhttp(server['xhttp-opts'] as Map? ?? const {}) &&
      (tls || encrypted || host is! String || _private(host));
}

/// Xray's run-time bounds and its own XHTTP build checks
/// (infra/conf/transport_method.go).
bool _xhttp(Map x) {
  final mode = x['mode'] ?? '';
  final reuse = x['reuse-settings'] as Map? ?? const {};
  int top(Object? range) => '${range ?? ''}'
      .split('-')
      .map((end) => int.tryParse(end) ?? 0)
      .fold(0, max);
  return !x.containsKey('download-settings') &&
      '${x['session-table'] ?? ''}'.isEmpty &&
      _range(x['x-padding-bytes'], 1, 65535) &&
      _range(x['session-length'], 1, 1024) &&
      _range(x['sc-max-each-post-bytes'], 1, _int32) &&
      _range(x['sc-min-posts-interval-ms'], 0, _int32) &&
      _range(x['uplink-chunk-size'], 0, _int32) &&
      [
        'max-concurrency',
        'max-connections',
        'c-max-reuse-times',
        'h-max-request-times',
        'h-max-reusable-secs',
      ].every((key) => _range(reuse[key], 0, _int32)) &&
      (reuse['h-keep-alive-period'] as num? ?? 0) >= 0 &&
      !(top(reuse['max-concurrency']) > 0 &&
          top(reuse['max-connections']) > 0) &&
      _oneOf(x, 'mode', 'auto packet-up stream-up stream-one') &&
      !(x['headers'] as Map? ?? const {}).keys.any(
        (key) => '$key'.toLowerCase() == 'host',
      ) &&
      _oneOf(x, 'x-padding-placement', 'cookie header query queryInHeader') &&
      _oneOf(x, 'x-padding-method', 'repeat-x tokenish') &&
      (_oneOf(x, 'uplink-data-placement', 'auto body') ||
          mode == 'packet-up' &&
              _oneOf(x, 'uplink-data-placement', 'cookie header')) &&
      ('${x['uplink-http-method'] ?? ''}'.toUpperCase() != 'GET' ||
          mode == 'packet-up') &&
      _oneOf(x, 'session-placement', 'path cookie header query') &&
      _oneOf(x, 'seq-placement', 'path cookie header query');
}

final _encryptionShape = RegExp(
  r'^mlkem768x25519plus\.(?:native|xorpub|random)\.[01]rtt'
  r'((?:\.\d{1,5}-\d{1,5}-\d{1,5})*)((?:\.[\w-]{20,})+)$',
);

/// The shape Xray slices VLESS encryption by (infra/conf/vless.go), and its
/// padding check (`ParsePadding`, proxy/vless/encryption/common.go).
bool _encryption(Object? value) {
  if (value == null || value == '' || value == 'none') return true;
  final match = _encryptionShape.firstMatch('$value');
  if (match == null ||
      match[2]!.split('.').skip(1).any((key) => !_keyBytes(key))) {
    return false;
  }
  final paddings = [
    for (final part in match[1]!.split('.').skip(1))
      [for (final n in part.split('-')) int.parse(n)],
  ];
  if (paddings.isNotEmpty &&
      (paddings[0][0] < 100 || paddings[0][1] < 35 || paddings[0][2] < 35)) {
    return false;
  }
  var total = 0;
  for (var i = 0; i < paddings.length; i += 2) {
    total += max(paddings[i][1], paddings[i][2]);
  }
  return total <= 18 + 65535;
}

/// An X25519 or ML-KEM-768 key, which Xray tells from the padding by length.
bool _keyBytes(String key) {
  try {
    final length = base64Url.decode(base64Url.normalize(key)).length;
    return length == 32 || length == 1184;
  } on FormatException {
    return false;
  }
}

bool _wireguard(Map<String, dynamic> server) {
  bool ip(Object? value) => InternetAddress.tryParse('$value') != null;
  bool key(Object? value) =>
      value == null || RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch('$value');
  final reserved = server['reserved'];
  final dns = server['dns'];
  final allowed = server['allowed-ips'];
  final mtu = server['mtu'];
  return (reserved == null ||
          reserved is List &&
              reserved.length == 3 &&
              reserved.every((b) => _number(b, 0, 255))) &&
      (dns == null || dns is List && dns.every(ip)) &&
      (allowed == null || allowed is List && allowed.every(_prefix)) &&
      [server['ip'], server['ipv6']].every(
        (address) => address == null || ip(address) || _prefix(address),
      ) &&
      (mtu == null || mtu == 0 || _number(mtu, 576, 65535)) &&
      _number(server['persistent-keepalive'], 0, 0xffffffff) &&
      [
        'private-key',
        'public-key',
        'pre-shared-key',
      ].every((name) => key(server[name]));
}

bool _number(Object? value, int low, int high) =>
    value == null || value is int && value >= low && value <= high;

/// "N" or "N-M", no sign, every end within [low, high].
bool _range(Object? value, int low, int high) {
  if (value == null || value == '') return true;
  final match = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch('$value');
  return match != null &&
      [match[1], match[2]].every((end) {
        final n = end == null ? low : int.tryParse(end);
        return n != null && n >= low && n <= high;
      });
}

bool _prefix(Object? value) {
  final parts = '$value'.split('/');
  final address = InternetAddress.tryParse(parts.first);
  final bits = parts.length == 2 ? int.tryParse(parts[1]) : null;
  return address != null &&
      bits != null &&
      bits >= 0 &&
      bits <= (address.type == InternetAddressType.IPv4 ? 32 : 128);
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
