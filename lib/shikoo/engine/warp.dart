import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry, setEquals;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show join;
import 'package:shared_preferences/shared_preferences.dart';

const warpProxyName = 'shikoo-warp';

/// How long a first try through the bridge may take on a network: aether's own start (25-31 s measured) and a ping.
Duration warpConnectTimeout = const Duration(seconds: 60);

/// Off unless the customer turns it on (Sam, 2026-10-28); `--dart-define=SHIKOO_WARP=true` in a test build.
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

class ShikooWarpMemoryNotifier extends Notifier<Map<String, Set<String>>> {
  static const _key = 'shikoo.warp.via';

  @override
  Map<String, Set<String>> build() => const {};

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    state = {
      for (final MapEntry(:key, :value) in (json.decode(raw) as Map).entries)
        '$key': {for (final name in value as List) '$name'},
    };
  }

  Future<void> set(String network, Set<String> names) async {
    state = {...state, network: names}..removeWhere((_, via) => via.isEmpty);
    await (await SharedPreferences.getInstance()).setString(
      _key,
      json.encode({
        for (final MapEntry(:key, :value) in state.entries) key: value.toList(),
      }),
    );
  }
}

final shikooWarpMemoryProvider =
    NotifierProvider<ShikooWarpMemoryNotifier, Map<String, Set<String>>>(
      ShikooWarpMemoryNotifier.new,
    );

class WarpCell<T> extends Notifier<T> {
  WarpCell(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}

final warpNetworkProvider = NotifierProvider<WarpCell<String>, String>(
  () => WarpCell(''),
);
final warpTrialProvider = NotifierProvider<WarpCell<Set<String>>, Set<String>>(
  () => WarpCell(const {}),
);
final warpAppProvider = NotifierProvider<WarpCell<bool>, bool>(
  () => WarpCell(false),
);

// shortcut: a network is its kind, what the app knows without a location permission; two Wi-Fi networks share one
// memory. Upgrade to the Wi-Fi name if the app ever holds that permission.
final warpNetworkReaderProvider = Provider<Future<String> Function()>(
  (_) => () async {
    try {
      final kinds = await Connectivity().checkConnectivity();
      return const [
            ConnectivityResult.ethernet,
            ConnectivityResult.wifi,
            ConnectivityResult.mobile,
          ].firstWhereOrNull(kinds.contains)?.name ??
          'other';
    } on Object {
      return 'other';
    }
  },
);

typedef WarpRoute = ({Set<String> via, bool app});

const WarpRoute noWarp = (via: {}, app: false);

WarpRoute warpRoute({
  required bool on,
  required Set<String> remembered,
  required Set<String> trial,
  required bool app,
}) => on ? (via: {...remembered, ...trial}, app: app) : noWarp;

bool sameRoute(WarpRoute a, WarpRoute b) =>
    a.app == b.app && setEquals(a.via, b.via);

final shikooWarpRouteProvider = Provider<WarpRoute>(
  (ref) => warpRoute(
    on: ref.watch(shikooWarpProvider),
    remembered:
        ref.watch(shikooWarpMemoryProvider)[ref.watch(warpNetworkProvider)] ??
        const {},
    trial: ref.watch(warpTrialProvider),
    app: ref.watch(warpAppProvider),
  ),
);

Set<String> bridgeCandidates({
  required bool on,
  required Iterable<String> silent,
  required Set<String> via,
}) => on ? {...silent}.difference(via) : const {};

/// Proxies that reach no server: through the bridge, `direct` would be WARP's free internet.
const _serverless = {
  'direct',
  'reject',
  'reject-drop',
  'pass',
  'dns',
  'compatible',
};

/// A core behind mihomo gives a server on [route] back to mihomo: those engines dial it themselves, around the bridge.
Map<String, dynamic> markWarp(Map<String, dynamic> config, WarpRoute route) {
  if (route.via.isEmpty && !route.app) return config;
  final proxies = config['proxies'];
  return {
    ...config,
    'proxies': [
      for (final proxy in proxies is List ? proxies : const [])
        if (proxy is Map &&
            route.via.contains(proxy['name']) &&
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

({String yaml, String md5}) warpOnlyProfile(WarpRoute route) {
  if (!route.app) return (yaml: '', md5: '');
  final yaml = json.encode(markWarp({'proxies': const []}, route));
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
