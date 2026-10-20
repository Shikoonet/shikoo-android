import 'dart:io';

import 'package:fl_clash/common/constant.dart' show shikooStagingBuild;
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/core/desktop/helper_client.dart';
import 'package:fl_clash/core/desktop/model.dart' show CoreProcessOwner;
import 'package:fl_clash/core/service.dart' show coreService;
import 'package:fl_clash/shikoo/engine/windows_adapters.dart';
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

const shikooDesktopPort = shikooStagingBuild ? 17471 : 17470;

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

enum ShikooAdmin { ready, installed, refused, failed }

final tunAuthorizeProvider = Provider<Future<ShikooAdmin> Function()>(
  (_) => _helperService,
);

/// A core the app launched itself, the helper not answering in time, cannot open TUN; FlClash still calls it authorized.
final directCoreProvider = Provider<bool Function()>(
  (_) =>
      () => coreService?.owner == CoreProcessOwner.direct,
);

/// FlClash's `registerHelperService` (`lib/common/system.dart`), a refused prompt told apart from a failed service.
Future<ShikooAdmin> _helperService() async {
  switch (await helperClient.readiness()) {
    case HelperReadiness.ready:
      return ShikooAdmin.ready;
    case HelperReadiness.manifestMissing:
      return ShikooAdmin.failed;
    case HelperReadiness.notReady:
      break;
  }
  if (windows?.runas(appPath.helperPath, 'install') != true) {
    return ShikooAdmin.refused;
  }
  for (var second = 0; second < 6; second++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (await helperClient.readiness(logFailure: false) ==
        HelperReadiness.ready) {
      return ShikooAdmin.installed;
    }
  }
  return ShikooAdmin.failed;
}

/// The core names the TUN adapter after `tun.device`; FlClash runs on without it when the helper fails.
final tunUpProvider = Provider<Future<bool> Function(String device)>(
  (_) =>
      (device) async => upAdapters().contains(device),
);
