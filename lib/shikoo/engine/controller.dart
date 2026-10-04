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
import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter/foundation.dart';
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

enum ShikooServiceStatus { active, expired, exhausted }

enum ShikooPick { server, finding, none }

enum ShikooRefresh { idle, running, failed }

const connectTimeout = Duration(seconds: 30);

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

  /// Came with an update since the app started.
  final bool fresh;

  String get label => withoutFlags(name);

  String? get country => countryOf(name);
}

@immutable
class ShikooService {
  const ShikooService({
    required this.name,
    required this.usedBytes,
    required this.totalBytes,
    this.expire,
    this.announce,
    this.supportUrl,
    this.updatedAt,
    this.profileId,
  });

  final String name;
  final int? profileId;
  final int usedBytes;

  /// 0 = no volume limit.
  final int totalBytes;
  final DateTime? expire;
  final String? announce;
  final String? supportUrl;

  final DateTime? updatedAt;

  String get supportLink => usableLink(supportUrl) ?? ShikooLinks.support;

  /// The name is `<username> · <tier>`, as in the bot's "my services".
  String get username => name.split(' · ').first;

  ShikooServiceStatus statusAt(DateTime now) {
    if (expire != null && !expire!.isAfter(now)) {
      return ShikooServiceStatus.expired;
    }
    if (totalBytes > 0 && usedBytes >= totalBytes) {
      return ShikooServiceStatus.exhausted;
    }
    return ShikooServiceStatus.active;
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

/// Only for an update the user asked for; an automatic one just says so under the name.
class RefreshFailed extends ShikooNotice {
  const RefreshFailed();
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

  ShikooServer? get selectedServer =>
      servers.firstWhereOrNull((server) => server.name == selected);
}

@immutable
class _Intent {
  const _Intent({this.connecting = false, this.waiting = false, this.error});

  final bool connecting;
  final bool waiting;
  final ShikooError? error;
}

class _Cell<T> extends Notifier<T> {
  _Cell(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  void set(T value) => state = value;
}

NotifierProvider<_Cell<T>, T> _cell<T>(T initial) =>
    NotifierProvider<_Cell<T>, T>(() => _Cell(initial));

final _intentProvider = _cell(const _Intent());

typedef _Round = ({Set<String> pending, int total, bool ended});

final _roundProvider = _cell<_Round>((
  pending: const <String>{},
  total: 0,
  ended: false,
));
final _orderProvider = _cell<List<String>>(const []);

/// Our own verdicts by name. FlClash's delay table also takes the core's group health checks
/// (a "Fastest" group with its own timeout), which repainted healthy servers as dead.
final _pingsProvider = _cell<Map<String, int>>(const {});
final _refreshProvider = _cell(ShikooRefresh.idle);
final _freshProvider = _cell<Set<String>>(const {});
final _noticeProvider = _cell<ShikooNotice?>(null);

/// The tunnel's real start; FlClash's run time starts at the press, before the consent dialog.
final _nativeStartProvider = _cell<DateTime?>(null);

/// Panel headers FlClash does not keep (`announce`, `support-url`), per profile id.
typedef _Extras = ({String? announce, String? supportUrl});

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
          '$key': {'announce': value.announce, 'supportUrl': value.supportUrl},
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
    !_infoRowParts.any(name.contains);

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
  required bool pinging,
  required bool roundEnded,
  required bool anyAnswer,
}) {
  if (selected) return ShikooPick.server;
  if (pinging || !roundEnded || anyAnswer) return ShikooPick.finding;
  return ShikooPick.none;
}

final shikooStateProvider = Provider<ShikooState>((ref) {
  final runTime = ref.watch(runTimeProvider);
  final nativeStart = ref.watch(_nativeStartProvider);
  final intent = ref.watch(_intentProvider);
  final profile = ref.watch(currentProfileProvider);
  final extras = ref.watch(_extrasProvider)[profile?.id];
  final info = profile?.subscriptionInfo;
  final group = _mainGroup(ref);
  final round = ref.watch(_roundProvider);
  final pings = ref.watch(_pingsProvider);
  final fresh = ref.watch(_freshProvider);
  final byName = {for (final proxy in _serversOf(group)) proxy.name: proxy};
  final chosen = group == null
      ? null
      : ref.watch(selectedMapProvider)[group.name];
  final selected = byName.containsKey(chosen) ? chosen : null;
  final servers = [
    for (final name in keepOrder(ref.watch(_orderProvider), [...byName.keys]))
      ShikooServer(
        name: name,
        type: byName[name]!.type,
        ping: round.pending.contains(name) ? null : pings[name],
        testing: round.pending.contains(name),
        fresh: fresh.contains(name),
      ),
  ];
  final pinging = round.total > 0;
  return ShikooState(
    connection: deriveConnection(
      connecting: intent.connecting,
      running: runTime != null || nativeStart != null,
      error: intent.error,
    ),
    connectedFor: nativeStart != null
        ? DateTime.now().difference(nativeStart)
        : Duration(milliseconds: runTime ?? 0),
    isTV: system.isTV,
    service: profile == null
        ? null
        : ShikooService(
            name: profile.label,
            profileId: profile.id,
            usedBytes: (info?.upload ?? 0) + (info?.download ?? 0),
            totalBytes: info?.total ?? 0,
            expire: (info?.expire ?? 0) > 0
                ? DateTime.fromMillisecondsSinceEpoch(info!.expire * 1000)
                : null,
            announce: extras?.announce,
            supportUrl: extras?.supportUrl,
            updatedAt: profile.lastUpdateDate,
          ),
    servers: servers,
    selected: selected,
    lastError: intent.error,
    pick: derivePick(
      selected: selected != null,
      pinging: pinging,
      roundEnded: round.ended,
      anyAnswer: servers.any((server) => (server.ping ?? 0) > 0),
    ),
    pinging: pinging
        ? (done: round.total - round.pending.length, total: round.total)
        : null,
    refresh: ref.watch(_refreshProvider),
    notice: ref.watch(_noticeProvider),
    waiting: intent.waiting,
  );
});

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

SubscriptionInfo _subscriptionInfo(String? header) {
  try {
    return SubscriptionInfo.formHString(header);
  } on RangeError {
    // FlClash's parser throws on a segment without "=", such as a trailing ";".
    return const SubscriptionInfo();
  }
}

/// Never the core's fallback, row 1 (the version row in a real subscription): with the tunnel
/// up or connect pressed, the first server that answers; otherwise the fastest at round end.
String? pickNow({
  required List<String> names,
  required int? Function(String name) ping,
  required bool pinging,
  required bool urgent,
}) => pinging && !urgent ? null : fastest(names, ping);

class ShikooController {
  // Microtasks: Riverpod forbids writing other providers while this one is being built.
  ShikooController(this._ref) {
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
        (s) => (s.servers.map((e) => e.name).toList()..sort()).join('\n'),
      ),
      (previous, names) {
        if (names.isNotEmpty && names != previous) scheduleMicrotask(pingAll);
      },
      fireImmediately: true,
    );
    _ref.listen(runTimeProvider.select((time) => time != null), (_, running) {
      scheduleMicrotask(running ? _reconcile : () => _nativeStart(null));
    });
    app?.onVpnConsent = onVpnConsent;
    scheduleMicrotask(() => _ref.read(_extrasProvider.notifier).load());
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
  Set<String> _roundNames = const {};
  bool _again = false;
  DateTime? _lastRound;

  /// The selection an update just took away, for the notice that names it.
  String? _removed;
  Future<void>? _refreshing;
  bool _manualRefresh = false;

  SetupAction get _setup => _ref.read(setupActionProvider.notifier);

  ProxiesAction get _proxies => _ref.read(proxiesActionProvider.notifier);

  Group? get _group => _ref.read(currentGroupsStateProvider).value.firstOrNull;

  void _set(_Intent intent) => _ref.read(_intentProvider.notifier).set(intent);

  String get _service => '${_ref.read(currentProfileIdProvider)}';

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

  bool get _pinging => _ref.read(_roundProvider).total > 0;

  bool get _running =>
      _ref.read(runTimeProvider) != null ||
      _ref.read(_nativeStartProvider) != null;

  void _notice(ShikooNotice? notice) =>
      _ref.read(_noticeProvider.notifier).set(notice);

  /// News leaves with the app or the next update; a failed update stays until one succeeds.
  void clearNews() {
    if (_ref.read(_noticeProvider) is! RefreshFailed) _notice(null);
  }

  List<String> _names(Group? group) => [
    for (final proxy in _serversOf(group)) proxy.name,
  ];

  String _testUrl(Group group) => _ref.read(realTestUrlProvider(group.testUrl));

  int? _ping(String name) => _ref.read(_pingsProvider)[name];

  String? _validSelection() {
    final group = _group;
    if (group == null) return null;
    final chosen = _ref.read(selectedMapProvider)[group.name];
    return _names(group).contains(chosen) ? chosen : null;
  }

  Future<void> connect() async {
    if (_ref.read(currentProfileProvider) == null) return;
    if (_validSelection() != null) return _start();
    _set(const _Intent(connecting: true, waiting: true));
    if (!_pinging) unawaited(pingAll());
    _reconcile();
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
    _ref.read(_pingsProvider.notifier).set(const {});
    _ref.read(_orderProvider.notifier).set(const []);
    _ref.read(_freshProvider.notifier).set(const {});
  }

  /// The user's choice, which the app never replaces.
  Future<void> selectServer(String name) async {
    _pickedByApp(null);
    if (_ref.read(_noticeProvider)
        case SilentReplaced() || SelectedReplaced()) {
      _notice(null);
    }
    await _choose(name);
    await _checkSelected();
  }

  Future<void> _choose(String name) async {
    final group = _group;
    if (group == null) return;
    await _proxies.changeProxy(groupName: group.name, proxyName: name);
    _proxies.updateGroupsDebounce();
    final applied = _ref.read(selectedProxyNameProvider(group.name)) == name;
    final intent = _ref.read(_intentProvider);
    if (applied && intent.waiting) {
      unawaited(_start());
      return;
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
    if (group == null || _validSelection() != null) return;
    final names = _names(group);
    if (names.isEmpty) return;
    final running = _running;
    final waiting = _ref.read(_intentProvider).waiting;
    final pinging = _pinging || _again;
    // Connect pressed while finding takes this round's first answer, not the round before's best;
    // with the tunnel up the old best beats the core's fallback, row 1.
    final pending = running
        ? const <String>{}
        : _ref.read(_roundProvider).pending;
    int? ping(String name) => pending.contains(name) ? null : _ping(name);
    final best = pickNow(
      names: names,
      ping: ping,
      pinging: pinging,
      urgent: running || waiting,
    );
    if (best == null) {
      if (!pinging && waiting) _set(const _Intent(error: ShikooError.noServer));
      return;
    }
    final removed = _removed;
    _removed = null;
    _pickedByApp(best);
    // changeProxy writes the selection before it awaits, so a second call sees it.
    unawaited(_choose(best));
    if (removed != null) {
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

  Future<void> pingAll() async {
    final group = _group;
    final names = _names(group);
    if (_pinging) {
      _again |= !setEquals(names.toSet(), _roundNames);
      return;
    }
    if (group == null || names.isEmpty) return;
    _roundNames = names.toSet();
    final round = _ref.read(_roundProvider.notifier);
    round.set((pending: names.toSet(), total: names.length, ended: false));
    final url = _testUrl(group);
    try {
      await pingServers(names, (name) => _probe(url, name), (name, ms) {
        _setPing(name, ms);
        final now = _ref.read(_roundProvider);
        round.set((
          pending: {...now.pending}..remove(name),
          total: now.total,
          ended: false,
        ));
        if (ms > 0) {
          if (_ref.read(_intentProvider).error == ShikooError.noServer) {
            _set(const _Intent());
          }
          _reconcile();
        }
      });
    } finally {
      _lastRound = DateTime.now();
      final current = _group;
      if (current != null) {
        _ref
            .read(_orderProvider.notifier)
            .set(sortByPing(_names(current), _ping));
      }
      round.set((pending: const <String>{}, total: 0, ended: true));
      unawaited(_replaceSilentPick());
      _reconcile();
      if (_again) {
        _again = false;
        unawaited(pingAll());
      }
    }
  }

  void _setPing(String name, int ms) => _ref.read(_pingsProvider.notifier).set({
    ..._ref.read(_pingsProvider),
    name: ms,
  });

  Future<void> _checkSelected() async {
    final group = _group;
    final chosen = _validSelection();
    if (group == null || chosen == null || _pinging) return;
    final url = _testUrl(group);
    await pingServers([chosen], (name) => _probe(url, name), _setPing);
    await _replaceSilentPick();
  }

  Future<void> _replaceSilentPick() async {
    final chosen = _validSelection();
    if (chosen == null || chosen != _appPick) return;
    final ms = _ping(chosen);
    if (ms == null || ms > 0) return;
    // Flutter says running from the press on; a probe under the consent dialog proves nothing.
    if (_running && await _nativeRunTime() == null) return;
    if (_validSelection() != chosen) return;
    final best = fastest(_names(_group), _ping);
    if (best == null) return;
    _pickedByApp(best);
    unawaited(_choose(best));
    _notice(SilentReplaced(silent: chosen, replacement: best, moved: _running));
  }

  /// WireGuard pings can fail while it carries traffic, so real traffic decides for the selection.
  Future<int?> _probe(String url, String name) async {
    int? ms;
    try {
      ms = (await _ref.read(coreHandlerProvider).getDelay(url, name))?.value;
    } catch (_) {}
    bool carriesTraffic() => name == _validSelection() && _running;
    if ((ms ?? 0) > 0 || !carriesTraffic()) return ms;
    if (await _nativeRunTime() == null) return ms;
    final took = Stopwatch()..start();
    final passes = await _ref.read(trafficPassesProvider)();
    // The lookup went out through whatever carried traffic when it ended, maybe not [name].
    return passes && carriesTraffic()
        ? math.max(took.elapsedMilliseconds, 1)
        : ms;
  }

  void onForeground() {
    final now = DateTime.now();
    if (!_pinging && isDue(_lastRound, now, pingEvery)) unawaited(pingAll());
    final updated = _ref.read(currentProfileProvider)?.lastUpdateDate;
    if (isDue(updated, now, refreshEvery)) {
      unawaited(refreshService(manual: false));
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
      await _download(profile.url, profile.label);
      if (!await _setup.applyProfile(silence: true)) {
        throw StateError('apply');
      }
    } catch (_) {
      status.set(ShikooRefresh.failed);
      if (_manualRefresh) _notice(const RefreshFailed());
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
    _ref.read(_freshProvider.notifier).set({
      ..._ref.read(_freshProvider).where(after.contains),
      ...added,
    });
    if (had != null && removed.contains(had)) {
      _removed = had;
    } else if (added.isNotEmpty || removed.isNotEmpty) {
      _notice(ServersChanged(added: added.length, removed: removed));
    }
    // Started here, not by the list listener, so a replacement waits for fresh pings.
    if (added.isNotEmpty || removed.isNotEmpty) unawaited(pingAll());
    _reconcile();
  }

  /// FlClash's `Profile.update` (same request and User-Agent) keeping the headers it drops.
  /// The url holds the customer's token: never log it, nor the error, which can quote it.
  Future<Profile> _download(String url, [String? label]) async {
    final response = await request
        .getFileResponseForUrl(url)
        .timeout(const Duration(seconds: 30));
    final header = response.headers.value;
    final existing = _ref
        .read(profilesProvider)
        .firstWhereOrNull((profile) => profile.url == url);
    final profile = await (existing ?? Profile.normal(url: url))
        .copyWith(
          label:
              label ??
              headerText(header('profile-title')) ??
              Uri.parse(url).host,
          // FlClash's own daily update would race this one and drop the headers kept below.
          autoUpdate: false,
          subscriptionInfo: _subscriptionInfo(header('subscription-userinfo')),
        )
        .saveFile(
          response.data ?? Uint8List(0),
          validate: (path) =>
              _ref.read(coreHandlerProvider).validateConfig(path),
        );
    _ref.read(profilesActionProvider.notifier).putProfile(profile);
    await _ref.read(_extrasProvider.notifier).put(profile.id, (
      announce: headerText(header('announce')),
      supportUrl: headerText(header('support-url')),
    ));
    return profile;
  }

  /// Null once the service is in, named by the panel unless [label] is given. Without [select]
  /// it becomes the current service only when there is none.
  Future<ShikooPasteError?> addService(
    String url, [
    String? label,
    bool select = true,
  ]) async {
    try {
      final profile = await _download(url, label);
      if (_ref.read(currentProfileIdProvider) == profile.id) {
        // The core re-reads a profile only when the selection changes.
        await _setup.applyProfile(silence: true);
      } else if (select) {
        _ref.read(currentProfileIdProvider.notifier).value = profile.id;
      }
      return null;
    } catch (error) {
      return addFailure(error);
    }
  }

  /// What the user pasted holds a token: nothing here shows or logs it.
  Future<ShikooPasteError?> pasteService(String? text) async {
    if (text == null || text.trim().isEmpty) return ShikooPasteError.empty;
    final link = shikooLink(text);
    if (link == null) return ShikooPasteError.notShikoo;
    return addService(link);
  }
}
