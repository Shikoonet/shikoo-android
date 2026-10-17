import 'dart:convert';

import 'package:fl_clash/shikoo/app/wininet.dart';
import 'package:proxy/proxy_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FlClash's own stop and its Windows-shutdown hook (`WM_ENDSESSION` in `proxy_plugin.cpp`) clear only the flags.
bool _stoppedByFlClash(WinProxy setting, int port) =>
    setting.flags == proxyTypeDirect && setting.server == '127.0.0.1:$port';

/// Puts back the setting from before connect, kept on disk until then, unless another app set its own since.
class ShikooSystemProxy extends ProxyPlatform {
  ShikooSystemProxy(
    this._inner,
    this._port, {
    this.read = readWinProxy,
    this.write = writeWinProxy,
  });

  final ProxyPlatform _inner;
  final int Function() _port;
  final WinProxy? Function() read;
  final bool Function(WinProxy setting) write;

  static const savedKey = 'shikoo.windowsProxy';
  bool _launch = true;

  @override
  Future<bool> startProxy(int port, List<String> bypassDomain) async {
    final now = read();
    final prefs = await SharedPreferences.getInstance();
    if (now != null &&
        !proxyIsOurs(now, port) &&
        !prefs.containsKey(savedKey)) {
      await prefs.setString(savedKey, jsonEncode(_toJson(now)));
    }
    return _inner.startProxy(port, bypassDomain);
  }

  @override
  Future<bool> stopProxy() async {
    final launch = _launch;
    _launch = false;
    final prefs = await SharedPreferences.getInstance();
    final saved = _fromJson(prefs.getString(savedKey));
    final now = read();
    final port = _port();
    final ours = now != null && proxyIsOurs(now, port);
    final leftOver =
        launch && saved != null && now != null && _stoppedByFlClash(now, port);
    if (!ours && !leftOver) {
      await prefs.remove(savedKey);
      return true;
    }
    final stopped = !ours || await _inner.stopProxy();
    // ponytail: the LAN setting only; a dial-up entry FlClash also set stays direct.
    final restored = saved == null || write(saved);
    if (restored) await prefs.remove(savedKey);
    return stopped && restored;
  }
}

Map<String, Object?> _toJson(WinProxy s) => {
  'flags': s.flags,
  'server': s.server,
  'bypass': s.bypass,
  'pac': s.pac,
};

WinProxy? _fromJson(String? raw) {
  if (raw == null) return null;
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return (
    flags: json['flags'] as int,
    server: json['server'] as String?,
    bypass: json['bypass'] as String?,
    pac: json['pac'] as String?,
  );
}
