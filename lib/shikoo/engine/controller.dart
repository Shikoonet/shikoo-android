import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/desktop/model.dart' show CoreProcessOwner;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/direct_dns.dart' show directInboundProxy;
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:fl_clash/shikoo/engine/order.dart';
import 'package:fl_clash/shikoo/engine/owner.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/warp.dart';
import 'package:fl_clash/shikoo/engine/wireguard.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:fl_clash/shikoo/engine/cores.dart' show shikooCoreSpecsProvider;

/// The only door from Shikoo screens into FlClash's engine (docs/extensibility.md section 1).

enum ShikooConnection { off, connecting, on, error }

enum ShikooError {
  connectTimeout,
  serverChange,
  noServer,
  vpnRefused,
  vpnMissing,
  coreDown,
  coreStart,
}

/// [revoked]: a pasted link the panel no longer knows (404 or 410).
enum ShikooServiceStatus { active, expired, exhausted, revoked }

enum ShikooPick { server, finding, auto, none }

enum ShikooRefresh { idle, running, failed }

enum ShikooSwitchStage { moving, done, failed }

/// Connected, a tapped [to] gets the traffic only once it answers; [from] keeps it until then.
typedef ShikooSwitch = ({String to, String from, ShikooSwitchStage stage});

typedef ShikooLanded = ({int id, bool arrived});

typedef ShikooCoreSwitch = ({
  ShikooProtocol protocol,
  ShikooCore to,
  ShikooSwitchStage stage,
});

/// The open card's list while another service has the tunnel: measured there, never connected to.
typedef ShikooOpened = ({
  int id,
  List<ShikooServer> servers,
  ({int done, int total})? pinging,
  bool sorted,
});

const connectTimeout = Duration(seconds: 30);

@visibleForTesting
Duration connectWait = connectTimeout;

/// A core that keeps dying is left down: a profile it cannot run would restart it forever.
const coreRevives = 3;
const coreReviveWindow = Duration(minutes: 2);

const switchedFor = Duration(seconds: 4);

@immutable
class ShikooServer {
  const ShikooServer({
    required this.name,
    required this.type,
    this.ping,
    this.testing = false,
    this.fresh = false,
    this.protocol = ShikooProtocol.other,
    this.core = ShikooCore.mihomo,
    this.viaBridge = false,
  });

  final String name;

  final bool viaBridge;

  /// The engine's protocol name, kept as data so a new protocol needs no screen change.
  final String type;

  final ShikooProtocol protocol;

  /// The core carrying it now: mihomo too when the user's pick cannot, or this build lacks it.
  final ShikooCore core;

  /// Milliseconds; null = not tested yet, -1 = no answer.
  final int? ping;
  final bool testing;

  final bool fresh;

  String get label => withoutFlags(name);

  String? get country => countryOf(name);
}

@immutable
class ShikooService {
  const ShikooService({
    this.id = 0,
    required this.name,
    required this.usedBytes,
    required this.totalBytes,
    this.expire,
    this.announce,
    this.supportUrl,
    this.updatedAt,
    this.usageKnown = true,
    this.refresh = ShikooRefresh.idle,
    this.leg,
    this.bridgeLeg = false,
    this.pasted = false,
    this.revoked = false,
    this.number = 1,
    this.account,
    this.outsourced = false,
    this.loginRefused = false,
    this.notHere = false,
  });

  final bool bridgeLeg;

  final int id;
  final String name;
  final int usedBytes;

  /// 0 = no volume limit.
  final int totalBytes;
  final DateTime? expire;
  final String? announce;
  final String? supportUrl;

  final DateTime? updatedAt;

  final bool usageKnown;

  final ShikooRefresh refresh;

  final ShikooLeg? leg;

  final bool pasted;
  final bool revoked;

  /// Among the services without a name, 1 for the first.
  final int number;

  final String? account;

  final bool outsourced;

  final bool loginRefused;

  /// An outsourced (OpenVPN) account no core here runs, as on Windows: its card says so, and it never connects.
  final bool notHere;

  String get supportLink => usableLink(supportUrl) ?? ShikooLinks.support;

  String get username => usernameOf(name);

  ShikooServiceStatus statusAt(DateTime now) {
    if (revoked) return ShikooServiceStatus.revoked;
    if (expire != null && !expire!.isAfter(now)) {
      return ShikooServiceStatus.expired;
    }
    if (totalBytes > 0 && usedBytes >= totalBytes) {
      return ShikooServiceStatus.exhausted;
    }
    return ShikooServiceStatus.active;
  }

  bool get finished => const {
    ShikooServiceStatus.exhausted,
    ShikooServiceStatus.expired,
  }.contains(ended);

  ShikooServiceStatus? get ended {
    final status = statusAt(shikooNow());
    return (usageKnown || revoked) && status != ShikooServiceStatus.active
        ? status
        : null;
  }
}

/// What the last subscription update did, shown under the service name until the next one.
sealed class ShikooNotice {
  const ShikooNotice();
}

class ServersChanged extends ShikooNotice {
  const ServersChanged({required this.added, required this.removed});

  final int added;
  final List<String> removed;
}

class SelectedReplaced extends ShikooNotice {
  const SelectedReplaced({
    required this.removed,
    required this.replacement,
    required this.moved,
    this.fastest = true,
  });

  final String removed;
  final String replacement;

  /// The tunnel was up, so traffic moved at once.
  final bool moved;

  final bool fastest;
}

class SilentReplaced extends ShikooNotice {
  const SilentReplaced({required this.silent, required this.replacement});

  final String silent;
  final String replacement;
}

class SelectedGone extends ShikooNotice {
  const SelectedGone();
}

class RefreshFailed extends ShikooNotice {
  const RefreshFailed({
    this.clock = false,
    this.way = ShikooFailedWay.directOff,
    this.server,
    this.bridge = false,
  });

  final bool clock;
  final ShikooFailedWay way;

  final bool bridge;

  final String? server;
}

/// "Without proxy" ([direct]: the device's own internet, also while connected) or "with proxy" ([server]).
enum ShikooRoute { direct, server }

/// The way an update is on: [directOff] with no tunnel up, [fallback] the server after direct failed.
enum ShikooLeg { direct, directOff, server, fallback }

/// [panel]: the subscription server itself answered, with an error.
enum ShikooFailedWay { directOff, direct, server, both, panel, notConnected }

ShikooFailedWay failedWay(ShikooLeg? last, Object error) =>
    switch ((last, error)) {
      (_, ShikooNotConnected()) => ShikooFailedWay.notConnected,
      (ShikooLeg.direct || ShikooLeg.directOff, DioException(response: _?)) =>
        ShikooFailedWay.panel,
      (ShikooLeg.direct, _) => ShikooFailedWay.direct,
      (ShikooLeg.server, _) => ShikooFailedWay.server,
      (ShikooLeg.fallback, _) => ShikooFailedWay.both,
      (ShikooLeg.directOff, _) => ShikooFailedWay.directOff,
      (null, _) => ShikooFailedWay.panel,
    };

class ShikooNotConnected implements Exception {
  const ShikooNotConnected();
}

/// [via] servers leaving through the bridge now; [trying] those silent direct, tried through it; [failed] the last
/// round got no answer even there; [door] the app's own request, to the door or for a subscription, is on it now.
typedef ShikooBridge = ({
  bool on,
  Set<String> via,
  bool trying,
  bool failed,
  bool door,
});

const ShikooBridge noBridge = (
  on: false,
  via: {},
  trying: false,
  failed: false,
  door: false,
);

@immutable
class ShikooState {
  const ShikooState({
    required this.connection,
    required this.connectedFor,
    required this.isTV,
    required this.servers,
    this.service,
    this.selected,
    this.lastError,
    this.pick = ShikooPick.server,
    this.pinging,
    this.refresh = ShikooRefresh.idle,
    this.notice,
    this.waiting = false,
    this.others = const [],
    this.switching,
    this.sorted = false,
    this.open,
    this.opened,
    this.order = const [],
    this.landed,
    this.busyPort,
    this.helperFailed = false,
    this.iranDirect = true,
    this.cores = const [],
    this.coreSwitch,
    this.bridge = noBridge,
    this.connectedNoTraffic = false,
  });

  final ShikooBridge bridge;

  final bool connectedNoTraffic;

  final ShikooConnection connection;
  final Duration connectedFor;
  final bool isTV;
  final ShikooService? service;

  /// In display order: panel order until a ping round ends, then fastest first.
  final List<ShikooServer> servers;

  /// Only a server the user or the app chose and that is still in the subscription.
  final String? selected;
  final ShikooError? lastError;
  final ShikooPick pick;
  final ({int done, int total})? pinging;
  final ShikooRefresh refresh;
  final ShikooNotice? notice;

  /// Connect was pressed before a server was chosen: the first one that answers is used.
  final bool waiting;

  final List<ShikooService> others;

  final ShikooSwitch? switching;

  final bool sorted;

  /// The card the customer opened; null with every card folded.
  final int? open;

  final ShikooOpened? opened;

  final List<int> order;

  final ShikooLanded? landed;

  final int? busyPort;
  final bool helperFailed;

  final bool iranDirect;

  final List<ShikooCoreRow> cores;

  final ShikooCoreSwitch? coreSwitch;

  ShikooServer? get selectedServer =>
      servers.firstWhereOrNull((server) => server.name == selected);

  bool get streaming => streamingOnly(selected ?? '');

  bool get noInternet {
    final server = selectedServer;
    return connection == ShikooConnection.on &&
        server != null &&
        !streaming &&
        (connectedNoTraffic || (server.ping ?? 0) < 0);
  }

  /// Every service in card order ([serviceOrderProvider]), the one in use keeping its place.
  List<ShikooService> get listed {
    final byId = {
      for (final s in [?service, ...others]) s.id: s,
    };
    return [
      for (final id in inOrder(order, [...byId.keys])) byId[id]!,
    ];
  }
}

@immutable
class _Intent {
  const _Intent({
    this.connecting = false,
    this.waiting = false,
    this.error,
    this.busyPort,
    this.helperFailed = false,
  });

  final bool connecting;
  final bool waiting;
  final ShikooError? error;
  final int? busyPort;
  final bool helperFailed;
}

class ShikooCell<T> extends Notifier<T> {
  ShikooCell(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}

NotifierProvider<ShikooCell<T>, T> _cell<T>(T initial) =>
    NotifierProvider<ShikooCell<T>, T>(() => ShikooCell(initial));

final _intentProvider = _cell(const _Intent());
final _noTrafficProvider = _cell(false);

/// A server chosen while another change is in the core, shown until its own is sent.
final _wantedProvider = _cell<String?>(null);

typedef _Round = ({Set<String> pending, int total, bool ended});

const _Round _noRound = (pending: <String>{}, total: 0, ended: false);

final _roundProvider = _cell<_Round>(_noRound);

final _orderProvider = _cell<Map<int, List<String>>>(const {});

/// Our own verdicts by service, then name. FlClash's delay table also takes the core's group
/// health checks (a "Fastest" group with its own timeout), which repainted healthy servers as dead.
final _pingsProvider = _cell<Map<int, Map<String, int>>>(const {});
final _openProvider = _cell<int?>(null);

typedef _Opened = ({
  int id,
  String group,
  String url,
  Map<String, Map<String, dynamic>> proxies,
});

final _openedProvider = _cell<_Opened?>(null);
final _openRoundProvider = _cell<_Round>(_noRound);
final _refreshesProvider = _cell<Map<int, ShikooRefresh>>(const {});
final _legsProvider = _cell<Map<int, ShikooLeg>>(const {});
final _freshProvider = _cell<Set<String>>(const {});
final _pastedProvider = _cell<Set<int>>(const {});
final _revokedProvider = _cell<Set<int>>(const {});
final _noticeProvider = _cell<ShikooNotice?>(null);
final _switchProvider = _cell<ShikooSwitch?>(null);
final _landedProvider = _cell<ShikooLanded?>(null);

/// The service whose server the switch is moving to, so a same-named row elsewhere keeps still.
final _switchServiceProvider = _cell<int?>(null);

/// The tunnel's real start; FlClash's run time starts at the press, before the consent dialog.
final _nativeStartProvider = _cell<DateTime?>(null);

/// Each service's servers as its profile has them, per id: the core only shows the type it runs.
final _sourcesProvider = _cell<Map<int, Map<String, Map<String, dynamic>>>>(
  const {},
);

final _loginRefusedProvider = _cell<Set<int>>(const {});

final _coreSwitchProvider = _cell<ShikooCoreSwitch?>(null);
final _warpTryingProvider = _cell(false);
final _warpFailedProvider = _cell(false);
final _warpDoorProvider = _cell(false);
final _bridgeLegsProvider = _cell<Set<int>>(const {});

final shikooSelectedSourceProvider = Provider<Map<String, dynamic>?>((ref) {
  final id = ref.watch(currentProfileIdProvider);
  final selected = ref.watch(shikooStateProvider.select((s) => s.selected));
  return ref.watch(_sourcesProvider)[id]?[selected];
});

final _serverSourceProvider = Provider(
  (ref) => (
    id: ref.watch(currentProfileIdProvider),
    name: ref.watch(shikooStateProvider.select((s) => s.selected)),
    source: ref.watch(shikooSelectedSourceProvider),
  ),
);

typedef ShikooCarrying = ({String core, String server});

/// Hard here: the desktop RPC restarts its own timer whenever the core answers anything else, up to three times.
@visibleForTesting
Duration ownerAnswerLimit = const Duration(seconds: 2);

@visibleForTesting
Duration ownerWatchEvery = const Duration(seconds: 2);

@visibleForTesting
Duration ownerDeathWindow = const Duration(minutes: 1);

/// Go's `shikooOwner`: the owner core carrying the tunnel and its server, both '' when none; null with no answer.
final ownerCarryingProvider = Provider<Future<ShikooCarrying?> Function()>(
  (ref) => () async {
    try {
      final data = await ref
          .read(coreHandlerProvider)
          .shikooOwner()
          .timeout(ownerAnswerLimit, onTimeout: () => null);
      return data == null
          ? null
          : (core: '${data['core'] ?? ''}', server: '${data['server'] ?? ''}');
    } catch (_) {
      return null;
    }
  },
);

final _carryingProvider = _cell<ShikooCarrying?>(null);

/// Go's word on an owner session (`state` of `shikooOwner`, core/shikoo_owner.go): '' for none or no answer.
final ownerSessionProvider = Provider<Future<String> Function()>(
  (ref) => () async {
    try {
      final data = await ref
          .read(coreHandlerProvider)
          .shikooOwner()
          .timeout(ownerAnswerLimit, onTimeout: () => null);
      return '${data?['state'] ?? ''}';
    } catch (_) {
      return '';
    }
  },
);

const _sessionUp = 'up';
const _sessionRefused = 'refused';

final _sessionProvider = _cell('');

/// Panel headers FlClash does not keep (`announce`, `support-url`), per profile id.
typedef _Extras = ({String? announce, String? supportUrl, String? account});

class _ExtrasNotifier extends Notifier<Map<int, _Extras>> {
  static const _key = 'shikoo.serviceExtras';

  @override
  Map<int, _Extras> build() => const {};

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    state = {
      for (final MapEntry(:key, :value)
          in (jsonDecode(raw) as Map<String, dynamic>).entries)
        int.parse(key): (
          announce: value['announce'] as String?,
          supportUrl: value['supportUrl'] as String?,
          account: value['account'] as String?,
        ),
    };
  }

  Future<void> clear() async {
    state = const {};
    await (await SharedPreferences.getInstance()).remove(_key);
  }

  Future<void> put(int profileId, _Extras extras) async {
    state = {...state, profileId: extras};
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode({
        for (final MapEntry(:key, :value) in state.entries)
          '$key': {
            'announce': value.announce,
            'supportUrl': value.supportUrl,
            'account': value.account,
          },
      }),
    );
  }
}

final _extrasProvider = NotifierProvider<_ExtrasNotifier, Map<int, _Extras>>(
  _ExtrasNotifier.new,
);

const _notServers = {
  'Direct',
  'Reject',
  'RejectDrop',
  'Compatible',
  'Pass',
  'Dns',
};

// ponytail: the panel's info rows ("V3.7.9 🆔 …", "قبل از اتصال …") are spotted by their
// wording, so a new wording needs a new entry here; the real fix is the panel not sending them.
const _infoRowParts = ['🆔', 'قبل از اتصال'];

/// Groups ("Fastest", Fallback, LoadBalance) are not servers: the app finds the fastest itself.
bool isServer(String type, String name) =>
    !_notServers.contains(type) &&
    !GroupTypeExtension.valueList.contains(type) &&
    !isInfoRow(name);

bool isInfoRow(String name) => _infoRowParts.any(name.contains);

typedef MainGroup = ({
  String group,
  String url,
  Map<String, Map<String, dynamic>> servers,
});

/// A config's first visible group, which the home lists, and its real servers' mappings in order.
MainGroup? mainGroupOf(
  Map<String, dynamic> config, {
  Map<ShikooCore, ShikooCoreSpec> specs = shikooCoreSpecs,
  bool tunnel = true,
}) {
  final proxies = {
    for (final proxy in config['proxies'] as List? ?? const [])
      if (proxy is Map) '${proxy['name']}': Map<String, dynamic>.from(proxy),
  };
  proxies.values.forEach(wireGuardDefaults);
  for (final group in config['proxy-groups'] as List? ?? const []) {
    if (group is! Map || group['hidden'] == true) continue;
    return (
      group: '${group['name']}',
      url: '${group['url'] ?? ''}',
      servers: {
        for (final name in group['proxies'] as List? ?? const [])
          if (proxies['$name'] case final proxy?
              when isServer('${proxy['type']}', '$name') &&
                  offeredHere(proxy, specs, tunnel: tunnel))
            '$name': proxy,
      },
    );
  }
  return null;
}

List<Proxy> _serversOf(
  Group? group,
  Map<ShikooCore, ShikooCoreSpec> specs,
  bool tunnel,
) => [
  for (final proxy in group?.all ?? const <Proxy>[])
    if (isServer(proxy.type, proxy.name) &&
        offeredHere({'type': proxy.type}, specs, tunnel: tunnel))
      proxy,
];

Group? _mainGroup(Ref ref) =>
    ref.watch(currentGroupsStateProvider).value.firstOrNull;

ShikooConnection deriveConnection({
  required bool connecting,
  required bool running,
  required ShikooError? error,
  bool blocked = false,
}) {
  if (connecting) return ShikooConnection.connecting;
  if (running) return ShikooConnection.on;
  if (blocked) return ShikooConnection.error;
  return switch (error) {
    ShikooError.connectTimeout ||
    ShikooError.noServer ||
    ShikooError.vpnRefused ||
    ShikooError.vpnMissing ||
    ShikooError.coreDown ||
    ShikooError.coreStart => ShikooConnection.error,
    _ => ShikooConnection.off,
  };
}

ShikooPick derivePick({
  required bool selected,
  required bool waiting,
  required bool noAnswer,
}) {
  if (selected) return ShikooPick.server;
  if (waiting) return ShikooPick.finding;
  return noAnswer ? ShikooPick.none : ShikooPick.auto;
}

/// [System.isTV], which tests override.
final shikooTvProvider = Provider<bool>((_) => system.isTV);

/// Bytes a second in the core's last one-second sample, taken while FlClash counts the run time.
final shikooSpeedProvider = Provider<({num down, num up})>((ref) {
  final last = ref.watch(trafficsProvider).list.lastOrNull;
  return (down: last?.down ?? 0, up: last?.up ?? 0);
});

final shikooStateProvider = Provider<ShikooState>((ref) {
  final runTime = ref.watch(runTimeProvider);
  final nativeStart = ref.watch(_nativeStartProvider);
  final intent = ref.watch(_intentProvider);
  final profile = ref.watch(currentProfileProvider);
  final extras = ref.watch(_extrasProvider);
  final refreshing = ref.watch(_refreshesProvider);
  final legs = ref.watch(_legsProvider);
  final bridgeLegs = ref.watch(_bridgeLegsProvider);
  final route = ref.watch(shikooWarpRouteProvider);
  final pasted = ref.watch(_pastedProvider);
  final revoked = ref.watch(_revokedProvider);
  final outsourced = {
    for (final linked in ref.watch(shikooAccountProvider).services)
      if (linked.outsourced) ?linked.profileId,
  };
  final loginRefused = ref.watch(_loginRefusedProvider);
  final specs = ref.watch(shikooCoreSpecsProvider);
  final tunnel = ref.watch(shikooTunnelProvider);
  final openvpnHere = offeredHere(
    const {'type': 'openvpn'},
    specs,
    tunnel: tunnel,
  );
  final unnamed = [
    for (final profile in ref.watch(profilesProvider))
      if (_nameOf(profile).isEmpty) profile.id,
  ];
  ShikooService of(Profile profile) => _serviceFrom(
    profile,
    extras: extras[profile.id],
    refresh: refreshing[profile.id] ?? ShikooRefresh.idle,
    leg: legs[profile.id],
    bridgeLeg: bridgeLegs.contains(profile.id),
    pasted: pasted.contains(profile.id),
    revoked: revoked.contains(profile.id),
    number: unnamed.indexOf(profile.id) + 1,
    outsourced: outsourced.contains(profile.id),
    loginRefused: loginRefused.contains(profile.id),
    notHere: outsourced.contains(profile.id) && !openvpnHere,
  );

  final group = _mainGroup(ref);
  final round = ref.watch(_roundProvider);
  final pings = ref.watch(_pingsProvider);
  final orders = ref.watch(_orderProvider);
  final fresh = ref.watch(_freshProvider);
  final byName = {
    for (final proxy in _serversOf(group, specs, tunnel)) proxy.name: proxy,
  };
  final chosen = group == null
      ? null
      : ref.watch(_wantedProvider) ??
            ref.watch(selectedMapProvider)[group.name];
  final selected = byName.containsKey(chosen) ? chosen : null;
  final switching = ref.watch(_switchProvider);
  final switchService = ref.watch(_switchServiceProvider);
  final choices = ref.watch(shikooCoresProvider);
  final sources = ref.watch(_sourcesProvider);
  final carrying = ref.watch(_carryingProvider);
  List<ShikooServer> listOf(
    int? id,
    Map<String, String> types,
    Map<String, Map<String, dynamic>> sources,
    _Round round, {
    Set<String> fresh = const {},
    bool loaded = true,
  }) {
    bool testing(String name) =>
        round.pending.contains(name) ||
        (switching?.stage == ShikooSwitchStage.moving &&
            switching?.to == name &&
            switchService == id);
    ShikooCore coreOf(String name) => loaded
        ? runningCore(
            sources[name],
            types[name]!,
            choices,
            specs: specs,
            tunnel: tunnel,
            carried: name != selected || carrying == null || intent.connecting
                ? null
                : carrying.server == name
                ? carrying.core
                : '',
          )
        : coreFor(sources[name]!, choices, specs: specs, tunnel: tunnel);
    return [
      for (final name in keepOrder(orders[id] ?? const [], [...types.keys]))
        ShikooServer(
          name: name,
          type: types[name]!,
          ping: testing(name) ? null : pings[id]?[name],
          testing: testing(name),
          fresh: fresh.contains(name),
          protocol: protocolOf(sources[name] ?? {'type': types[name]}),
          core: coreOf(name),
          viaBridge:
              loaded &&
              route.via.contains(name) &&
              !ownsTunnel(
                coreFor(
                  sources[name] ?? {'type': types[name]},
                  choices,
                  specs: specs,
                  tunnel: tunnel,
                ),
                specs,
              ),
        ),
    ];
  }

  final servers = listOf(
    profile?.id,
    {for (final proxy in byName.values) proxy.name: proxy.type},
    sources[profile?.id] ?? const {},
    round,
    fresh: fresh,
  );
  final ids = {for (final profile in ref.watch(profilesProvider)) profile.id};
  final open = ref.watch(_openProvider);
  final opened = ref.watch(_openedProvider);
  final openRound = ref.watch(_openRoundProvider);
  ShikooOpened? openedView(_Opened opened) {
    // Moving into it, the core loads it only later: until the move lands its card keeps this list.
    final landing =
        switching?.stage == ShikooSwitchStage.moving &&
        switchService == opened.id;
    if ((opened.id == profile?.id && !landing) || !ids.contains(opened.id)) {
      return null;
    }
    final servers = listOf(
      opened.id,
      {
        for (final MapEntry(:key, :value) in opened.proxies.entries)
          key: '${value['type']}',
      },
      opened.proxies,
      openRound,
      loaded: false,
    );
    return (
      id: opened.id,
      servers: servers,
      pinging: _progress(openRound, servers),
      sorted: (orders[opened.id] ?? const []).isNotEmpty,
    );
  }

  return ShikooState(
    connection: deriveConnection(
      connecting: intent.connecting,
      running: runTime != null || nativeStart != null,
      error: intent.error,
      blocked: intent.busyPort != null || intent.helperFailed,
    ),
    // ponytail: wall clock, negative once the clock moves back mid-tunnel; needs elapsedRealtime from Kotlin.
    connectedFor: nativeStart != null
        ? DateTime.now().difference(nativeStart)
        : Duration(milliseconds: runTime ?? 0),
    isTV: ref.watch(shikooTvProvider),
    service: profile == null ? null : of(profile),
    others: [
      for (final other in ref.watch(profilesProvider))
        if (other.id != profile?.id) of(other),
    ],
    servers: servers,
    selected: selected,
    lastError: intent.error,
    pick: derivePick(
      selected: selected != null,
      waiting: intent.waiting,
      noAnswer:
          intent.error == ShikooError.noServer ||
          (round.ended && !servers.any((server) => (server.ping ?? 0) > 0)),
    ),
    pinging: _progress(round, servers),
    refresh: refreshing[profile?.id] ?? ShikooRefresh.idle,
    notice: ref.watch(_noticeProvider),
    waiting: intent.waiting,
    switching: switching,
    sorted: (orders[profile?.id] ?? const []).isNotEmpty,
    open: ids.contains(open) ? open : null,
    opened: opened == null ? null : openedView(opened),
    order: ref.watch(serviceOrderProvider),
    landed: ref.watch(_landedProvider),
    busyPort: intent.busyPort,
    helperFailed: intent.helperFailed,
    iranDirect: ref.watch(shikooIranDirectProvider),
    cores: coreRows(
      {
        for (final id in ids)
          for (final server in sources[id]?.values ?? const <Never>[])
            protocolOf(server),
      },
      choices,
      specs: specs,
      tunnel: tunnel,
    ),
    coreSwitch: ref.watch(_coreSwitchProvider),
    bridge: (
      on: ref.watch(shikooWarpProvider),
      via: {
        for (final server in servers)
          if (server.viaBridge) server.name,
      },
      trying: ref.watch(_warpTryingProvider),
      failed: ref.watch(_warpFailedProvider),
      door: ref.watch(_warpDoorProvider),
    ),
    connectedNoTraffic: ref.watch(_noTrafficProvider),
  );
});

({int done, int total})? _progress(_Round round, List<ShikooServer> servers) =>
    round.total == 0
    ? null
    : (
        done: servers
            .where((server) => !round.pending.contains(server.name))
            .length,
        total: servers.length,
      );

final shikooControllerProvider = Provider<ShikooController>(
  ShikooController.new,
);

/// The desktop has no VPN service: `setRunning` returns once the core took the start, and a dead core takes the tunnel.
final nativeRunTimeProvider = Provider<Future<DateTime?> Function()>(
  (ref) => () async {
    if (service case final android?) return android.getRunTime();
    final ms = ref.read(runTimeProvider);
    if (ms == null || ref.read(coreStatusProvider) != CoreStatus.connected) {
      return null;
    }
    final tun = ref.read(patchClashConfigProvider).tun;
    if (tun.enable && !await ref.read(tunUpProvider)(tun.device)) return null;
    return DateTime.now().subtract(Duration(milliseconds: ms));
  },
);

final nativeStartFailedProvider = Provider<bool Function()>(
  (_) =>
      () => service?.startFailed ?? false,
);

/// The failed start was the official OpenVPN engine's AUTH_FAILED.
final nativeLoginRefusedProvider = Provider<bool Function()>(
  (_) =>
      () => service?.loginRefused ?? false,
);

final switchHoldProvider = Provider<Future<void> Function()>(
  (_) =>
      () async => service?.holdForSwitch(),
);

// ponytail: trusts the panel's rules to send FlClash's IP lookups to the selected server.
// The app is outside an owner core's VPN, so there the server's own handshake answers (core/shikoo_wg.go).
final trafficPassesProvider = Provider<Future<bool> Function()>(
  (ref) => () async {
    final server = ref.read(shikooStateProvider).selectedServer;
    if (server != null &&
        ownsTunnel(server.core, ref.read(shikooCoreSpecsProvider))) {
      final delay = await ref
          .read(coreHandlerProvider)
          .getDelay('', server.name);
      return (delay?.value ?? 0) > 0;
    }
    return (await request.checkIp()).data != null;
  },
);

/// FlClash loads a newly current profile in the next frame (CoreManager); an apply asked after
/// that frame queues behind that load and returns once the core holds the profile.
final serviceAppliedProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await SchedulerBinding.instance.endOfFrame;
    await ref.read(setupActionProvider.notifier).applyProfile(silence: true);
  },
);

/// Polls [runTime] until native reports a running tunnel. Flutter's own run state is set
/// optimistically before the service starts (engine map section 4), so only native is proof.
Future<DateTime?> waitForTunnel(
  Future<DateTime?> Function() runTime, {
  required Duration timeout,
  required bool Function() stillWanted,
  bool Function() paused = _never,
  bool Function() failed = _never,
  Duration every = const Duration(seconds: 1),
}) async {
  final waited = Stopwatch();
  while (stillWanted()) {
    if (await runTime() case final start?) return start;
    if (failed()) return null;
    paused() ? waited.stop() : waited.start();
    if (waited.elapsed >= timeout) return null;
    await Future<void>.delayed(every);
  }
  return null;
}

bool _never() => false;

ShikooService _serviceFrom(
  Profile profile, {
  _Extras? extras,
  ShikooRefresh refresh = ShikooRefresh.idle,
  ShikooLeg? leg,
  bool bridgeLeg = false,
  bool pasted = false,
  bool revoked = false,
  int number = 1,
  bool outsourced = false,
  bool loginRefused = false,
  bool notHere = false,
}) {
  final info = profile.subscriptionInfo;
  return ShikooService(
    id: profile.id,
    name: _nameOf(profile),
    usedBytes: (info?.upload ?? 0) + (info?.download ?? 0),
    totalBytes: info?.total ?? 0,
    expire: (info?.expire ?? 0) > 0
        ? DateTime.fromMillisecondsSinceEpoch(info!.expire * 1000)
        : null,
    announce: extras?.announce,
    supportUrl: extras?.supportUrl,
    account: extras?.account,
    updatedAt: profile.lastUpdateDate,
    usageKnown: info != null && !outsourced,
    refresh: refresh,
    leg: leg,
    bridgeLeg: bridgeLeg,
    pasted: pasted,
    revoked: revoked,
    number: number < 1 ? 1 : number,
    outsourced: outsourced,
    loginRefused: loginRefused,
    notHere: notHere,
  );
}

bool profileFinished(Profile profile) => _serviceFrom(profile).finished;

String _nameOf(Profile profile) =>
    profile.label == '${profile.id}' ? '' : profile.label;

String usernameOf(String name) => name.split(' · ').first.trim();

final _infoRowUser = RegExp(r'🆔[^(\n]*\(([^)\n]+)\)');

/// The live panel titles every account "Shi"; the account is in the file name or first row.
String? accountOf({String? file, String? title, required String body}) =>
    [
          file,
          _infoRowUser.firstMatch(body)?[1],
          if (title != null && title.contains(' · ')) usernameOf(title),
        ]
        .map((user) => user?.trim())
        .firstWhereOrNull((user) => user?.isNotEmpty ?? false);

String serviceName(String? title, String? user) =>
    title != null && title.contains(' · ') ? title : user ?? '';

String? _fileName(String? disposition) {
  try {
    return getFileNameForDisposition(disposition);
  } on ArgumentError {
    // A `filename*` FlClash cannot percent-decode, such as `%ZZ`.
    return null;
  }
}

Profile? serviceOf(List<Profile> profiles, String url, String? user) =>
    profiles.firstWhereOrNull(
      (profile) => normalLink(profile.url) == normalLink(url),
    ) ??
    (user == null
        ? null
        : profiles.firstWhereOrNull(
            (profile) =>
                usernameOf(profile.label) == user &&
                Uri.tryParse(profile.url)?.host == Uri.tryParse(url)?.host,
          ));

/// FlClash would add a Latin "(1)" to a name another service has.
String unusedName(String name, Set<String> taken) {
  if (name.isEmpty) return name;
  var unused = name;
  for (var n = 2; taken.contains(unused); n++) {
    unused =
        '$name ${String.fromCharCodes(n.toString().codeUnits.map((c) => c + 0x06C0))}';
  }
  return unused;
}

String _sorted(Iterable<String> names) => (names.toList()..sort()).join('\n');

SubscriptionInfo? _subscriptionInfo(String? header) {
  if (header == null) return null;
  try {
    return SubscriptionInfo.formHString(header);
  } on RangeError {
    // FlClash's parser throws on a segment without "=", such as a trailing ";".
    return const SubscriptionInfo();
  }
}

/// Windows cannot keep the app out of a tunnel an owner core holds, so the app's direct requests take mihomo's port,
/// whose DIRECT rules leave beside the tunnel. Android keeps the app in every VPN too.
String? ownerAside(ProviderReader read, Uri url) {
  final core = read(shikooStateProvider).selectedServer?.core;
  if (core == null ||
      read(shikooCoreSpecsProvider)[core]!.shape != ShikooShape.ownsTunnel) {
    return null;
  }
  final proxy = FlClashHttpOverrides.findProxyForReader(read, url);
  return proxy == 'DIRECT' ? null : proxy;
}

Future<Response<Uint8List>> _get(
  String url,
  String? proxy, {
  Duration? timeout,
}) async {
  final dio = Dio()
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        ..userAgent = globalState.ua
        ..findProxy = (_) => proxy ?? 'DIRECT',
    );
  try {
    return await dio
        .get<Uint8List>(url, options: Options(responseType: ResponseType.bytes))
        .timeout(timeout ?? subscriptionTimeout);
  } catch (error) {
    commonPrint.log(
      'subscription ${proxy == null ? 'direct' : 'server'} error ${compactError(error)}',
      logLevel: LogLevel.warning,
    );
    rethrow;
  } finally {
    dio.close(force: true);
  }
}

/// dart:io now and then fails a reply whose server closed right after it, though every byte came (`unknown`, no
/// answer): one more try. Not after a timeout or a refused connection, so a phone with no internet waits once.
Future<Response<Uint8List>> _getAgain(String url, String? proxy) async {
  try {
    return await _get(url, proxy);
  } on DioException catch (error) {
    if (error.type == DioExceptionType.unknown && error.response == null) {
      return _get(url, proxy);
    }
    rethrow;
  }
}

@visibleForTesting
Duration subscriptionTimeout = const Duration(seconds: 30);

/// Never row 1, the core's fallback: with connect pressed the first ordinary whole test, as it stays, else the fastest.
String? pickNow({
  required List<String> names,
  required int? Function(String name) ping,
  required bool pinging,
  required bool urgent,
  required bool Function(String name) handshake,
}) => pinging && !urgent
    ? null
    : fastest(
        names,
        (name) => pinging && (handshake(name) || multiplied(name))
            ? null
            : ping(name),
        handshake: handshake,
      );

/// While off, a selection that cannot connect gives way to one that can, else to the last ended.
int? serviceInstead(ShikooState state) {
  final current = state.service;
  final busy = {ShikooConnection.on, ShikooConnection.connecting};
  if (current?.ended == null || busy.contains(state.connection)) return null;
  final usable = state.listed.firstWhereOrNull(
    (other) => other.id != current!.id && other.ended == null,
  );
  if (usable != null) return usable.id;
  final latest = finishedOrder([
    for (final service in [current!, ...state.others])
      if (service.finished) finishedOf(service),
  ], shikooNow()).firstOrNull?.profileId;
  return latest == current.id ? null : latest;
}

class ShikooController {
  // Microtasks: Riverpod forbids writing other providers while this one is being built.
  ShikooController(this._ref) {
    _ref.onDispose(() {
      _switched?.cancel();
      _coreSwitched?.cancel();
      _ownerWatch?.cancel();
    });
    _ref.listen(shikooStateProvider.select(serviceInstead), (_, id) {
      if (id != null) scheduleMicrotask(() => selectService(id));
    }, fireImmediately: true);
    _ref.listen(patchClashConfigProvider.select((config) => config.mode), (
      _,
      mode,
    ) {
      // In global mode the GLOBAL group sits on DIRECT: "connected" with nothing tunnelled.
      if (mode != Mode.rule) {
        scheduleMicrotask(() => _setup.changeMode(Mode.rule));
      }
    }, fireImmediately: true);
    _ref.listen(
      shikooStateProvider.select(
        (s) => (s.service?.id, _sorted(s.servers.map((e) => e.name))),
      ),
      (previous, list) {
        final (service, names) = list;
        if (previous?.$1 != null && previous!.$1 != service) {
          _arrived = false;
          scheduleMicrotask(() {
            _setNotice(null);
            _forgetRound();
          });
        }
        if (!_arrived && service != null && names.isNotEmpty) {
          scheduleMicrotask(_arrive);
        }
        if (service != null && names.isNotEmpty) {
          scheduleMicrotask(_loadSources);
        }
      },
      fireImmediately: true,
    );
    _ref.listen(
      shikooStateProvider.select(
        (s) => [for (final x in s.listed) '${x.id} ${x.updatedAt}'].join(','),
      ),
      (_, _) => scheduleMicrotask(_loadSources),
      fireImmediately: true,
    );
    _ref.listen(initProvider, (_, init) {
      if (init) scheduleMicrotask(_loadSources);
    });
    // An update that changes the key or address of the server an owner core carries; Windows' Go rebuilds in place.
    _ref.listen(_serverSourceProvider, (was, now) {
      if (!_ref.read(shikooDesktopProvider) &&
          was != null &&
          (was.id, was.name) == (now.id, now.name) &&
          was.source != null &&
          now.source != null &&
          !const DeepCollectionEquality().equals(was.source, now.source)) {
        scheduleMicrotask(() => unawaited(_rebuildOwnerTunnel()));
      }
    });
    _ref.listen(runTimeProvider.select((time) => time != null), (_, running) {
      scheduleMicrotask(
        running
            ? () {
                if (_ref.read(_noticeProvider) is SelectedGone) {
                  _setNotice(null);
                }
                // A start the app did not make (the tile, always-on) came up; its own connects clear both in _start.
                final intent = _ref.read(_intentProvider);
                if (!intent.connecting) {
                  _loginRefused(_current, refused: false);
                  if (intent.error != null) _set(const _Intent());
                }
                _reconcile();
                unawaited(_checkCarrying());
                _watchOwner(true);
              }
            : () {
                _nativeStart(null);
                _endSwitch();
                _watchOwner(false);
                // Any end of the connection lifts the hold: the system's Disconnect, the notification or the tile.
                if (!_fallingBack) {
                  _ref.read(shikooOwnerHeldOffProvider.notifier).set(false);
                }
                if (_endOwnerRoad()) unawaited(_rebuildClients());
              },
      );
    });
    _ref.listen(
      shikooStateProvider.select(
        (s) => s.servers.isEmpty ? null : streamingOnly(s.selected ?? ''),
      ),
      (_, on) {
        if (on != null) _routeStreaming(on);
      },
      fireImmediately: true,
    );
    _ref.listen(
      shikooStateProvider.select(
        (s) => s.connection == ShikooConnection.on
            ? (s.service?.id, s.selected)
            : null,
      ),
      (_, now) => scheduleMicrotask(() => unawaited(_checkTraffic(now?.$2))),
    );
    _ref.listen(coreStatusProvider, (was, now) {
      if (was == CoreStatus.connected &&
          now == CoreStatus.disconnected &&
          _ref.read(shikooDesktopProvider)) {
        _deaths++;
        scheduleMicrotask(_answerDeaths);
      }
    });
    app?.onVpnConsent = onVpnConsent;
    scheduleMicrotask(() => _ref.read(_extrasProvider.notifier).load());
    scheduleMicrotask(_loadPasted);
    scheduleMicrotask(() => _ref.read(savedOrderProvider.notifier).load());
    scheduleMicrotask(() => _ref.read(shikooModeProvider.notifier).load());
    scheduleMicrotask(() async {
      final stored = (await SharedPreferences.getInstance()).getString(
        _appPicksKey,
      );
      if (stored == null) return;
      _appPickByService = {
        ...(jsonDecode(stored) as Map<String, dynamic>).cast<String, String>(),
        ..._appPickByService,
      };
    });
    scheduleMicrotask(() async {
      final start = await _nativeRunTime();
      if (start == null || _ref.read(runTimeProvider) != null) return;
      _nativeStart(start);
    });
  }

  final Ref _ref;

  bool foreground = true;
  static const _appPicksKey = 'shikoo.appPicks';

  Map<String, String> _appPickByService = const {};
  int _attempt = 0;

  Future<void>? _rebuilding;
  bool _rebuildAgain = false;
  Future<void>? _iranApplying;
  bool _iranAgain = false;
  Future<void>? _iranSaved;

  /// main.dart clears the streaming rules at launch, so none are in the database until a selection asks.
  bool _streamingRouted = false;
  Future<void> _streamingRoute = Future.value();
  int _trafficNo = 0;

  Timer? _ownerWatch;
  DateTime? _ownerRebuiltAt;
  bool _fallingBack = false;

  /// Bumped by every round and by a switch of service, whose round's answers go unread.
  int _roundNo = 0;
  bool _pinging = false;
  bool _roundList = false;

  bool _again = false;

  bool _checkNext = false;

  /// This round's answers: only these choose while it runs.
  final _heard = <String>{};

  bool _arrived = false;
  bool _pingOnArrival = false;

  int _openNo = 0;

  int _tap = 0;
  int _chooseNo = 0;

  /// The core runs each change on its own goroutine: two at once may land in either order.
  Future<void>? _changing;

  Future<ShikooAdmin>? _admin;
  final _revives = <DateTime>[];
  Future<void>? _reviving;
  int _deaths = 0;
  String? _pickInCore;
  Timer? _switched;
  Timer? _coreSwitched;
  int _coreMove = 0;
  String? _awaiting;
  DateTime _awaitingUntil = DateTime(0);

  /// The selection an update just took away, for the notice that names it.
  String? _removed;
  final _refreshing = <int, Future<void>>{};
  Future<void>? _refreshingDue;
  final _renewed = <int>{};
  final _renewedAt = <int, DateTime>{};
  final _manual = <int>{};

  SetupAction get _setup => _ref.read(setupActionProvider.notifier);

  ProxiesAction get _proxies => _ref.read(proxiesActionProvider.notifier);

  Group? get _group => _ref.read(currentGroupsStateProvider).value.firstOrNull;

  void _set(_Intent intent) => _ref.read(_intentProvider.notifier).set(intent);

  int? get _current => _ref.read(currentProfileIdProvider);

  String get _service => '$_current';

  String? get _appPick => _appPickByService[_service];

  void _pickedByApp(String? name) {
    final others = {..._appPickByService}..remove(_service);
    _savePicks(name == null ? others : {...others, _service: name});
  }

  void _savePicks(Map<String, String> picks) {
    _appPickByService = picks;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString(_appPicksKey, jsonEncode(picks)),
      ),
    );
  }

  Future<DateTime?> _nativeRunTime() => _ref.read(nativeRunTimeProvider)();

  void _nativeStart(DateTime? start) =>
      _ref.read(_nativeStartProvider.notifier).set(start);

  bool get _running =>
      _ref.read(runTimeProvider) != null ||
      _ref.read(_nativeStartProvider) != null;

  /// SelectedGone stays till the customer picks a server or connects (Sam, 2026-10-30).
  void _notice(ShikooNotice? notice) {
    if (_ref.read(_noticeProvider) is! SelectedGone) _setNotice(notice);
  }

  void _setNotice(ShikooNotice? notice) =>
      _ref.read(_noticeProvider.notifier).set(notice);

  /// News leaves with the app or the next update; a failed update stays until one succeeds.
  void clearNews() {
    if (_ref.read(_noticeProvider) is! RefreshFailed) _notice(null);
    _ref.read(_freshProvider.notifier).set(const {});
  }

  /// A switch's outcome leaves with the app as well, one under way does not.
  void onBackground() {
    clearNews();
    _ref.read(_landedProvider.notifier).set(null);
    if (_ref.read(_switchProvider)?.stage != ShikooSwitchStage.moving) {
      _endSwitch();
    }
  }

  void _switching(ShikooSwitch? next, [int? service]) {
    _ref.read(_switchProvider.notifier).set(next);
    _ref
        .read(_switchServiceProvider.notifier)
        .set(next == null ? null : service);
  }

  int _endSwitch() {
    _switched?.cancel();
    _switching(null);
    return ++_tap;
  }

  List<Proxy> _offered(Group? group) =>
      _serversOf(group, _ref.read(shikooCoreSpecsProvider), _tunnel);

  List<String> _names(Group? group) => [
    for (final proxy in _offered(group)) proxy.name,
  ];

  String _testUrl(Group group) => _ref.read(realTestUrlProvider(group.testUrl));

  int? _ping(String name) => _pingOf(_current, name);

  int? _pingOf(int? service, String name) =>
      _ref.read(_pingsProvider)[service]?[name];

  String? _validSelection() {
    final group = _group;
    if (group == null) return null;
    final chosen = _ref.read(selectedMapProvider)[group.name];
    return _names(group).contains(chosen) ? chosen : null;
  }

  /// The pick is in the subscription but not offered in this mode (Windows' proxy mode has no OpenVPN): it stays the customer's.
  bool get _held {
    final group = _group;
    final chosen = group == null
        ? null
        : _ref.read(selectedMapProvider)[group.name];
    return _validSelection() == null &&
        (group?.all.any((proxy) => proxy.name == chosen) ?? false);
  }

  Future<void> connect() {
    if (_ref.read(_noticeProvider) is SelectedGone) _setNotice(null);
    return _connect(setAside: true);
  }

  Future<void> _connect({required bool setAside}) async {
    if (_ref.read(currentProfileProvider) == null ||
        (_ref.read(shikooStateProvider).service?.notHere ?? false)) {
      return;
    }
    if (!await _coreReady()) return;
    if (setAside) _setAsideMultiplied();
    if (_validSelection() != null) return _start();
    _find();
  }

  void _find({bool list = false}) {
    _set(const _Intent(connecting: true, waiting: true));
    unawaited(pingAll(list: list));
  }

  void _arrive() {
    if (_arrived || _staleGroups || _names(_group).isEmpty) return;
    _arrived = true;
    final ping = _pingOnArrival;
    _pingOnArrival = false;
    final waiting = _ref.read(_intentProvider).waiting;
    if (waiting && !_running) _setAsideMultiplied();
    if (_validSelection() == null && (_running || waiting)) {
      return _find(list: ping);
    }
    final start = waiting && !_running;
    if (waiting) start ? unawaited(_start()) : _set(const _Intent());
    if (ping) return unawaited(pingAll());
    if (!start && _running) unawaited(_checkSelected());
  }

  /// The old service's round goes unread; numbers and order stay with the service they measured.
  void _forgetRound() {
    _roundNo++;
    _pinging = false;
    _again = false;
    _checkNext = false;
    _heard.clear();
    _ref.read(_roundProvider.notifier).set(_noRound);
    if (_ref.read(_openProvider) == _current) {
      _openNo++;
      _ref.read(_openRoundProvider.notifier).set(_noRound);
    }
    if (_ref.read(_intentProvider).error == ShikooError.noServer) {
      _set(const _Intent());
    }
  }

  /// Windows has no service to block on the official OpenVPN engine's start: Go says when its session is up or why it ended.
  bool get _askGo =>
      _ref.read(shikooDesktopProvider) &&
      _ref.read(shikooStateProvider).selectedServer?.core == ShikooCore.openvpn;

  Future<DateTime?> _sessionRunTime() async {
    final word = await _ref.read(ownerSessionProvider)();
    _ref.read(_sessionProvider.notifier).set(word);
    return word == _sessionUp ? _nativeRunTime() : null;
  }

  bool _sessionEnded() =>
      const {'failed', _sessionRefused}.contains(_ref.read(_sessionProvider));

  Future<void> _start([ShikooError? error]) async {
    final attempt = ++_attempt;
    _set(_Intent(connecting: true, error: error));
    final refused = await _desktopReady(attempt);
    if (attempt != _attempt) return;
    if (refused != null) return _set(refused);
    bool started;
    try {
      started = await _setup.setRunning(
        true,
        initialize: !_ref.read(initProvider),
      );
    } catch (_) {
      started = false;
    }
    final askGo = _askGo;
    final since = started
        ? await waitForTunnel(
            askGo ? _sessionRunTime : _nativeRunTime,
            timeout: connectWait,
            stillWanted: () => attempt == _attempt,
            paused: () => !foreground,
            failed: askGo
                ? _sessionEnded
                : _ref.read(nativeStartFailedProvider),
          )
        : null;
    if (attempt != _attempt) return;
    if (since != null) {
      _nativeStart(since);
      _loginRefused(_current, refused: false);
      await _checkCarrying();
      if (attempt != _attempt) return;
      _set(_Intent(error: error));
      unawaited(_checkSelected());
      return;
    }
    if (started &&
        (_ref.read(nativeLoginRefusedProvider)() ||
            (askGo && _ref.read(_sessionProvider) == _sessionRefused)) &&
        (_ref.read(shikooStateProvider).service?.outsourced ?? false)) {
      _loginRefused(_current, refused: true);
    }
    _set(const _Intent(error: ShikooError.connectTimeout));
    await _setup.setRunning(false);
  }

  /// FlClash's flags for the mode are set only here: with TUN on, each apply asks for the helper service.
  Future<_Intent?> _desktopReady(int attempt) async {
    if (!_ref.read(shikooDesktopProvider) || _running) return null;
    bool stale() => attempt != _attempt;
    final mode = _ref.read(shikooModeProvider);
    final port = _ref.read(patchClashConfigProvider).mixedPort;
    if (mode.systemProxy && !await _ref.read(localPortFreeProvider)(port)) {
      return _Intent(busyPort: port);
    }
    // Only the service's core opens TUN; with no core yet, as mid-restart, restartCore() below joins that restart.
    bool foreign() => _ref.read(coreOwnerProvider)() != CoreProcessOwner.helper;
    final authorized = _ref.read(authorizedTunEnableProvider.notifier);
    // shortcut: a service still too slow for one ping here gets the admin prompt, retry the ping first if reports show it.
    if (mode.tun &&
        (foreign() || authorized.value != TunAuthorizationState.authorized)) {
      final admin = await (_admin ??= _ref
          .read(tunAuthorizeProvider)()
          .whenComplete(() => _admin = null));
      switch (admin) {
        case ShikooAdmin.refused:
          return const _Intent(error: ShikooError.vpnRefused);
        case ShikooAdmin.failed:
          return const _Intent(helperFailed: true);
        case ShikooAdmin.installed:
        case ShikooAdmin.ready:
          break;
      }
      authorized.value = TunAuthorizationState.authorized;
    }
    if (stale()) return null;
    if (mode.tun && foreign()) {
      final restarted = await _restartCore();
      if (stale()) return null;
      if (!restarted || foreign()) return const _Intent(helperFailed: true);
    }
    final tunWas = _ref.read(patchClashConfigProvider).tun.enable;
    _ref
        .read(networkSettingProvider.notifier)
        .update((s) => s.copyWith(systemProxy: mode.systemProxy));
    _ref
        .read(patchClashConfigProvider.notifier)
        .update((c) => c.copyWith.tun(enable: mode.tun));
    // The core starts its listeners from the config it holds; FlClash would send this flag 600 ms after the start.
    if (tunWas != mode.tun) {
      await _setup.applyProfile(force: true, silence: true);
    }
    return null;
  }

  Future<void> setMode(ShikooMode mode) async {
    if (!_ref.read(shikooDesktopProvider)) return;
    await _ref.read(shikooModeProvider.notifier).save(mode);
    if (!_running && !_ref.read(_intentProvider).connecting) {
      return _set(const _Intent());
    }
    await _reconnect();
  }

  /// A switch of server or core: the VPN service keeps traffic blocked between the stop and the start.
  Future<void> _reconnect() async {
    _reconnects++;
    try {
      await _ref.read(switchHoldProvider)();
      await disconnect();
      await connectAgain();
    } finally {
      _reconnects--;
    }
  }

  /// The app's own start after its own stop, as a rebuild or a failed install: the pick stays, and SelectedGone holds it.
  Future<void> connectAgain() async {
    if (_ref.read(_noticeProvider) is! SelectedGone && !_held) {
      await _connect(setAside: false);
    }
  }

  /// The app's own stop around [step], as the Windows installer's: it counts as up, and [startAgain] keeps the pick.
  Future<void> whileStopped(
    Future<void> Function() step, {
    required bool Function() startAgain,
  }) async {
    _reconnects++;
    var after = Future<void>.value();
    try {
      await disconnect();
      await step();
      if (startAgain()) after = connectAgain();
    } finally {
      unawaited(after.whenComplete(() => _reconnects--));
    }
  }

  int _reconnects = 0;

  bool get _upOrStarting =>
      _running || _reconnects > 0 || _ref.read(_intentProvider).connecting;

  /// A core behind mihomo only needs the config again; a new tunnel owner, a reconnect. Connected, a move shows as a
  /// server switch, done only once the core carrying the server is the pick: a failed engine leaves it on mihomo.
  Future<void> setCore(ShikooProtocol protocol, ShikooCore core) async {
    final name = _validSelection();
    final was = _ref.read(shikooStateProvider).selectedServer?.core;
    final before = name == null ? null : _tunnelKeyOf(name);
    await _ref.read(shikooCoresProvider.notifier).set(protocol, core);
    _ref
        .read(shikooDiagProvider)
        .add('T', 'core ${protocol.name} ${core.name}');
    if (_ref.read(currentProfileProvider) == null) return;
    final to = name == null ? null : _coreFor(name);
    final move = ++_coreMove;
    final told =
        _running && !_ref.read(_intentProvider).connecting && to != was;
    void show(ShikooSwitchStage stage) =>
        _coreSwitching((protocol: protocol, to: to!, stage: stage), move);
    if (told) show(ShikooSwitchStage.moving);
    await _setup.applyProfile(silence: true);
    if (name == null) return;
    final up = _running || _ref.read(_intentProvider).connecting;
    if (up && _tunnelKeyOf(name) != before) await _reconnect();
    if (!told) return;
    final group = _group;
    final landed = _ref.read(shikooStateProvider).selectedServer?.core == to;
    final passes =
        landed &&
        _running &&
        group != null &&
        await _probe(_testUrl(group), name) != null;
    show(passes ? ShikooSwitchStage.done : ShikooSwitchStage.failed);
  }

  /// No answer reads as none: the server shows mihomo, a switch to its owner core fails, [ownerAside] stays off.
  Future<void> _checkCarrying() async {
    final carrying =
        await _ref.read(ownerCarryingProvider)() ?? (core: '', server: '');
    if (!_running) return;
    final selected = _ref.read(shikooStateProvider).selected;
    _ownerRoad =
        _ownerRoad ||
        carrying.server.isNotEmpty ||
        (selected != null && _tunnelKeyOf(selected) != ShikooCore.mihomo.name);
    _ref.read(_carryingProvider.notifier).set(carrying);
  }

  void _coreSwitching(ShikooCoreSwitch next, int move) {
    if (move != _coreMove) return;
    _coreSwitched?.cancel();
    final cell = _ref.read(_coreSwitchProvider.notifier)..set(next);
    if (next.stage != ShikooSwitchStage.moving) {
      _coreSwitched = Timer(switchedFor, () => cell.set(null));
    }
  }

  bool get _tunnel => _ref.read(shikooTunnelProvider);

  ShikooCore _coreFor(String name, [_Opened? other]) {
    final running = _offered(
      _group,
    ).firstWhereOrNull((proxy) => proxy.name == name)?.type;
    return coreFor(
      other?.proxies[name] ??
          _ref.read(_sourcesProvider)[_current]?[name] ??
          {'type': running},
      _ref.read(shikooCoresProvider),
      specs: _ref.read(shikooCoreSpecsProvider),
      tunnel: _tunnel,
    );
  }

  bool _handshake(String name) =>
      _coreFor(name) == ShikooCore.openvpn &&
      !_ref.read(shikooOwnerHeldOffProvider);

  String _tunnelKeyOf(String name, [_Opened? other]) => tunnelKey(
    _coreFor(name, other),
    name,
    specs: _ref.read(shikooCoreSpecsProvider),
  );

  /// Connected, mihomo takes the new rules in place, and so does Windows' Go engine (core/shikoo_wg_windows.go).
  Future<void> setIranDirect(bool on) {
    _iranSaved = _ref.read(shikooIranDirectProvider.notifier).set(on);
    if (_iranApplying case final applying?) {
      _iranAgain = true;
      return applying;
    }
    return _iranApplying = () async {
      do {
        _iranAgain = false;
        await keepIranDirect(_ref.read(shikooIranDirectProvider));
        if (_running) await _setup.applyProfile(silence: true);
        await _iranSaved;
        if (!_ref.read(shikooDesktopProvider)) await _rebuildOwnerTunnel();
      } while (_iranAgain);
    }().whenComplete(() => _iranApplying = null);
  }

  /// An owner core reads Iran's routes and its server only as it builds the VPN: one rebuild at a time, last ask last.
  Future<void> _rebuildOwnerTunnel() {
    if (_rebuilding case final rebuilding?) {
      _rebuildAgain = true;
      return rebuilding;
    }
    return _rebuilding = () async {
      do {
        _rebuildAgain = false;
        final up = _running || _ref.read(_intentProvider).connecting;
        // The apply waits out an update's own: a refused config has stopped the app, and a start would land on mihomo.
        if (up &&
            _ref.read(shikooOwnerProvider) != null &&
            await _setup.applyProfile(silence: true)) {
          await _reconnect();
        }
      } while (_rebuildAgain);
    }().whenComplete(() => _rebuilding = null);
  }

  void _watchOwner(bool running) {
    _ownerWatch?.cancel();
    _ownerWatch = running
        ? Timer.periodic(ownerWatchEvery, (_) => unawaited(_checkOwnerAlive()))
        : null;
  }

  /// Every [ownerWatchEvery]: Go drops an engine whose device closed, so build the tunnel again, or within a minute hand it to mihomo.
  Future<void> _checkOwnerAlive() async {
    final carried = _ref.read(_carryingProvider)?.server ?? '';
    if (!_running ||
        carried.isEmpty ||
        _rebuilding != null ||
        _ref.read(_intentProvider).connecting) {
      return;
    }
    final carrying = await _ref.read(ownerCarryingProvider)();
    if (carrying == null || carrying.server.isNotEmpty || !_running) return;
    final now = DateTime.now();
    final again =
        _ownerRebuiltAt != null &&
        now.difference(_ownerRebuiltAt!) < ownerDeathWindow;
    _ownerRebuiltAt = now;
    if (!again) return _rebuildOwnerTunnel();
    if (!shikooOnlyCores.containsValue(_coreFor(carried))) {
      return _fallBackToMihomo();
    }
    final off = disconnect();
    _set(const _Intent(error: ShikooError.coreDown));
    await off;
  }

  Future<void> _fallBackToMihomo() async {
    _fallingBack = true;
    _ref.read(shikooOwnerHeldOffProvider.notifier).set(true);
    try {
      await _reconnect();
    } finally {
      _fallingBack = false;
    }
  }

  void onVpnConsent(String result) {
    if (!_ref.read(_intentProvider).connecting) return;
    _attempt++;
    _set(
      _Intent(
        error: result == 'missing'
            ? ShikooError.vpnMissing
            : ShikooError.vpnRefused,
      ),
    );
    unawaited(_setup.setRunning(false));
  }

  Future<void> disconnect() async {
    if (!_fallingBack) {
      _ref.read(shikooOwnerHeldOffProvider.notifier).set(false);
    }
    _attempt++;
    _endSwitch();
    _ref.read(_landedProvider.notifier).set(null);
    final took = _endOwnerRoad();
    _nativeStart(null);
    _set(const _Intent());
    await _setup.setRunning(false);
    if (took) await _rebuildClients();
  }

  /// Sticky until the rebuild: a later "none" from Go cannot undo a client `shikooOwnerTakes` closed.
  bool _ownerRoad = false;

  bool _endOwnerRoad() {
    final took = _ownerRoad;
    _ownerRoad = false;
    _ref.read(_carryingProvider.notifier).set(null);
    return took;
  }

  Future<void> _rebuildClients() =>
      _setup.applyProfile(force: true, silence: true);

  void forgetError() {
    final intent = _ref.read(_intentProvider);
    _set(_Intent(connecting: intent.connecting, waiting: intent.waiting));
  }

  bool get _coreUp => _ref.read(coreStatusProvider) == CoreStatus.connected;

  Future<bool> _restartCore() => _ref
      .read(coreActionProvider.notifier)
      .restartCore()
      .then((_) => true, onError: (Object _) => false);

  void _answerDeaths() {
    if (_deaths == 0) return;
    var clean = false;
    _reviving ??= _revive().then((_) => clean = true).whenComplete(() {
      _reviving = null;
      // One that threw before taking its deaths would start again at once, forever.
      if (clean) _answerDeaths();
    });
  }

  /// FlClash leaves a dead core down: its only restart is a dashboard button Shikoo never shows.
  Future<void> _revive() async {
    final attempt = _attempt;
    bool stale() => attempt != _attempt;
    final wanted = _running;
    if (wanted) _set(const _Intent(connecting: true));
    var up = false;
    while (_deaths > 0 && !stale()) {
      _deaths--;
      up = false;
      if (!_mayRevive() || !await _restartCore()) break;
      // A restart that joined one under way may return to the core it found dead: once more, no death.
      if (!_coreUp && _deaths == 0 && !await _restartCore()) break;
      if (!_coreUp) continue;
      up =
          !wanted ||
          await waitForTunnel(
                _carrying,
                timeout: connectTimeout,
                stillWanted: () => !stale() && _running && _coreUp,
              ) !=
              null;
    }
    if (stale()) return;
    _deaths = 0;
    if (up) {
      if (wanted) _set(const _Intent());
      _forgetRound();
      unawaited(wanted ? _checkSelected() : pingAll());
    } else if (wanted) {
      final off = disconnect();
      _set(const _Intent(error: ShikooError.coreDown));
      await off;
    }
  }

  bool _mayRevive() {
    final now = shikooNow();
    _revives.removeWhere((at) => now.difference(at) > coreReviveWindow);
    if (_revives.length >= coreRevives) return false;
    _revives.add(now);
    return true;
  }

  Future<DateTime?> _carrying() async {
    final since = await _nativeRunTime();
    if (since == null || !_ref.read(shikooModeProvider).systemProxy) {
      return since;
    }
    final port = _ref.read(patchClashConfigProvider).mixedPort;
    return await _ref.read(localPortFreeProvider)(port) ? null : since;
  }

  Future<bool> _coreReady() async {
    if (!_ref.read(shikooDesktopProvider) ||
        !_ref.read(initProvider) ||
        _ref.read(coreStatusProvider) != CoreStatus.disconnected) {
      return true;
    }
    final attempt = ++_attempt;
    _set(const _Intent(connecting: true));
    await _restartCore();
    if (attempt != _attempt) return false;
    if (_coreUp) return true;
    _set(const _Intent(error: ShikooError.coreStart));
    return false;
  }

  Future<void> forgetServices() async {
    await disconnect();
    final profiles = _ref.read(profilesActionProvider.notifier);
    for (final profile in [..._ref.read(profilesProvider)]) {
      await profiles.deleteProfile(profile.id);
    }
    await _ref.read(_extrasProvider.notifier).clear();
    _savePicks(const {});
    _setNotice(null);
    _forgetRound();
    openService(null);
    _ref.read(_pingsProvider.notifier).set(const {});
    _ref.read(_orderProvider.notifier).set(const {});
    _ref.read(_freshProvider.notifier).set(const {});
    _ref.read(_refreshesProvider.notifier).set(const {});
    await _ref.read(savedOrderProvider.notifier).save(const []);
  }

  /// The user's choice, which the app never replaces; connected, a dead one never gets the traffic.
  /// A [service] other than the one in use is the open card's: choosing there is choosing it too.
  Future<void> selectServer(String name, {int? service}) async {
    final elsewhere = service != null && service != _current;
    final other = elsewhere ? _ref.read(_openedProvider) : null;
    if (elsewhere &&
        (other == null ||
            other.id != service ||
            !other.proxies.containsKey(name))) {
      return;
    }
    final shift = _ref.read(_switchProvider);
    if (shift?.stage == ShikooSwitchStage.moving &&
        shift?.to == name &&
        _ref.read(_switchServiceProvider) == (other?.id ?? _current)) {
      return;
    }
    _ref
        .read(shikooDiagProvider)
        .add('T', 'server picked ${withoutFlags(name)}');
    final tap = _endSwitch();
    if (_ref.read(_noticeProvider)
        case SilentReplaced() || SelectedReplaced() || SelectedGone()) {
      _setNotice(null);
    }
    final from = _validSelection();
    final connected = _running && !_ref.read(_intentProvider).connecting;
    if (connected && from != null && (other != null || from != name)) {
      if (_tunnelKeyOf(from) == _tunnelKeyOf(name, other)) {
        return _switchTo(name, from, tap, other);
      }
      if (other == null) {
        await _choose(name, byApp: false);
      } else {
        await _moveTo(other, name);
        await _ref.read(serviceAppliedProvider)();
      }
      return _reconnect();
    }
    if (other != null) return _moveTo(other, name);
    await _choose(name, byApp: false);
    if (connected) await _checkSelected();
  }

  Future<void> _switchTo(
    String name,
    String from,
    int tap, [
    _Opened? other,
  ]) async {
    final home = _current;
    final target = other?.id ?? home;
    void show(ShikooSwitchStage stage) {
      if (tap != _tap) return;
      final now = stage == ShikooSwitchStage.failed ? _validSelection() : null;
      _switching((to: name, from: now ?? from, stage: stage), target);
      if (stage != ShikooSwitchStage.moving) {
        _switched = Timer(switchedFor, () => _switching(null));
      }
    }

    show(ShikooSwitchStage.moving);
    final mapping = other?.proxies[name];
    final url = other?.url ?? _testUrl(_group!);
    var ms = -1;
    await pingServers(
      [name],
      (name) => mapping == null ? _probe(url, name) : _probeOther(url, mapping),
      (_, answer) {
        ms = answer;
      },
    );
    if (tap != _tap) return;
    final running = _offered(
      _group,
    ).firstWhereOrNull((proxy) => proxy.name == name)?.type;
    if (mapping == null && running == null) return _switching(null);
    final source =
        mapping ??
        _ref.read(_sourcesProvider)[target]?[name] ??
        {'type': running};
    if (ms <= 0 && protocolOf(source) != ShikooProtocol.wireguard) {
      _setPing(target, name, -1);
      return show(ShikooSwitchStage.failed);
    }
    if (ms > 0) _setPing(target, name, ms);
    final before = other == null
        ? null
        : (
            selected: _ref
                .read(profilesProvider)
                .getProfile(other.id)
                ?.selectedMap[other.group],
            pick: _appPickByService['${other.id}'],
          );
    if (other == null) {
      await _choose(name);
    } else {
      _ref.read(_landedProvider.notifier).set((id: other.id, arrived: false));
      await _moveTo(other, name);
      await _ref.read(serviceAppliedProvider)();
    }
    if (ms <= 0) {
      // WireGuard pings can fail while it carries traffic (c19fdfc): real traffic decides.
      if (!await _ref.read(trafficPassesProvider)()) {
        if (_current == target && _validSelection() == name && _running) {
          if (other == null) {
            await _choose(from);
          } else if (home != null && before != null && tap == _tap) {
            await _use(home);
            _setChoice(other.id, other.group, before.selected, before.pick);
            _ref.read(_landedProvider.notifier).set(null);
          }
        }
        _setPing(target, name, -1);
        return show(ShikooSwitchStage.failed);
      }
      _setPing(target, name, math.max(_pingOf(target, name) ?? 0, 0));
    }
    if (tap != _tap) return;
    if (_current != target || _validSelection() != name) {
      return _switching(null);
    }
    _pickedByApp(null);
    show(ShikooSwitchStage.done);
    if (other != null && _ref.read(_landedProvider)?.id == other.id) {
      _ref.read(_landedProvider.notifier).set((id: other.id, arrived: true));
    }
  }

  /// The core loads [other] with [name] chosen already, so no other server of it gets traffic first.
  Future<void> _moveTo(_Opened other, String name) async {
    if (_ref.read(profilesProvider).getProfile(other.id) == null) return;
    clearNews();
    _setChoice(other.id, other.group, name, null);
    await _use(other.id);
  }

  /// A service's server as setup hands it to the core, and whether the app or the user chose it.
  void _setChoice(int id, String group, String? name, String? appPick) {
    final profile = _ref.read(profilesProvider).getProfile(id);
    if (profile == null) return;
    final selected = {...profile.selectedMap}..remove(group);
    _ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(selectedMap: {...selected, group: ?name}));
    _savePicks({
      ...{..._appPickByService}..remove('$id'),
      '$id': ?appPick,
    });
  }

  Future<void> _choose(String name, {bool? byApp}) async {
    final group = _group;
    if (group == null) return;
    final no = ++_chooseNo;
    if (_changing == null) _pickInCore = _appPick;
    if (byApp != null) _pickedByApp(byApp ? name : null);
    final pick = _appPick;
    final wanted = _ref.read(_wantedProvider.notifier);
    if (_changing case final earlier?) {
      wanted.set(name);
      await earlier;
      if (no != _chooseNo) return;
    }
    final change = _changing = _proxies
        .changeProxy(groupName: group.name, proxyName: name)
        .whenComplete(() => _changing = null);
    wanted.set(null);
    await change;
    _proxies.updateGroupsDebounce();
    final applied = _ref.read(selectedProxyNameProvider(group.name)) == name;
    if (applied) _pickInCore = pick;
    if (no != _chooseNo) return;
    if (!applied) _pickedByApp(_pickInCore);
    final intent = _ref.read(_intentProvider);
    final error = applied ? null : ShikooError.serverChange;
    if (intent.waiting && _validSelection() != null) {
      // Up already, as after a switch of service: the answer takes the traffic, no new start.
      return _running
          ? _set(_Intent(error: error))
          : unawaited(_start(byApp == false ? error : null));
    }
    final waiting = intent.waiting && _pinging;
    _set(
      _Intent(
        connecting: intent.waiting ? waiting : intent.connecting,
        waiting: waiting,
        error: error,
      ),
    );
  }

  void _reconcile() {
    final group = _group;
    if (group == null || _staleGroups || _validSelection() != null) return;
    if (_ref.read(_noticeProvider) is SelectedGone) return;
    final names = _names(group);
    if (names.isEmpty) return;
    final running = _running;
    final intent = _ref.read(_intentProvider);
    if (_held && !intent.waiting) return;
    final pinging = _pinging || _again;
    // Connect pressed while finding takes this round's first answer, not the round before's best.
    int? ping(String name) =>
        !pinging || _heard.contains(name) ? _ping(name) : null;
    final best = pickNow(
      names: names,
      ping: ping,
      pinging: pinging,
      urgent: intent.waiting,
      handshake: _handshake,
    );
    if (best == null) {
      if (pinging) return;
      if (intent.waiting) {
        _set(const _Intent(error: ShikooError.noServer));
      } else if (running && intent.error != ShikooError.noServer) {
        // Never row 1, the core's own choice: the panel's info row.
        _find();
      }
      return;
    }
    final removed = _removed;
    _removed = null;
    unawaited(_choose(best, byApp: true));
    if (removed != null) {
      _checkNext |= running;
      _notice(
        SelectedReplaced(
          removed: removed,
          replacement: best,
          moved: running,
          fastest: !pinging && names.every((name) => ping(name) != null),
        ),
      );
    }
  }

  /// [list] false is connect's probe: its first answer is taken and nothing else shows.
  Future<void> pingAll({bool list = true}) async {
    final group = _group;
    final names = _names(group);
    if (_pinging) {
      _again |= list && !_roundList;
      return;
    }
    if (group == null || names.isEmpty || _staleGroups) return;
    final no = ++_roundNo;
    final service = _current;
    _pinging = true;
    _roundList = list;
    _heard.clear();
    final round = _ref.read(_roundProvider.notifier);
    if (list) {
      round.set((pending: names.toSet(), total: names.length, ended: false));
    }
    final url = _testUrl(group);
    final answered = <String>{};
    void onResult(String name, int ms) {
      if (no != _roundNo) return;
      if (ms > 0) answered.add(name);
      if (!list) {
        if (ms <= 0) return;
        final first =
            _validSelection() == null && _ref.read(_intentProvider).waiting;
        if (!first) return;
        _heard.add(name);
        _setPing(service, name, ms);
        _reconcile();
        return;
      }
      final kept = _names(_group).contains(name);
      _heard.add(name);
      if (kept) _setPing(service, name, ms);
      final now = _ref.read(_roundProvider);
      round.set((
        pending: {...now.pending}..remove(name),
        total: now.total,
        ended: false,
      ));
      if (!kept || ms <= 0) return;
      if (_ref.read(_intentProvider).error == ShikooError.noServer) {
        _set(const _Intent());
      }
      _reconcile();
    }

    var bridged = false;
    try {
      await _followNetwork();
      Future<int?> probe(String name) => _probeFor(no, url, name);
      await pingServers(names, probe, onResult);
      if (no == _roundNo) {
        bridged = await _tryBridge(
          no,
          url,
          names.where((name) => !answered.contains(name)),
          probe,
          onResult,
        );
      }
    } finally {
      if (_ref.mounted && no == _roundNo) {
        _ref
            .read(_warpFailedProvider.notifier)
            .set(bridged && answered.isEmpty);
        _endRound(list);
      }
    }
  }

  Future<void> _followNetwork() async {
    if (!_ref.read(shikooWarpProvider)) return;
    final network = await _ref.read(warpNetworkReaderProvider)();
    if (network == _ref.read(warpNetworkProvider)) return;
    final before = _ref.read(shikooWarpRouteProvider);
    _ref.read(warpNetworkProvider.notifier).set(network);
    _ref.read(warpAppProvider.notifier).set(false);
    if (!sameRoute(before, _ref.read(shikooWarpRouteProvider))) {
      await _setup.applyProfile(silence: true);
    }
  }

  /// Silent servers are pinged through the bridge until [warpConnectTimeout]; those that answer stay on it on this
  /// network. One on it that is silent there, or answers direct from its definition, goes back. True when it tried any.
  Future<bool> _tryBridge(
    int no,
    String url,
    Iterable<String> silent,
    Future<int?> Function(String name) probe,
    void Function(String name, int ms) onResult,
  ) async {
    final on = _ref.read(shikooWarpProvider);
    final route = _ref.read(shikooWarpRouteProvider);
    final memory = _ref.read(shikooWarpMemoryProvider.notifier);
    final network = _ref.read(warpNetworkProvider);
    final remembered =
        _ref.read(shikooWarpMemoryProvider)[network] ?? const <String>{};
    final specs = _ref.read(shikooCoreSpecsProvider);
    // A core that owns the tunnel dials its server itself, around the bridge.
    bool owned(String name) => ownsTunnel(_coreFor(name), specs);
    final lost = on
        ? {
            ...remembered.intersection({...silent}),
            ...remembered.where(owned),
          }
        : const <String>{};
    final candidates = bridgeCandidates(
      on: on,
      silent: silent.whereNot(owned),
      via: route.via,
    );
    final direct = <String, int>{};
    final service = _current;
    if (on && remembered.isNotEmpty && service != null) {
      final servers = (await _mainGroupOf(service))?.servers ?? const {};
      await pingServers(
        [...remembered],
        (name) async => switch (servers[name]) {
          final proxy? when no == _roundNo => _probeOther(url, proxy),
          _ => null,
        },
        (name, ms) {
          if (ms > 0) direct[name] = ms;
        },
      );
      if (!_ref.mounted) return false;
    }
    final back = {...lost, ...direct.keys};
    if (back.isNotEmpty) await memory.set(network, remembered.difference(back));
    direct.forEach(onResult);
    if (candidates.isEmpty) {
      if (back.isNotEmpty) await _setup.applyProfile(silence: true);
      return false;
    }
    final trial = _ref.read(warpTrialProvider.notifier);
    _ref.read(_warpTryingProvider.notifier).set(true);
    trial.set(candidates);
    try {
      await _setup.applyProfile(silence: true);
      final left = {...candidates};
      final until = DateTime.now().add(warpConnectTimeout);
      while (_ref.mounted &&
          _ref.read(shikooWarpProvider) &&
          left.isNotEmpty &&
          no == _roundNo &&
          DateTime.now().isBefore(until)) {
        await pingServers([...left], probe, (name, ms) {
          if (ms <= 0) return;
          left.remove(name);
          onResult(name, ms);
        });
        // A bridge still starting refuses at once: passes a breath apart, not a busy loop.
        if (left.isNotEmpty) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      if (!_ref.mounted || !_ref.read(shikooWarpProvider)) return true;
      final current = _ref.read(shikooWarpMemoryProvider)[network] ?? const {};
      await memory.set(network, {...current, ...candidates.difference(left)});
      trial.set(const {});
      if (left.isNotEmpty) await _setup.applyProfile(silence: true);
    } finally {
      if (_ref.mounted) {
        trial.set(const {});
        _ref.read(_warpTryingProvider.notifier).set(false);
      }
    }
    return true;
  }

  Future<void> setBridge(bool on) async {
    final before = _ref.read(shikooWarpRouteProvider);
    await _ref.read(shikooWarpProvider.notifier).set(on);
    if (!on) _ref.read(warpAppProvider.notifier).set(false);
    _ref.read(_warpFailedProvider.notifier).set(false);
    if (!sameRoute(before, _ref.read(shikooWarpRouteProvider))) {
      await _setup.applyProfile(silence: true);
    }
    if (on && _ref.read(_intentProvider).error == ShikooError.noServer) {
      await connect();
    }
  }

  int _doorCalls = 0;
  bool _leaveWhenDone = false;

  /// Runs the app's own [request] with the bridge's `PROXY …`, up for the app until [leaveBridge]; null while off.
  Future<T?> throughBridge<T>(Future<T> Function(String proxy) request) async {
    if (!_ref.read(shikooWarpProvider)) return null;
    _doorCalls++;
    _ref.read(_warpDoorProvider.notifier).set(true);
    try {
      final starting = !_ref.read(warpAppProvider);
      if (starting) {
        _ref.read(warpAppProvider.notifier).set(true);
        await _setup.applyProfile(silence: true);
      }
      // A bridge that died is started again by Go's supervisor; its endpoint comes back with it.
      final until = DateTime.now().add(warpConnectTimeout);
      while (_ref.mounted &&
          _ref.read(shikooWarpProvider) &&
          DateTime.now().isBefore(until)) {
        switch (await warpProxy(_ref.read)) {
          case (proxy: final proxy?, error: _):
            return await request(proxy);
          case (proxy: null, error: final error?):
            if (starting) {
              shikooDiag.add('T', 'warp bridge cannot start: $error');
            }
            return null;
          default:
            await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      return null;
    } finally {
      if (--_doorCalls == 0 && _ref.mounted) {
        _ref.read(_warpDoorProvider.notifier).set(false);
        if (_leaveWhenDone) await leaveBridge();
      }
    }
  }

  Future<void> leaveBridge() async {
    _leaveWhenDone = _doorCalls > 0;
    if (_leaveWhenDone || !_ref.read(warpAppProvider)) return;
    final before = _ref.read(shikooWarpRouteProvider);
    _ref.read(warpAppProvider.notifier).set(false);
    if (!sameRoute(before, _ref.read(shikooWarpRouteProvider))) {
      await _setup.applyProfile(silence: true);
    }
  }

  void _endRound(bool list) {
    _pinging = false;
    if (list) {
      _sort();
      _ref.read(_roundProvider.notifier).set((
        pending: const {},
        total: 0,
        ended: true,
      ));
    } else if (_validSelection() == null &&
        _ref.read(_wantedProvider) == null &&
        _ref.read(_intentProvider).waiting) {
      final best = fastest(
        _names(_group),
        (name) => _heard.contains(name) ? _ping(name) : null,
        handshake: _handshake,
      );
      best == null
          ? _set(const _Intent(error: ShikooError.noServer))
          : unawaited(_choose(best, byApp: true));
    }
    if (_again) {
      _again = false;
      unawaited(pingAll());
    } else if (list) {
      _replaceSilentPick();
      _reconcile();
      if (_checkNext) unawaited(_checkSelected());
      _checkNext = false;
    }
  }

  void _setPing(int? service, String name, int ms) {
    if (service == null) return;
    final all = _ref.read(_pingsProvider);
    _ref.read(_pingsProvider.notifier).set({
      ...all,
      service: {...?all[service], name: ms}..removeWhere((_, ms) => ms == 0),
    });
  }

  Future<void> _checkSelected() async {
    if (_staleGroups) return;
    final group = _group;
    final chosen = _validSelection();
    if (group == null || chosen == null || _pinging) return;
    final url = _testUrl(group);
    final no = _roundNo;
    final service = _current;
    await pingServers([chosen], (name) => _probeFor(no, url, name), (name, ms) {
      if (no == _roundNo) _setPing(service, name, ms);
    });
  }

  void _routeStreaming(bool on) {
    if (on == _streamingRouted) return;
    _streamingRouted = on;
    _streamingRoute = _streamingRoute.then((_) async {
      if (on != _streamingRouted || !_ref.mounted) return;
      try {
        if (await keepStreaming(on) && _ref.mounted && _running) {
          await _setup.applyProfile(silence: true);
        }
      } catch (e) {
        commonPrint.log('streaming rules: $e', logLevel: LogLevel.warning);
      }
    });
  }

  Future<void> _checkTraffic(String? server) async {
    if (!_ref.mounted) return;
    final no = ++_trafficNo;
    bool current() => no == _trafficNo && _ref.mounted;
    _ref.read(_noTrafficProvider.notifier).set(false);
    if (server == null || streamingOnly(server)) return;
    if (await _nativeRunTime() == null || !current()) return;
    final passes = _ref.read(trafficPassesProvider);
    Future<bool> once() => passes().catchError((Object _) => false);
    final ok = await once() || (current() && await once());
    if (current()) _ref.read(_noTrafficProvider.notifier).set(!ok);
  }

  void _sort() {
    final group = _group;
    if (group == null) return;
    _setOrder(_current, sortByPing(_names(group), _ping));
  }

  void _setOrder(int? service, List<String> order) {
    if (service == null) return;
    _ref.read(_orderProvider.notifier).set({
      ..._ref.read(_orderProvider),
      service: order,
    });
  }

  static bool _setAside(String name) => multiplied(name) || streamingOnly(name);

  void _setAsideMultiplied() {
    final chosen = _validSelection();
    if (chosen == null || chosen != _appPick || !_setAside(chosen)) return;
    _setChoice(_current!, _group!.name, null, null);
  }

  void _replaceSilentPick() {
    if (_staleGroups || _upOrStarting) return;
    final chosen = _validSelection();
    if (chosen == null || chosen != _appPick) return;
    final ms = _ping(chosen);
    final best = fastest(_names(_group), _ping, handshake: _handshake);
    if (ms == null || best == null) return;
    final silent = ms < 0;
    if (!silent && (!_setAside(chosen) || multiplied(best))) return;
    unawaited(_choose(best, byApp: true));
    if (silent) _notice(SilentReplaced(silent: chosen, replacement: best));
  }

  Future<int?> _probeFor(int no, String url, String name) async =>
      no == _roundNo ? _probe(url, name) : null;

  /// WireGuard pings can fail while it carries traffic, so real traffic decides for the selection.
  Future<int?> _probe(String url, String name) async {
    int? ms;
    try {
      ms = (await _ref.read(coreHandlerProvider).getDelay(url, name))?.value;
    } catch (_) {}
    if ((ms ?? 0) > 0) return ms;
    bool carriesTraffic() => name == _validSelection() && _running;
    if (!carriesTraffic() || await _nativeRunTime() == null) return null;
    final passes = await _ref.read(trafficPassesProvider)();
    // The lookup went out through whatever carried traffic when it ended, maybe not [name].
    // Its time is not a ping: the last real one stays, or none (0).
    return passes && carriesTraffic() ? math.max(_ping(name) ?? 0, 0) : null;
  }

  void _updated(int id) {
    shikooDiag.refreshed(id, null);
    if (_ref.read(_refreshesProvider)[id] == ShikooRefresh.failed) {
      _mark(id, ShikooRefresh.idle);
    }
    if (id == _current && _ref.read(_noticeProvider) is RefreshFailed) {
      _notice(null);
    }
  }

  Future<void> _loadPasted() async =>
      _ref.read(_pastedProvider.notifier).set(await pastedProfiles());

  void _revoked(int id, {required bool revoked}) {
    final now = _ref.read(_revokedProvider);
    _ref
        .read(_revokedProvider.notifier)
        .set(revoked ? {...now, id} : ({...now}..remove(id)));
  }

  void _loginRefused(int? id, {required bool refused}) {
    final now = _ref.read(_loginRefusedProvider);
    if (id == null || now.contains(id) == refused) return;
    _ref
        .read(_loginRefusedProvider.notifier)
        .set(refused ? {...now, id} : ({...now}..remove(id)));
  }

  /// Phone-only, as only a phone pastes: the account's own services leave with its next sync.
  void _failed(int id, Object error) {
    shikooDiag.refreshed(id, error);
    if (addFailure(error) == ShikooPasteError.revoked &&
        !_ref.read(shikooTvProvider) &&
        _ref.read(_pastedProvider).contains(id)) {
      _revoked(id, revoked: true);
    }
  }

  /// phone-remove-confirm: the next card takes its place, and the app never reconnects by itself.
  Future<void> removeService(int id) async {
    if (id == _ref.read(currentProfileIdProvider)) {
      if (_running || _ref.read(_intentProvider).connecting) await disconnect();
      final next = _ref
          .read(shikooStateProvider)
          .listed
          .firstWhereOrNull((service) => service.id != id);
      if (next != null) {
        await _use(next.id);
      }
    }
    await _ref.read(profilesActionProvider.notifier).deleteProfile(id);
    await forgetPasted(id);
    await _loadPasted();
    _revoked(id, revoked: false);
    _savePicks({..._appPickByService}..remove('$id'));
  }

  Future<void> renameFromPanel(int id) async {
    final profile = _ref.read(profilesProvider).getProfile(id);
    if (profile == null || profile.url.isEmpty) return;
    try {
      await _download(profile.url, refresh: true);
    } catch (_) {
      // ponytail: offline, the account's name stays until the next sign-out or paste.
    }
  }

  void onForeground() {
    unawaited(_loadPasted());
    unawaited(refreshDue());
  }

  /// Every service's usage and date, the one in use first; one at a time, as FlClash's own
  /// update does.
  /// [renewed] skip the wait, once a [renewedEvery]: an update starts a sync that names them again.
  Future<void> refreshDue({Set<int> renewed = const {}}) {
    final now = DateTime.now();
    for (final id in renewed) {
      if (isDue(_renewedAt[id], now, renewedEvery)) {
        _renewedAt[id] = now;
        _renewed.add(id);
      }
    }
    return _refreshingDue ??= _refreshDue().whenComplete(() {
      _refreshingDue = null;
      if (_renewed.isNotEmpty) unawaited(refreshDue());
    });
  }

  Future<void> _refreshDue() async {
    final now = DateTime.now();
    final forced = {..._renewed};
    _renewed.clear();
    bool due(Profile? profile) =>
        forced.contains(profile?.id) ||
        isDue(profile?.lastUpdateDate, now, refreshEvery);
    final current = _ref.read(currentProfileProvider);
    if (due(current)) await refreshService(manual: false);
    for (final other in [..._ref.read(profilesProvider)]) {
      if (other.id != current?.id && due(other)) await refreshOther(other.id);
    }
  }

  void selectService(int id) {
    clearNews();
    _endSwitch();
    _pingOnArrival = false;
    unawaited(_use(id));
  }

  /// Off, the card opened is the one connect uses; on, the tunnel stays. Null folds every card.
  void openService(int? id) {
    _ref.read(_openProvider.notifier).set(id);
    _ref.read(_landedProvider.notifier).set(null);
    _closeOpened();
    final service = _ref
        .read(shikooStateProvider)
        .listed
        .firstWhereOrNull((s) => s.id == id);
    if (service == null || service.ended != null) return;
    if (service.id == _current) return unawaited(pingAll());
    if (!_running && !_ref.read(_intentProvider).connecting) {
      selectService(service.id);
      _pingOnArrival = true;
      return;
    }
    unawaited(_pingOther(service.id));
  }

  void _closeOpened() {
    _openNo++;
    _ref.read(_openedProvider.notifier).set(null);
    _ref.read(_openRoundProvider.notifier).set(_noRound);
  }

  Future<void> _pingOther(int id) async {
    final no = _openNo;
    final main = await _mainGroupOf(id);
    if (no != _openNo || main == null || main.servers.isEmpty) return;
    final _Opened opened = (
      id: id,
      group: main.group,
      url: _ref.read(realTestUrlProvider(main.url)),
      proxies: main.servers,
    );
    final names = [...opened.proxies.keys];
    final round = _ref.read(_openRoundProvider.notifier);
    _ref.read(_openedProvider.notifier).set(opened);
    round.set((pending: names.toSet(), total: names.length, ended: false));
    await pingServers(
      names,
      (name) async =>
          no == _openNo ? _probeOther(opened.url, opened.proxies[name]!) : null,
      (name, ms) {
        if (no != _openNo) return;
        _setPing(id, name, ms);
        final now = _ref.read(_openRoundProvider);
        round.set((
          pending: {...now.pending}..remove(name),
          total: now.total,
          ended: false,
        ));
      },
    );
    if (no != _openNo) return;
    _setOrder(id, sortByPing(names, (name) => _pingOf(id, name)));
    round.set((pending: const {}, total: 0, ended: true));
  }

  /// A server whose core owns the tunnel goes marked, as in the applied config, so Go asks it that core's way.
  Future<int?> _probeOther(String url, Map<String, dynamic> proxy) async {
    final specs = _ref.read(shikooCoreSpecsProvider);
    final core = coreFor(
      proxy,
      _ref.read(shikooCoresProvider),
      specs: specs,
      tunnel: _tunnel,
    );
    final asked = ownsTunnel(core, specs)
        ? {...proxy, shikooOwnerKey: core.name}
        : proxy;
    try {
      return (await _ref.read(coreHandlerProvider).getDelayOf(url, asked))
          ?.value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _use(int id) async {
    final main = await _mainGroupOf(id);
    if (main != null && main.servers.isNotEmpty) {
      final names = _sorted(main.servers.keys);
      if (names != _sorted(_names(_group))) {
        _awaiting = names;
        _awaitingUntil = DateTime.now().add(const Duration(seconds: 15));
      }
    }
    _ref.read(currentProfileIdProvider.notifier).value = id;
  }

  bool get _staleGroups {
    final awaiting = _awaiting;
    if (awaiting == null) return false;
    // ponytail: a name FlClash and the config read differently would wait the 15 s out.
    if (awaiting == _sorted(_names(_group)) ||
        DateTime.now().isAfter(_awaitingUntil)) {
      _awaiting = null;
    }
    return _awaiting != null;
  }

  Future<MainGroup?> _mainGroupOf(int id) async {
    try {
      return mainGroupOf(
        await _ref.read(coreHandlerProvider).getConfig(id),
        specs: _ref.read(shikooCoreSpecsProvider),
        tunnel: _tunnel,
      );
    } catch (_) {
      return null;
    }
  }

  /// Profiles are readable only once FlClash's boot has set their folder; a failed read keeps what was there.
  Future<void> _loadSources() async {
    if (!_ref.read(initProvider)) return;
    final loaded = <int, Map<String, Map<String, dynamic>>>{};
    for (final service in _ref.read(shikooStateProvider).listed) {
      final servers =
          (await _mainGroupOf(service.id))?.servers ??
          _ref.read(_sourcesProvider)[service.id];
      if (servers != null) loaded[service.id] = servers;
    }
    _ref.read(_sourcesProvider.notifier).set(loaded);
  }

  Future<void> refreshOther(int id, {ShikooRoute? via}) =>
      _refreshCard(id, manual: false, via: via);

  void _mark(int id, ShikooRefresh state) {
    final now = {..._ref.read(_refreshesProvider)}..remove(id);
    _ref.read(_refreshesProvider.notifier).set({
      ...now,
      if (state != ShikooRefresh.idle) id: state,
    });
  }

  void _leg(int id, ShikooLeg? leg) {
    final legs = {..._ref.read(_legsProvider)}..remove(id);
    _ref.read(_legsProvider.notifier).set({...legs, id: ?leg});
  }

  void _bridgeLeg(int id, bool on) {
    final legs = {..._ref.read(_bridgeLegsProvider)};
    _ref
        .read(_bridgeLegsProvider.notifier)
        .set(on ? (legs..add(id)) : (legs..remove(id)));
  }

  /// One update at a time per service; a press during an automatic one makes its failure visible.
  Future<void> refreshService({bool manual = true, ShikooRoute? via}) {
    final id = _current;
    return id == null
        ? Future.value()
        : _refreshCard(id, manual: manual, via: via);
  }

  Future<void> _refreshCard(int id, {required bool manual, ShikooRoute? via}) {
    if (manual) _manual.add(id);
    return _refreshing[id] ??= _refresh(id, via).whenComplete(() {
      _refreshing.remove(id);
      _manual.remove(id);
    });
  }

  Future<void> _refresh(int id, ShikooRoute? via) async {
    final profile = _ref.read(profilesProvider).getProfile(id);
    if (profile == null || profile.url.isEmpty) return;
    // Another card, or none after a sign-out, may be in use by the time the answer comes.
    final started = id == _current;
    _mark(id, ShikooRefresh.running);
    if (started) clearNews();
    final before = _names(_group);
    final had = _validSelection();
    ShikooLeg? last;
    var bridged = false;
    try {
      final fresh = await _download(
        profile.url,
        label: profile.label,
        refresh: true,
        via: via,
        onLeg: (leg) {
          last = leg;
          if (leg != null) _leg(id, leg);
        },
        onBridge: (on) {
          bridged = on;
          _bridgeLeg(profile.id, on);
        },
      );
      if (fresh == null) {
        _mark(id, ShikooRefresh.idle);
        return;
      }
      if (fresh.id == _current && !await _setup.applyProfile(silence: true)) {
        throw StateError('apply');
      }
    } catch (error) {
      final clock = id == _current && await clockFailed(error, profile.url);
      _mark(id, ShikooRefresh.failed);
      _failed(id, error);
      if (id == _current && (_manual.contains(id) || clock)) {
        _notice(
          RefreshFailed(
            clock: clock,
            way: failedWay(last, error),
            server: _validSelection(),
            bridge: bridged,
          ),
        );
      }
      return;
    } finally {
      _leg(id, null);
      _bridgeLeg(id, false);
    }
    _mark(id, ShikooRefresh.idle);
    if (!started || id != _current) return;
    _notice(null);
    final after = _names(_group);
    final removed = [
      for (final name in before)
        if (!after.contains(name)) name,
    ];
    final added = after.where((name) => !before.contains(name)).toSet();
    _ref.read(_freshProvider.notifier).set(added);
    if (_ref.read(_switchProvider) case final shift?
        when removed.contains(shift.to) || removed.contains(shift.from)) {
      _endSwitch();
    }
    if (had != null && removed.contains(had)) {
      if (_upOrStarting) {
        _notice(const SelectedGone());
        return disconnect();
      }
      _removed = had;
      unawaited(pingAll());
    } else if (added.isNotEmpty || removed.isNotEmpty) {
      _notice(ServersChanged(added: added.length, removed: removed));
    }
    _reconcile();
  }

  /// [via] null tries the device's own internet, then once the server if that failed while connected.
  Future<Response<Uint8List>> _fetch(
    String url,
    ShikooRoute? via,
    void Function(ShikooLeg? leg)? onLeg, [
    void Function(bool on)? onBridge,
  ]) async {
    final server = FlClashHttpOverrides.findProxyForReader(
      _ref.read,
      Uri.parse(url),
    );
    final connected = server != 'DIRECT';
    var aside = ownerAside(_ref.read, Uri.parse(url));
    if (aside != null) {
      // Go was asked at connect; an engine that stopped since must not keep the app's requests on its road.
      await _checkCarrying();
      aside = ownerAside(_ref.read, Uri.parse(url));
    }
    // The owner's tunnel carries plain requests, and subscription hosts on Android's mixed port (subscriptionDirectRule).
    final byServer = aside == null ? server : null;
    final direct = aside == null ? null : directInboundProxy() ?? aside;
    if (via == ShikooRoute.server) {
      if (!connected) throw const ShikooNotConnected();
      onLeg?.call(ShikooLeg.server);
      return _get(url, byServer);
    }
    onLeg?.call(connected ? ShikooLeg.direct : ShikooLeg.directOff);
    try {
      try {
        final response = await _getAgain(url, direct);
        await leaveBridge();
        return response;
      } catch (error) {
        final answered = error is DioException && error.response != null;
        if (via != null || !connected || answered) rethrow;
        onLeg?.call(ShikooLeg.fallback);
        return await _get(url, byServer);
      }
    } catch (error) {
      final wanted = warpLegWanted(
        on: _ref.read(shikooWarpProvider),
        chosen: via != null,
        error: error,
      );
      final bridged = wanted
          ? await throughBridge((proxy) {
              onBridge?.call(true);
              return _get(url, proxy, timeout: warpConnectTimeout);
            })
          : null;
      if (bridged == null) rethrow;
      return bridged;
    }
  }

  /// FlClash's `Profile.update` (same request and User-Agent) keeping the headers it drops.
  /// The url holds the customer's token: never log it, nor the error, which can quote it.
  Future<Profile?> _download(
    String url, {
    String? label,
    bool needsServers = false,
    bool refresh = false,
    ShikooRoute? via,
    void Function(ShikooLeg? leg)? onLeg,
    void Function(bool on)? onBridge,
  }) async {
    final response = await _fetch(url, via, onLeg, onBridge);
    // What fails from here on came with an answer: no way is to blame.
    onLeg?.call(null);
    final header = response.headers.value;
    learnClock(header('date'));
    final body = response.data ?? Uint8List(0);
    final profiles = _ref.read(profilesProvider);
    final title = headerText(header('profile-title'));
    final user = accountOf(
      file: _fileName(header('content-disposition')),
      title: title,
      body: utf8.decode(body, allowMalformed: true),
    );
    final existing = serviceOf(profiles, url, user);
    if (refresh && existing == null) return null;
    final name = label ?? serviceName(title, user);
    final draft = (existing ?? Profile.normal(url: url)).copyWith(
      url: url,
      label: unusedName(name, {
        for (final other in profiles)
          if (other != existing) other.label,
      }),
      // FlClash's own daily update would race this one and drop the headers kept below.
      autoUpdate: false,
      subscriptionInfo: _subscriptionInfo(header('subscription-userinfo')),
    );
    final ended = _serviceFrom(draft).ended;
    // A panel may send a used-up or expired service with no servers until renewal.
    if (needsServers && ended == null) {
      await _needServers(body);
    }
    Profile profile;
    try {
      profile = await draft.saveFile(body, validate: _validate);
    } on MessageException {
      if (ended == null) rethrow;
      if (!refresh) throw ShikooPanelEnded(ended);
      // Its last servers stay on disk for the renewal; the panel's usage and date are what changed.
      profile = draft.copyWith(lastUpdateDate: DateTime.now());
    }
    // ponytail: its just-saved config file stays behind, as with FlClash's own update.
    if (refresh &&
        !_ref.read(profilesProvider).any((p) => p.id == profile.id)) {
      return null;
    }
    _revoked(profile.id, revoked: false);
    _updated(profile.id);
    if (existing != null &&
        profileFinished(existing) &&
        !profileFinished(profile)) {
      await _ref.read(savedOrderProvider.notifier).forget(existing.id);
    }
    _ref.read(profilesActionProvider.notifier).putProfile(profile);
    await _ref.read(_extrasProvider.notifier).put(profile.id, (
      announce: headerText(header('announce')),
      supportUrl: headerText(header('support-url')),
      account: user,
    ));
    return profile;
  }

  Future<String> _validate(String path) =>
      _ref.read(coreHandlerProvider).validateConfig(path);

  Future<void> _needServers(Uint8List body) async {
    final probe = await Profile.normal().saveFile(body, validate: _validate);
    Map<String, dynamic>? config;
    try {
      config = await _ref.read(coreHandlerProvider).getConfig(probe.id);
    } catch (_) {
      // ponytail: a core that cannot answer is unsure, and unsure lets the service in.
    } finally {
      await (await probe.file).safeDelete();
    }
    if (config != null && !configHasServers(config)) {
      throw const FormatException('no servers');
    }
  }

  Future<ShikooPasteError?> addService(
    String url, [
    String? label,
    bool select = true,
  ]) async {
    try {
      final profile = (await _download(url, label: label, needsServers: true))!;
      if (_ref.read(currentProfileIdProvider) == profile.id) {
        // The core re-reads a profile only when the selection changes.
        await _setup.applyProfile(silence: true);
      } else if (select) {
        await _use(profile.id);
      }
      return null;
    } catch (error) {
      return await clockFailed(error, url)
          ? ShikooPasteError.clock
          : addFailure(error);
    }
  }

  /// What the user pasted holds a token: nothing here shows or logs it.
  Future<ShikooPasted> pasteService(
    String? text, {
    bool debug = shikooDebug,
  }) async {
    ShikooPasted failed(ShikooPasteError error) =>
        (error: error, id: null, added: false);
    if (text == null || text.trim().isEmpty) {
      return failed(ShikooPasteError.empty);
    }
    final link = shikooLink(text, debug: debug);
    if (link == null) return failed(ShikooPasteError.notShikoo);
    final before = {
      for (final profile in _ref.read(profilesProvider)) profile.id,
    };
    final failure = await addService(link, null, false);
    if (failure != null) return failed(failure);
    final ids = [
      for (final profile in _ref.read(profilesProvider))
        if (normalLink(profile.url) == normalLink(link)) profile.id,
    ];
    await markPasted(ids);
    await _loadPasted();
    final id = ids.firstOrNull;
    if (id != null) openService(id);
    return (error: null, id: id, added: id != null && !before.contains(id));
  }
}
