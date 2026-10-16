import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:fl_clash/shikoo/engine/order.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The only door from Shikoo screens into FlClash's engine (docs/extensibility.md section 1).

enum ShikooConnection { off, connecting, on, error }

enum ShikooError {
  connectTimeout,
  serverChange,
  noServer,
  vpnRefused,
  vpnMissing,
}

/// [revoked]: a pasted link the panel no longer knows (404 or 410).
enum ShikooServiceStatus { active, expired, exhausted, revoked }

enum ShikooPick { server, finding, auto, none }

enum ShikooRefresh { idle, running, failed }

enum ShikooSwitchStage { moving, done, failed }

/// Connected, a tapped [to] gets the traffic only once it answers; [from] keeps it until then.
typedef ShikooSwitch = ({String to, String from, ShikooSwitchStage stage});

typedef ShikooLanded = ({int id, bool arrived});

/// The open card's list while another service has the tunnel: measured there, never connected to.
typedef ShikooOpened = ({
  int id,
  List<ShikooServer> servers,
  ({int done, int total})? pinging,
  bool sorted,
});

const connectTimeout = Duration(seconds: 30);

const switchedFor = Duration(seconds: 4);

@immutable
class ShikooServer {
  const ShikooServer({
    required this.name,
    required this.type,
    this.ping,
    this.testing = false,
    this.fresh = false,
  });

  final String name;

  /// The engine's protocol name, kept as data so a new protocol needs no screen change.
  final String type;

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
    this.pasted = false,
    this.revoked = false,
    this.number = 1,
    this.account,
  });

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

  /// Of a service other than the current one; the current one's is [ShikooState.refresh].
  final ShikooRefresh refresh;

  final bool pasted;
  final bool revoked;

  /// Among the services without a name, 1 for the first.
  final int number;

  final String? account;

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
  const SilentReplaced({
    required this.silent,
    required this.replacement,
    required this.moved,
  });

  final String silent;
  final String replacement;
  final bool moved;
}

class RefreshFailed extends ShikooNotice {
  const RefreshFailed({this.clock = false});

  final bool clock;
}

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
  });

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

  ShikooServer? get selectedServer =>
      servers.firstWhereOrNull((server) => server.name == selected);

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
  const _Intent({this.connecting = false, this.waiting = false, this.error});

  final bool connecting;
  final bool waiting;
  final ShikooError? error;
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
final _refreshProvider = _cell(ShikooRefresh.idle);
final _othersRefreshProvider = _cell<Map<int, ShikooRefresh>>(const {});
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
MainGroup? mainGroupOf(Map<String, dynamic> config) {
  final proxies = {
    for (final proxy in config['proxies'] as List? ?? const [])
      if (proxy is Map) '${proxy['name']}': Map<String, dynamic>.from(proxy),
  };
  for (final group in config['proxy-groups'] as List? ?? const []) {
    if (group is! Map || group['hidden'] == true) continue;
    return (
      group: '${group['name']}',
      url: '${group['url'] ?? ''}',
      servers: {
        for (final name in group['proxies'] as List? ?? const [])
          if (proxies['$name'] case final proxy?
              when isServer('${proxy['type']}', '$name'))
            '$name': proxy,
      },
    );
  }
  return null;
}

List<Proxy> _serversOf(Group? group) => [
  for (final proxy in group?.all ?? const <Proxy>[])
    if (isServer(proxy.type, proxy.name)) proxy,
];

Group? _mainGroup(Ref ref) =>
    ref.watch(currentGroupsStateProvider).value.firstOrNull;

ShikooConnection deriveConnection({
  required bool connecting,
  required bool running,
  required ShikooError? error,
}) {
  if (connecting) return ShikooConnection.connecting;
  if (running) return ShikooConnection.on;
  return switch (error) {
    ShikooError.connectTimeout ||
    ShikooError.noServer ||
    ShikooError.vpnRefused ||
    ShikooError.vpnMissing => ShikooConnection.error,
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

final shikooStateProvider = Provider<ShikooState>((ref) {
  final runTime = ref.watch(runTimeProvider);
  final nativeStart = ref.watch(_nativeStartProvider);
  final intent = ref.watch(_intentProvider);
  final profile = ref.watch(currentProfileProvider);
  final extras = ref.watch(_extrasProvider);
  final refreshing = ref.watch(_othersRefreshProvider);
  final pasted = ref.watch(_pastedProvider);
  final revoked = ref.watch(_revokedProvider);
  final unnamed = [
    for (final profile in ref.watch(profilesProvider))
      if (_nameOf(profile).isEmpty) profile.id,
  ];
  ShikooService of(Profile profile) => _serviceFrom(
    profile,
    extras: extras[profile.id],
    refresh: refreshing[profile.id] ?? ShikooRefresh.idle,
    pasted: pasted.contains(profile.id),
    revoked: revoked.contains(profile.id),
    number: unnamed.indexOf(profile.id) + 1,
  );

  final group = _mainGroup(ref);
  final round = ref.watch(_roundProvider);
  final pings = ref.watch(_pingsProvider);
  final orders = ref.watch(_orderProvider);
  final fresh = ref.watch(_freshProvider);
  final byName = {for (final proxy in _serversOf(group)) proxy.name: proxy};
  final chosen = group == null
      ? null
      : ref.watch(selectedMapProvider)[group.name];
  final selected = byName.containsKey(chosen) ? chosen : null;
  final switching = ref.watch(_switchProvider);
  final switchService = ref.watch(_switchServiceProvider);
  List<ShikooServer> listOf(
    int? id,
    Map<String, String> types,
    _Round round, {
    Set<String> fresh = const {},
  }) {
    bool testing(String name) =>
        round.pending.contains(name) ||
        (switching?.stage == ShikooSwitchStage.moving &&
            switching?.to == name &&
            switchService == id);
    return [
      for (final name in keepOrder(orders[id] ?? const [], [...types.keys]))
        ShikooServer(
          name: name,
          type: types[name]!,
          ping: testing(name) ? null : pings[id]?[name],
          testing: testing(name),
          fresh: fresh.contains(name),
        ),
    ];
  }

  final servers = listOf(
    profile?.id,
    {for (final proxy in byName.values) proxy.name: proxy.type},
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
    final servers = listOf(opened.id, {
      for (final MapEntry(:key, :value) in opened.proxies.entries)
        key: '${value['type']}',
    }, openRound);
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
    refresh: ref.watch(_refreshProvider),
    notice: ref.watch(_noticeProvider),
    waiting: intent.waiting,
    switching: switching,
    sorted: (orders[profile?.id] ?? const []).isNotEmpty,
    open: ids.contains(open) ? open : null,
    opened: opened == null ? null : openedView(opened),
    order: ref.watch(serviceOrderProvider),
    landed: ref.watch(_landedProvider),
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

final nativeRunTimeProvider = Provider<Future<DateTime?> Function()>(
  (_) =>
      () async => service?.getRunTime(),
);

// ponytail: trusts the panel's rules to send FlClash's IP lookups to the selected server.
final trafficPassesProvider = Provider<Future<bool> Function()>(
  (_) =>
      () async => (await request.checkIp()).data != null,
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
  Duration every = const Duration(seconds: 1),
}) async {
  final waited = Stopwatch();
  while (stillWanted()) {
    if (await runTime() case final start?) return start;
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
  bool pasted = false,
  bool revoked = false,
  int number = 1,
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
    usageKnown: info != null,
    refresh: refresh,
    pasted: pasted,
    revoked: revoked,
    number: number < 1 ? 1 : number,
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

/// Never row 1, the core's fallback: with connect pressed the first answer, else the fastest.
String? pickNow({
  required List<String> names,
  required int? Function(String name) ping,
  required bool pinging,
  required bool urgent,
}) => pinging && !urgent ? null : fastest(names, ping);

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
    _ref.onDispose(() => _switched?.cancel());
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
            _carryRefresh(previous.$1!, service);
            _forgetRound();
          });
        }
        if (!_arrived && service != null && names.isNotEmpty) {
          scheduleMicrotask(_arrive);
        }
      },
      fireImmediately: true,
    );
    _ref.listen(runTimeProvider.select((time) => time != null), (_, running) {
      scheduleMicrotask(
        running
            ? _reconcile
            : () {
                _nativeStart(null);
                _endSwitch();
              },
      );
    });
    app?.onVpnConsent = onVpnConsent;
    scheduleMicrotask(() => _ref.read(_extrasProvider.notifier).load());
    scheduleMicrotask(_loadPasted);
    scheduleMicrotask(() => _ref.read(savedOrderProvider.notifier).load());
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
  Timer? _switched;
  String? _awaiting;
  DateTime _awaitingUntil = DateTime(0);

  /// The selection an update just took away, for the notice that names it.
  String? _removed;
  Future<void>? _refreshing;
  Future<void>? _refreshingDue;
  final _renewed = <int>{};
  final _renewedAt = <int, DateTime>{};
  bool _manualRefresh = false;

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

  void _notice(ShikooNotice? notice) =>
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

  List<String> _names(Group? group) => [
    for (final proxy in _serversOf(group)) proxy.name,
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

  Future<void> connect() async {
    if (_ref.read(currentProfileProvider) == null) return;
    _setAsideMultiplied();
    if (_validSelection() != null) return _start();
    _find();
  }

  /// No server chosen: the first to answer now takes it, with the tunnel up or not.
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

  Future<void> _start() async {
    final attempt = ++_attempt;
    _set(const _Intent(connecting: true));
    bool started;
    try {
      started = await _setup.setRunning(
        true,
        initialize: !_ref.read(initProvider),
      );
    } catch (_) {
      started = false;
    }
    final since = started
        ? await waitForTunnel(
            _nativeRunTime,
            timeout: connectTimeout,
            stillWanted: () => attempt == _attempt,
            paused: () => !foreground,
          )
        : null;
    if (attempt != _attempt) return;
    if (since != null) {
      _nativeStart(since);
      _set(const _Intent());
      unawaited(_checkSelected());
      return;
    }
    _set(const _Intent(error: ShikooError.connectTimeout));
    await _setup.setRunning(false);
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
    _attempt++;
    _endSwitch();
    _ref.read(_landedProvider.notifier).set(null);
    _nativeStart(null);
    _set(const _Intent());
    await _setup.setRunning(false);
  }

  Future<void> forgetServices() async {
    await disconnect();
    final profiles = _ref.read(profilesActionProvider.notifier);
    for (final profile in [..._ref.read(profilesProvider)]) {
      await profiles.deleteProfile(profile.id);
    }
    await _ref.read(_extrasProvider.notifier).clear();
    _savePicks(const {});
    _notice(null);
    _forgetRound();
    openService(null);
    _ref.read(_pingsProvider.notifier).set(const {});
    _ref.read(_orderProvider.notifier).set(const {});
    _ref.read(_freshProvider.notifier).set(const {});
    _ref.read(_othersRefreshProvider.notifier).set(const {});
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
    final tap = _endSwitch();
    if (_ref.read(_noticeProvider)
        case SilentReplaced() || SelectedReplaced()) {
      _notice(null);
    }
    final from = _validSelection();
    final connected = _running && !_ref.read(_intentProvider).connecting;
    if (connected && from != null && (other != null || from != name)) {
      return _switchTo(name, from, tap, other);
    }
    if (other != null) return _moveTo(other, name);
    _pickedByApp(null);
    await _choose(name);
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
    final type =
        mapping?['type'] ??
        _serversOf(
          _group,
        ).firstWhereOrNull((proxy) => proxy.name == name)?.type;
    if (type == null) return _switching(null);
    if (ms <= 0 && '$type'.toLowerCase() != 'wireguard') {
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
    _switched = Timer(switchedFor, () => _switching(null));
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

  Future<void> _choose(String name) async {
    final group = _group;
    if (group == null) return;
    final no = ++_chooseNo;
    await _proxies.changeProxy(groupName: group.name, proxyName: name);
    _proxies.updateGroupsDebounce();
    // Only the newest change speaks: the core answers each on its own goroutine, in any order.
    if (no != _chooseNo) return;
    final applied = _ref.read(selectedProxyNameProvider(group.name)) == name;
    final intent = _ref.read(_intentProvider);
    if (applied && intent.waiting) {
      // Up already, as after a switch of service: the answer takes the traffic, no new start.
      return _running ? _set(const _Intent()) : unawaited(_start());
    }
    _set(
      _Intent(
        connecting: intent.connecting,
        waiting: intent.waiting,
        error: applied ? null : ShikooError.serverChange,
      ),
    );
  }

  void _reconcile() {
    final group = _group;
    if (group == null || _staleGroups || _validSelection() != null) return;
    final names = _names(group);
    if (names.isEmpty) return;
    final running = _running;
    final intent = _ref.read(_intentProvider);
    final pinging = _pinging || _again;
    // Connect pressed while finding takes this round's first answer, not the round before's best.
    int? ping(String name) =>
        !pinging || _heard.contains(name) ? _ping(name) : null;
    final best = pickNow(
      names: names,
      ping: ping,
      pinging: pinging,
      urgent: intent.waiting,
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
    _pickedByApp(best);
    // changeProxy writes the selection before it awaits, so a second call sees it.
    unawaited(_choose(best));
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
    try {
      await pingServers(names, (name) => _probeFor(no, url, name), (name, ms) {
        if (no != _roundNo) return;
        if (!list) {
          if (ms <= 0) return;
          final first =
              _validSelection() == null && _ref.read(_intentProvider).waiting;
          if (!first && !_leaveMultiplied(name)) return;
          _heard.add(name);
          _setPing(service, name, ms);
          if (first) _reconcile();
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
      });
    } finally {
      if (no == _roundNo) _endRound(list);
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
        _ref.read(_intentProvider).waiting) {
      _set(const _Intent(error: ShikooError.noServer));
    }
    if (_again) {
      _again = false;
      unawaited(pingAll());
    } else if (list) {
      unawaited(_replaceSilentPick());
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
    if (chosen == _appPick &&
        chosen == _validSelection() &&
        (_ping(chosen) ?? 0) < 0) {
      unawaited(pingAll());
    }
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

  /// The app's own usage-multiplier pick gives way to an ordinary [to]; a user's own stays.
  bool _leaveMultiplied(String? to) {
    final chosen = _validSelection();
    if (to == null || multiplied(to) || chosen == null) return false;
    if (chosen != _appPick || !multiplied(chosen)) return false;
    _pickedByApp(to);
    unawaited(_choose(to));
    return true;
  }

  /// Connect searches as for a new customer instead of starting on the app's own multiplied pick.
  void _setAsideMultiplied() {
    final chosen = _validSelection();
    if (chosen == null || chosen != _appPick || !multiplied(chosen)) return;
    _setChoice(_current!, _group!.name, null, null);
  }

  Future<void> _replaceSilentPick() async {
    if (_staleGroups) return;
    final chosen = _validSelection();
    if (chosen == null || chosen != _appPick) return;
    final ms = _ping(chosen);
    if (ms == null) return;
    if (ms > 0) {
      _leaveMultiplied(fastest(_names(_group), _ping));
      return;
    }
    // Flutter says running from the press on; a probe under the consent dialog proves nothing.
    if (_running && await _nativeRunTime() == null) return;
    if (_validSelection() != chosen) return;
    final best = fastest(_names(_group), _ping);
    if (best == null) return;
    _pickedByApp(best);
    unawaited(_choose(best));
    _notice(SilentReplaced(silent: chosen, replacement: best, moved: _running));
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

  /// The in-use card's update state is kept apart from the others': it moves with its service.
  void _carryRefresh(int from, int? to) {
    final others = {..._ref.read(_othersRefreshProvider)};
    final mine = _ref.read(_refreshProvider);
    if (mine == ShikooRefresh.failed) others[from] = mine;
    _ref
        .read(_refreshProvider.notifier)
        .set(others.remove(to) ?? ShikooRefresh.idle);
    _ref.read(_othersRefreshProvider.notifier).set(others);
    if (_ref.read(_noticeProvider) is RefreshFailed) _notice(null);
  }

  void _updated(int id) {
    shikooDiag.refreshed(id, null);
    if (id == _ref.read(currentProfileIdProvider)) {
      if (_ref.read(_refreshProvider) == ShikooRefresh.failed) {
        _ref.read(_refreshProvider.notifier).set(ShikooRefresh.idle);
      }
      if (_ref.read(_noticeProvider) is RefreshFailed) _notice(null);
    } else if (_ref.read(_othersRefreshProvider)[id] == ShikooRefresh.failed) {
      _ref
          .read(_othersRefreshProvider.notifier)
          .set({..._ref.read(_othersRefreshProvider)}..remove(id));
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

  Future<int?> _probeOther(String url, Map<String, dynamic> proxy) async {
    try {
      return (await _ref.read(coreHandlerProvider).getDelayOf(url, proxy))
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
      return mainGroupOf(await _ref.read(coreHandlerProvider).getConfig(id));
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshOther(int id) async {
    final profile = _ref.read(profilesProvider).getProfile(id);
    void mark(ShikooRefresh state) => _ref
        .read(_othersRefreshProvider.notifier)
        .set({..._ref.read(_othersRefreshProvider), id: state});
    if (profile == null ||
        profile.url.isEmpty ||
        _ref.read(_othersRefreshProvider)[id] == ShikooRefresh.running) {
      return;
    }
    mark(ShikooRefresh.running);
    try {
      await _download(profile.url, label: profile.label, refresh: true);
      mark(ShikooRefresh.idle);
    } catch (error) {
      mark(ShikooRefresh.failed);
      _failed(id, error);
    }
  }

  /// One update at a time; a press during an automatic one makes its failure visible.
  Future<void> refreshService({bool manual = true}) {
    _manualRefresh |= manual;
    return _refreshing ??= _refresh().whenComplete(() {
      _refreshing = null;
      _manualRefresh = false;
    });
  }

  Future<void> _refresh() async {
    final profile = _ref.read(currentProfileProvider);
    if (profile == null || profile.url.isEmpty) return;
    final status = _ref.read(_refreshProvider.notifier);
    status.set(ShikooRefresh.running);
    clearNews();
    final before = _names(_group);
    final had = _validSelection();
    try {
      final fresh = await _download(
        profile.url,
        label: profile.label,
        refresh: true,
      );
      if (fresh == null) {
        status.set(ShikooRefresh.idle);
        return;
      }
      if (!await _setup.applyProfile(silence: true)) {
        throw StateError('apply');
      }
    } catch (error) {
      final clock = await clockFailed(error, profile.url);
      status.set(ShikooRefresh.failed);
      _failed(profile.id, error);
      if (_manualRefresh || clock) _notice(RefreshFailed(clock: clock));
      return;
    }
    status.set(ShikooRefresh.idle);
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
      // One fresh round names the replacement; connected, its first answer takes the traffic.
      _removed = had;
      _running ? _find(list: true) : unawaited(pingAll());
    } else if (added.isNotEmpty || removed.isNotEmpty) {
      _notice(ServersChanged(added: added.length, removed: removed));
    }
    _reconcile();
  }

  /// FlClash's `Profile.update` (same request and User-Agent) keeping the headers it drops.
  /// The url holds the customer's token: never log it, nor the error, which can quote it.
  Future<Profile?> _download(
    String url, {
    String? label,
    bool needsServers = false,
    bool refresh = false,
  }) async {
    final response = await request
        .getFileResponseForUrl(url)
        .timeout(const Duration(seconds: 30));
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
    // A panel may send a used-up or expired service with no servers until renewal.
    if (needsServers && _serviceFrom(draft).ended == null) {
      await _needServers(body);
    }
    final profile = await draft.saveFile(body, validate: _validate);
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
