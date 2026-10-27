import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show join;
import 'package:shared_preferences/shared_preferences.dart';

const warpProxyName = 'shikoo-warp';

/// No screen has it yet; `--dart-define=SHIKOO_WARP=true` turns it on in a test build (docs/warp-bridge.md).
class ShikooWarpNotifier extends Notifier<bool> {
  static const _key = 'shikoo.warp';

  @override
  bool build() => const bool.fromEnvironment('SHIKOO_WARP');

  Future<void> load() async =>
      state = (await SharedPreferences.getInstance()).getBool(_key) ?? state;

  Future<void> set(bool on) async {
    state = on;
    await (await SharedPreferences.getInstance()).setBool(_key, on);
  }
}

final shikooWarpProvider = NotifierProvider<ShikooWarpNotifier, bool>(
  ShikooWarpNotifier.new,
);

/// Proxies that reach no server: through the bridge, `direct` would be WARP's free internet.
const _serverless = {
  'direct',
  'reject',
  'reject-drop',
  'pass',
  'dns',
  'compatible',
};

/// A server handed to a core behind mihomo stays with mihomo: those engines dial it themselves, around the bridge.
Map<String, dynamic> markWarp(Map<String, dynamic> config, {required bool on}) {
  if (!on) return config;
  final proxies = config['proxies'];
  return {
    ...config,
    'proxies': [
      for (final proxy in proxies is List ? proxies : const [])
        if (proxy is Map &&
            !_serverless.contains('${proxy['type']}'.toLowerCase()))
          {
            for (final MapEntry(:key, :value) in proxy.entries)
              if (key != 'shikoo-core') key: value,
            'dialer-proxy': proxy['dialer-proxy'] ?? warpProxyName,
          }
        else
          proxy,
      // Go fills in the port and password; port 1 is refused if this build has no bridge.
      {
        'name': warpProxyName,
        'type': 'socks5',
        'server': '127.0.0.1',
        'port': 1,
        'shikoo-core': 'warp',
      },
    ],
  };
}

({String yaml, String md5}) warpOnlyProfile({required bool on}) {
  if (!on) return (yaml: '', md5: '');
  final yaml = json.encode(markWarp({'proxies': const []}, on: true));
  return (yaml: yaml, md5: yaml.toMd5());
}

bool warpLegWanted({
  required bool on,
  required bool chosen,
  required Object error,
}) => on && !chosen && !(error is DioException && error.response != null);

Future<String?> warpProxy(ProviderReader read) async {
  if (!read(shikooWarpProvider)) return null;
  try {
    final home = await appPath.homeDirPath;
    final endpoint = json.decode(
      await File(join(home, 'warp', 'endpoint.json')).readAsString(),
    );
    return 'PROXY ${endpoint['auth']}@${endpoint['http']}';
  } on Object {
    return null;
  }
}

const warpSource =
    'aether 2.4.0 (patterniha/Aether, commit d58f9d568083129ce2c767c85054021eb3ee6a38, AGPL-3.0-only), '
    'built without tor or psiphon by tools/warp-build.sh, with the change in tools/warp/aether-proxy-auth.patch. '
    'Source: https://github.com/patterniha/Aether and https://github.com/Shikoonet/shikoo-android';

void registerWarpLicenses() => LicenseRegistry.addLicense(() async* {
  final license = await rootBundle.loadString('assets/data/warp-LICENSE.txt');
  final notices = await rootBundle.loadString('assets/data/warp-NOTICES.txt');
  yield LicenseEntryWithLineBreaks(['aether'], '$warpSource\n\n$license');
  yield LicenseEntryWithLineBreaks(['aether'], notices);
});
