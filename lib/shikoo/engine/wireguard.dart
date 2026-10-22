/// SHIKOO_PATCHES 47, only where the panel says nothing: the official Android app's MTU, not
/// mihomo's 1408 that some lines drop; a keepalive; and UDP, which mihomo otherwise sends DIRECT.
void wireGuardDefaults(Map proxy) {
  if (proxy['type'] != 'wireguard') return;
  proxy['mtu'] ??= 1280;
  proxy['persistent-keepalive'] ??= 25;
  proxy['udp'] ??= true;
}
