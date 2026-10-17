import 'dart:io';

import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Windows' system proxy, or TUN for the whole computer.
enum ShikooMode {
  proxy(systemProxy: true, tun: false),
  tunnel(systemProxy: false, tun: true);

  const ShikooMode({required this.systemProxy, required this.tun});

  final bool systemProxy;
  final bool tun;
}

const shikooDefaultMode = ShikooMode.tunnel;

class ShikooModeNotifier extends Notifier<ShikooMode> {
  static const _key = 'shikoo.mode';

  @override
  ShikooMode build() => shikooDefaultMode;

  Future<void> load() async {
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    state = ShikooMode.values.asNameMap()[saved] ?? state;
  }

  Future<void> save(ShikooMode mode) async {
    state = mode;
    await (await SharedPreferences.getInstance()).setString(_key, mode.name);
  }
}

final shikooModeProvider = NotifierProvider<ShikooModeNotifier, ShikooMode>(
  ShikooModeNotifier.new,
);

final shikooDesktopProvider = Provider<bool>((_) => system.isWindows);

final localPortFreeProvider = Provider<Future<bool> Function(int port)>(
  (_) => (port) async {
    try {
      await (await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      )).close();
      return true;
    } on SocketException {
      return false;
    }
  },
);

final tunAuthorizeProvider = Provider<Future<AuthorizeCode> Function()>(
  (_) => system.authorizeCore,
);

/// The core names the TUN adapter after `tun.device`; FlClash runs on without it when the helper fails.
final tunUpProvider = Provider<Future<bool> Function(String device)>(
  (_) =>
      (device) async =>
          (await NetworkInterface.list()).any((i) => i.name == device),
);
