import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The only door from Shikoo screens into FlClash's engine (docs/extensibility.md section 1).

enum ShikooConnection { off, connecting, on, error }

enum ShikooError { connectTimeout, serverChange, addService }

enum ShikooServiceStatus { active, expired, exhausted }

// ponytail: native never reports a refused VPN consent (engine map section 4), so a user
// slower than this on the consent dialog sees "couldn't connect" and presses again.
const connectTimeout = Duration(seconds: 30);

@immutable
class ShikooServer {
  const ShikooServer({
    required this.name,
    required this.type,
    this.ping,
    this.testing = false,
  });

  final String name;

  /// The engine's protocol name, kept as data so a new protocol needs no screen change.
  final String type;

  /// Milliseconds; null = not tested yet, -1 = no answer.
  final int? ping;
  final bool testing;

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
  });

  final String name;
  final int usedBytes;

  /// 0 = no volume limit.
  final int totalBytes;
  final DateTime? expire;
  final String? announce;
  final String? supportUrl;

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
  });

  final ShikooConnection connection;
  final Duration connectedFor;
  final bool isTV;
  final ShikooService? service;
  final List<ShikooServer> servers;
  final String? selected;
  final ShikooError? lastError;

  ShikooServer? get selectedServer =>
      servers.firstWhereOrNull((server) => server.name == selected);
}

@immutable
class _Intent {
  const _Intent({this.connecting = false, this.error});

  final bool connecting;
  final ShikooError? error;
}

class _IntentNotifier extends Notifier<_Intent> {
  @override
  _Intent build() => const _Intent();

  void set(_Intent value) => state = value;
}

final _intentProvider = NotifierProvider<_IntentNotifier, _Intent>(
  _IntentNotifier.new,
);

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

Group? _mainGroup(Ref ref) =>
    ref.watch(currentGroupsStateProvider).value.firstOrNull;

ShikooConnection deriveConnection({
  required bool connecting,
  required bool running,
  required ShikooError? error,
}) {
  if (connecting) return ShikooConnection.connecting;
  if (running) return ShikooConnection.on;
  if (error == ShikooError.connectTimeout) return ShikooConnection.error;
  return ShikooConnection.off;
}

final shikooStateProvider = Provider<ShikooState>((ref) {
  final runTime = ref.watch(runTimeProvider);
  final intent = ref.watch(_intentProvider);
  final profile = ref.watch(currentProfileProvider);
  final extras = ref.watch(_extrasProvider)[profile?.id];
  final info = profile?.subscriptionInfo;
  final group = _mainGroup(ref);
  final servers = <ShikooServer>[
    for (final proxy in group?.all ?? const <Proxy>[])
      if (!_notServers.contains(proxy.type))
        ShikooServer(
          name: proxy.name,
          type: proxy.type,
          ping: ref.watch(
            delayProvider(proxyName: proxy.name, testUrl: group!.testUrl),
          ),
          testing: ref.watch(
            delayTestPendingProvider(
              proxyName: proxy.name,
              testUrl: group.testUrl,
            ),
          ),
        ),
  ];
  return ShikooState(
    connection: deriveConnection(
      connecting: intent.connecting,
      running: runTime != null,
      error: intent.error,
    ),
    connectedFor: Duration(milliseconds: runTime ?? 0),
    isTV: system.isTV,
    service: profile == null
        ? null
        : ShikooService(
            name: profile.label,
            usedBytes: (info?.upload ?? 0) + (info?.download ?? 0),
            totalBytes: info?.total ?? 0,
            expire: (info?.expire ?? 0) > 0
                ? DateTime.fromMillisecondsSinceEpoch(info!.expire * 1000)
                : null,
            announce: extras?.announce,
            supportUrl: extras?.supportUrl,
          ),
    servers: servers,
    selected: group == null
        ? null
        : ref.watch(selectedProxyNameProvider(group.name)),
    lastError: intent.error,
  );
});

final shikooControllerProvider = Provider<ShikooController>(
  ShikooController.new,
);

/// Polls [runTime] until native reports a running tunnel. Flutter's own run state is set
/// optimistically before the service starts (engine map section 4), so only native is proof.
Future<bool> waitForTunnel(
  Future<DateTime?> Function() runTime, {
  required Duration timeout,
  required bool Function() stillWanted,
  Duration every = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (stillWanted()) {
    if (await runTime() != null) return true;
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(every);
  }
  return false;
}

SubscriptionInfo _subscriptionInfo(String? header) {
  try {
    return SubscriptionInfo.formHString(header);
  } on RangeError {
    // FlClash's parser throws on a segment without "=", such as a trailing ";".
    return const SubscriptionInfo();
  }
}

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
        (s) => s.servers.map((e) => e.name).join('\n'),
      ),
      (previous, names) {
        if (names.isNotEmpty && names != previous) scheduleMicrotask(pingAll);
      },
      fireImmediately: true,
    );
    scheduleMicrotask(() => _ref.read(_extrasProvider.notifier).load());
  }

  final Ref _ref;
  int _attempt = 0;

  SetupAction get _setup => _ref.read(setupActionProvider.notifier);

  ProxiesAction get _proxies => _ref.read(proxiesActionProvider.notifier);

  Group? get _group => _ref.read(currentGroupsStateProvider).value.firstOrNull;

  void _set(_Intent intent) => _ref.read(_intentProvider.notifier).set(intent);

  Future<void> connect() async {
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
    final up =
        started &&
        await waitForTunnel(
          () async => service?.getRunTime(),
          timeout: connectTimeout,
          stillWanted: () => attempt == _attempt,
        );
    if (attempt != _attempt) return;
    if (up) {
      _set(const _Intent());
      return;
    }
    _set(const _Intent(error: ShikooError.connectTimeout));
    await _setup.setRunning(false);
  }

  Future<void> disconnect() async {
    _attempt++;
    _set(const _Intent());
    await _setup.setRunning(false);
  }

  Future<void> selectServer(String name) async {
    final group = _group;
    if (group == null) return;
    await _proxies.changeProxy(groupName: group.name, proxyName: name);
    _proxies.updateGroupsDebounce();
    final applied = _ref.read(selectedProxyNameProvider(group.name)) == name;
    final intent = _ref.read(_intentProvider);
    _set(
      _Intent(
        connecting: intent.connecting,
        error: applied ? null : ShikooError.serverChange,
      ),
    );
  }

  /// One at a time: engine map section 3 suspects parallel probes of the spike's false timeouts.
  Future<void> pingAll() async {
    final group = _group;
    if (group == null) return;
    for (final proxy in group.all) {
      if (_notServers.contains(proxy.type)) continue;
      await _proxies.proxyDelayTest(proxy, group.testUrl);
    }
  }

  /// FlClash's `Profile.update` (same request and User-Agent) keeping the headers it drops.
  /// The url holds the customer's token: never log it, nor the error, which can quote it.
  Future<void> addService(String url, String label) async {
    try {
      final response = await request
          .getFileResponseForUrl(url)
          .timeout(const Duration(seconds: 30));
      final header = response.headers.value;
      final existing = _ref
          .read(profilesProvider)
          .firstWhereOrNull((profile) => profile.url == url);
      final profile = await (existing ?? Profile.normal(url: url))
          .copyWith(
            label: label,
            subscriptionInfo: _subscriptionInfo(
              header('subscription-userinfo'),
            ),
          )
          .saveFile(
            response.data ?? Uint8List(0),
            validate: (path) =>
                _ref.read(coreHandlerProvider).validateConfig(path),
          );
      _ref.read(profilesActionProvider.notifier).putProfile(profile);
      _ref.read(currentProfileIdProvider.notifier).value = profile.id;
      await _ref.read(_extrasProvider.notifier).put(profile.id, (
        announce: headerText(header('announce')),
        supportUrl: headerText(header('support-url')),
      ));
    } catch (_) {
      _set(const _Intent(error: ShikooError.addService));
    }
  }
}
