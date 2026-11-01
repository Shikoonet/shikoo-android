import 'dart:async';
import 'dart:io' show InternetAddress, Socket;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/shikoo/engine/direct_dns.dart'
    show shikooServerNameDns;
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const offlineProbeLimit = Duration(seconds: 3);

final networksNowProvider =
    Provider<Future<List<ConnectivityResult>> Function()>(
      (ref) =>
          () => Connectivity().checkConnectivity(),
    );

final hostResolvesProvider = Provider<Future<bool> Function(String)>(
  (ref) => (host) async {
    try {
      final found = await InternetAddress.lookup(
        host,
      ).timeout(offlineProbeLimit);
      return found.isNotEmpty;
    } catch (_) {
      return false;
    }
  },
);

Future<bool> _connects(String host, int port) async {
  try {
    final socket = await Socket.connect(host, port, timeout: offlineProbeLimit);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// A TCP answer from any door: a device clock too wrong for TLS must not read as no internet.
final doorReachableProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () => anyTrue([
        for (final base in shikooApiBases)
          _connects(Uri.parse(base).host, Uri.parse(base).port),
      ]),
);

final resolversReachableProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () => anyTrue([
        for (final server in shikooServerNameDns) _connects(server, 53),
      ]),
);

Future<bool> anyTrue(Iterable<Future<bool>> checks) {
  final answer = Completer<bool>();
  var left = checks.length;
  if (left == 0) answer.complete(false);
  for (final check in checks) {
    check.then((ok) {
      if (ok && !answer.isCompleted) answer.complete(true);
      if (--left == 0 && !answer.isCompleted) answer.complete(false);
    });
  }
  return answer.future;
}

/// Asked before the tunnel starts, so no VPN of ours is up; any doubt is online.
Future<bool> startsOffline({
  required Future<List<ConnectivityResult>> Function() networks,
  required Future<bool> Function(String host) resolves,
  required Future<bool> Function() door,
  required Future<bool> Function() resolvers,
  required String? host,
}) async {
  final now = await networks();
  if (now.contains(ConnectivityResult.vpn)) return false;
  if (now.isEmpty) return false;
  if (now.every((network) => network == ConnectivityResult.none)) return true;
  if (host == null || host.isEmpty || InternetAddress.tryParse(host) != null) {
    return false;
  }
  return !await resolves(host) && !await anyTrue([door(), resolvers()]);
}
