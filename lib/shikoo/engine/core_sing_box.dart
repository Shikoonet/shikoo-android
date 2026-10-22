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

const _fingerprints =
    'none chrome firefox safari ios android edge 360 qq random randomized';

bool _serves(ShikooProtocol protocol, Map<String, dynamic> server) {
  final keys = '${_keys[protocol]} name type server port udp'.split(' ');
  if (!_keys.containsKey(protocol) ||
      !server.keys.every(keys.contains) ||
      server['remote-dns-resolve'] == true) {
    return false;
  }
  bool oneOf(String key, String values) =>
      ' $values'.split(' ').contains(server[key] ?? '');
  return switch (protocol) {
    ShikooProtocol.vless =>
      oneOf('encryption', 'none') &&
          oneOf('network', 'tcp ws grpc') &&
          oneOf('flow', 'xtls-rprx-vision') &&
          oneOf('client-fingerprint', _fingerprints),
    ShikooProtocol.openvpn => oneOf('dev', 'tun'),
    _ => true,
  };
}
