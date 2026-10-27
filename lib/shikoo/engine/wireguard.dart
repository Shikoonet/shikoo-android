import 'dart:io' show InternetAddress, InternetAddressType;

/// SHIKOO_PATCHES 47, only where the panel says nothing: the official Android app's MTU, not
/// mihomo's 1408 that some lines drop; a keepalive; UDP, which mihomo otherwise sends DIRECT; and
/// names resolved inside the tunnel, as the official app does, not by the core's own DNS.
void wireGuardDefaults(Map proxy) {
  if (proxy['type'] != 'wireguard') return;
  proxy['mtu'] ??= 1280;
  proxy['persistent-keepalive'] ??= 25;
  proxy['udp'] ??= true;
  if (proxy['dns'] == null &&
      proxy['remote-dns-resolve'] == null &&
      _tunnelReachesDns(proxy)) {
    proxy['remote-dns-resolve'] = true;
    proxy['dns'] = [for (final ip in _tunnelDns) ip.address];
  }
}

final _tunnelDns = [InternetAddress('1.1.1.1'), InternetAddress('8.8.8.8')];

/// The core sends the lookups as UDP over IPv4, and a server without `peers` routes 0.0.0.0/0.
bool _tunnelReachesDns(Map proxy) {
  if (proxy['udp'] != true || '${proxy['ip'] ?? ''}'.isEmpty) return false;
  final peers = proxy['peers'];
  if (peers is! List || peers.isEmpty) return true;
  final nets = [];
  for (final peer in peers) {
    if (peer is! Map || peer['allowed-ips'] is! List) return false;
    nets.addAll(peer['allowed-ips'] as List);
  }
  return _tunnelDns.every((ip) => nets.any((net) => _covers('$net', ip)));
}

bool _covers(String net, InternetAddress ip) {
  final [address, ...bits] = net.trim().split('/');
  final base = InternetAddress.tryParse(address);
  final length = bits.isEmpty ? 32 : int.tryParse(bits.first);
  if (base?.type != InternetAddressType.IPv4 || length == null) return false;
  if (length < 0 || length > 32) return false;
  final a = base!.rawAddress, b = ip.rawAddress;
  for (var i = 0; i < length; i++) {
    if ((a[i >> 3] ^ b[i >> 3]) & (0x80 >> (i & 7)) != 0) return false;
  }
  return true;
}
