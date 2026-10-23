/// SHIKOO_PATCHES 47, only where the panel says nothing: the official Android app's MTU, not
/// mihomo's 1408 that some lines drop; a keepalive; UDP, which mihomo otherwise sends DIRECT; and
/// names resolved inside the tunnel, as the official app does, not by the core's own DNS.
void wireGuardDefaults(Map proxy) {
  if (proxy['type'] != 'wireguard') return;
  proxy['mtu'] ??= 1280;
  proxy['persistent-keepalive'] ??= 25;
  proxy['udp'] ??= true;
  if (proxy['dns'] == null && proxy['remote-dns-resolve'] == null) {
    proxy['remote-dns-resolve'] = true;
    proxy['dns'] = ['1.1.1.1', '8.8.8.8'];
  }
}
