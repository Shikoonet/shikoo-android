import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/shikoo/app/wininet.dart';
import 'package:proxy/proxy_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FlClash's own stop and its Windows-shutdown hook (`WM_ENDSESSION` in `proxy_plugin.cpp`) clear only the flags.
bool _stoppedByFlClash(WinProxy setting, int port) =>
    setting.flags == proxyTypeDirect && setting.server == '127.0.0.1:$port';

const _loopback = {'127.0.0.1', 'localhost', '::1'};

/// Sam (2026-10-17): a proxy on this computer whose app no longer answers is turned off, not put back.
Future<WinProxy> _alive(
  WinProxy saved,
  Future<bool> Function(String host, int port) listening,
) async {
  if (saved.flags & proxyTypeProxy == 0) return saved;
  final servers = [
    for (final entry in (saved.server ?? '').split(';'))
      Uri.tryParse('http://${entry.split('=').last.trim()}'),
  ];
  if (servers.any(
    (uri) => uri == null || !uri.hasPort || !_loopback.contains(uri.host),
  )) {
    return saved;
  }
  for (final uri in servers) {
    if (await listening(uri!.host, uri.port)) return saved;
  }
  return (
    flags: saved.flags & ~proxyTypeProxy | proxyTypeDirect,
    server: saved.server,
    bypass: saved.bypass,
    pac: saved.pac,
  );
}

Future<bool> _listening(String host, int port) async {
  try {
    (await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 1),
    )).destroy();
    return true;
  } on SocketException {
    return false;
  }
}

/// Puts back the setting from before connect, kept on disk until then, unless another app set its own since.
class ShikooSystemProxy extends ProxyPlatform {
  ShikooSystemProxy(
    this._inner,
    this._port, {
    this.read = readWinProxy,
    this.write = writeWinProxy,
    this.listening = _listening,
  });

  final ProxyPlatform _inner;
  final int Function() _port;
  final WinProxy? Function() read;
  final bool Function(WinProxy setting) write;
  final Future<bool> Function(String host, int port) listening;

  static const savedKey = 'shikoo.windowsProxy';
  bool _launch = true;
  Future<void> _last = Future.value();

  /// An exit's stop that lands during a start's save would read the setting from before the save.
  Future<bool> _inTurn(Future<bool> Function() step) {
    final next = _last.then((_) => step());
    _last = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  @override
  Future<bool> startProxy(int port, List<String> bypassDomain) =>
      _inTurn(() async {
        final now = read();
        final prefs = await SharedPreferences.getInstance();
        if (now != null &&
            !proxyIsOurs(now, port) &&
            !prefs.containsKey(savedKey)) {
          await prefs.setString(
            savedKey,
            jsonEncode({..._toJson(now), 'port': port}),
          );
        }
        return _inner.startProxy(port, bypassDomain);
      });

  @override
  Future<bool> stopProxy() => _inTurn(() async {
    final launch = _launch;
    _launch = false;
    final prefs = await SharedPreferences.getInstance();
    final saved = _fromJson(prefs.getString(savedKey));
    final now = read();
    final port = saved?.port ?? _port();
    final ours = now != null && proxyIsOurs(now, port);
    final leftOver =
        launch && saved != null && now != null && _stoppedByFlClash(now, port);
    if (!ours && !leftOver) {
      if (saved != null) await prefs.remove(savedKey);
      return true;
    }
    final stopped = !ours || await _inner.stopProxy();
    // ponytail: the LAN setting only; a dial-up entry FlClash also set stays direct.
    final restored =
        saved == null || write(await _alive(saved.setting, listening));
    if (restored && saved != null) await prefs.remove(savedKey);
    return stopped && restored;
  });
}

/// `--restore-proxy`, for the uninstaller, which kills the app first and waits on this process with no limit of its own.
Future<Never> restoreProxyAndExit({
  Never Function(int code) quit = exit,
  Future<bool> Function() restore = _restore,
}) async {
  var restored = false;
  try {
    // Its slowest real path is four loopback probes of a second each (_alive).
    restored = await restore().timeout(
      const Duration(seconds: 10),
      onTimeout: () => false,
    );
  } finally {
    quit(restored ? 0 : 1);
  }
}

Future<bool> _restore() =>
    ShikooSystemProxy(ProxyPlatform.instance, () => 0).stopProxy();

Map<String, Object?> _toJson(WinProxy s) => {
  'flags': s.flags,
  'server': s.server,
  'bypass': s.bypass,
  'pac': s.pac,
};

({WinProxy setting, int? port})? _fromJson(String? raw) {
  if (raw == null) return null;
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return (
    setting: (
      flags: json['flags'] as int,
      server: json['server'] as String?,
      bypass: json['bypass'] as String?,
      pac: json['pac'] as String?,
    ),
    port: json['port'] as int?,
  );
}
