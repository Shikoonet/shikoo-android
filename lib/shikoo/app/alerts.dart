import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:fl_clash/plugins/tile.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart'
    show bidiName, serverName, unnamedTitle;
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android's connection alerts (variant ب, `.notes/drop-notices-2026-10-30/ui/variants.html`), which
/// `ShikooAlerts.kt` posts in one shared place. None while the app is on screen, where its own cards
/// speak, and none once the customer stopped the tunnel. A revoke is Kotlin's alone: Dart may be gone.
enum ShikooAlert { noTraffic, dropped, ended, refused, removed }

/// A stop that a start follows this soon is a switch of server or core, not a drop.
@visibleForTesting
Duration alertSettle = const Duration(seconds: 3);

final shikooAlertsProvider = Provider<ShikooAlerts>(ShikooAlerts.new);

typedef _Ended = ({int? id, ShikooServiceStatus? ended});

class ShikooAlerts with TileListener {
  ShikooAlerts(this._ref) {
    // Made after the first frame, often with the tunnel already up.
    _ref.listen(
      shikooStateProvider.select((s) => s.connection),
      _connection,
      fireImmediately: true,
    );
    _ref.listen(shikooStateProvider.select((s) => s.selected), (_, _) {
      _session++;
      _cancel(ShikooAlert.noTraffic);
    });
    _ref.listen(shikooStateProvider.select(_endedOf), _ended);
    _ref.listen(
      shikooLookProvider.select((look) => look.language),
      (_, _) => unawaited(_primeRevoked()),
    );
    tile?.addListener(this);
    _channel.setMethodCallHandler(_fromNative);
    _ref.onDispose(() {
      _settle?.cancel();
      tile?.removeListener(this);
      _channel.setMethodCallHandler(null);
    });
  }

  final Ref _ref;
  static const _channel = MethodChannel('shikoo/alerts');
  static const _refusedKey = 'shikoo.alerts.refused';

  /// The tunnel came up and has not settled down since.
  bool _up = false;
  Timer? _settle;

  /// Bumped by every connect and every server picked: one no-internet alert each.
  int _session = 0;
  int? _noTrafficIn;
  final _removed = <String>{};

  ShikooController get _controller => _ref.read(shikooControllerProvider);

  ShikooState get _state => _ref.read(shikooStateProvider);

  String get _language => _ref.read(shikooLookProvider).language;

  ShikooL10n get _l => lookupShikooL10n(Locale(_language));

  /// After the first frame: an alert tapped while no app ran waits in Kotlin until now.
  Future<void> start() async {
    await _ref.read(shikooAlertNoTrafficProvider.notifier).load();
    await _ref.read(shikooAlertDroppedProvider.notifier).load();
    await _primeRevoked();
    if (await _channel.invokeMethod<String>('target') case final target?) {
      _open(target);
    }
  }

  @override
  void onStop() => _controller.offByCustomer = true;

  @override
  void onStart() => _controller.offByCustomer = false;

  void _connection(ShikooConnection? was, ShikooConnection now) {
    _settle?.cancel();
    if (now == ShikooConnection.on) {
      _session++;
      _up = true;
      _cancel(ShikooAlert.dropped);
      _cancel(ShikooAlert.refused);
      _cancel(ShikooAlert.removed);
      if (_state.service?.finished != true) _cancel(ShikooAlert.ended);
      return;
    }
    _cancel(ShikooAlert.noTraffic);
    if (now != ShikooConnection.connecting && _up) {
      _settle = Timer(alertSettle, _settled);
    }
  }

  /// Any change of the connection cancels the wait, so the tunnel is still down here.
  void _settled() {
    _up = false;
    if (!_ref.read(shikooAlertDroppedProvider)) return;
    final l = _l;
    unawaited(
      _post(
        ShikooAlert.dropped,
        title: l.alertDroppedTitle(l.appName),
        body: l.alertDroppedBody(l.appName),
        tap: 'home',
        actions: _droppedActions(l),
      ),
    );
  }

  static _Ended _endedOf(ShikooState s) => (
    id: s.service?.id,
    ended: s.service?.finished ?? false ? s.service!.ended : null,
  );

  /// Once per ending: only the service in use turning from active to ended while connected.
  void _ended(_Ended? was, _Ended now) {
    if (now.ended == null) {
      if (was?.id == now.id && was?.ended != null) {
        _cancel(ShikooAlert.ended);
      }
      return;
    }
    if (was?.id != now.id || was?.ended != null || !_up) return;
    final service = _state.service!;
    final account = _ref.read(shikooAccountProvider);
    final id = account.serviceOf(service.id);
    final l = _l;
    unawaited(
      _post(
        ShikooAlert.ended,
        title: now.ended == ShikooServiceStatus.exhausted
            ? l.alertExhaustedTitle
            : l.alertExpiredTitle,
        body: l.alertEndedBody(
          service.name.isEmpty
              ? unnamedTitle(l, _language, service.number)
              : bidiName(service.name),
        ),
        tap: 'card:${service.id}',
        actions: [
          [
            l.renew,
            'url:${id == null ? ShikooLinks.renew : ShikooLinks.renewOne(id, account.bot)}',
          ],
        ],
      ),
    );
  }

  /// At most one per connect or server picked; it goes once traffic passes, or with the switch or the stop.
  Future<void> noTraffic(String server) async {
    if (_noTrafficIn == _session || !_ref.read(shikooAlertNoTrafficProvider)) {
      return;
    }
    final l = _l;
    if (await _post(
      ShikooAlert.noTraffic,
      title: l.alertNoTrafficTitle,
      body: l.alertNoTrafficBody(serverName(server)),
      tap: 'list',
      actions: [
        [l.alertPickAnother, 'open:list'],
        [l.alertDontShow, 'mute'],
      ],
    )) {
      _noTrafficIn = _session;
    }
  }

  void trafficPassed() => _cancel(ShikooAlert.noTraffic);

  /// At most once a day for each server, kept across starts: the account stays refused until support acts.
  Future<void> refused(String server) async {
    final prefs = await SharedPreferences.getInstance();
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final sent = {
      for (final MapEntry(:key, :value)
          in (jsonDecode(prefs.getString(_refusedKey) ?? '{}') as Map).entries)
        if (value == day) '$key': day,
    };
    if (sent.containsKey(server)) return;
    final service = _state.service;
    final l = _l;
    if (!await _post(
      ShikooAlert.refused,
      title: l.alertRefusedTitle,
      body: l.alertRefusedBody(serverName(server)),
      tap: service == null ? 'home' : 'card:${service.id}',
      actions: [
        [l.support, 'url:${service?.supportLink ?? ShikooLinks.support}'],
      ],
    )) {
      return;
    }
    await prefs.setString(_refusedKey, jsonEncode({...sent, server: day}));
  }

  /// Once for each server an update took away.
  Future<void> removed(String server) async {
    final key = '${_state.service?.id}/$server';
    if (_removed.contains(key)) return;
    final l = _l;
    if (await _post(
      ShikooAlert.removed,
      title: l.alertRemovedTitle,
      body: l.alertRemovedBody(serverName(server)),
      tap: 'list',
      actions: [
        [l.alertPickServer, 'open:list'],
      ],
    )) {
      _removed.add(key);
    }
  }

  List<List<String>> _droppedActions(ShikooL10n l) => [
    [l.alertReconnect, 'start'],
    [l.alertDontShow, 'mute'],
  ];

  /// What Kotlin posts on a revoke, in the language of the moment.
  Future<void> _primeRevoked() {
    final l = _l;
    return _channel.invokeMethod<bool>(
      'revokedAlert',
      _alert(
        ShikooAlert.dropped,
        title: l.alertDroppedTitle(l.appName),
        body: l.alertRevokedBody(l.appName),
        tap: 'home',
        actions: _droppedActions(l),
      ),
    );
  }

  Future<bool> _post(
    ShikooAlert kind, {
    required String title,
    required String body,
    required String tap,
    required List<List<String>> actions,
  }) async {
    if (_controller.foreground || _controller.offByCustomer) return false;
    return await _channel.invokeMethod<bool>(
          'post',
          _alert(kind, title: title, body: body, tap: tap, actions: actions),
        ) ??
        false;
  }

  Map<String, Object> _alert(
    ShikooAlert kind, {
    required String title,
    required String body,
    required String tap,
    required List<List<String>> actions,
  }) => {
    'kind': kind.name,
    'channel': _l.alerts,
    'title': title,
    'body': body,
    'tap': tap,
    'actions': actions,
  };

  /// Kotlin clears it only while it is the alert showing.
  void _cancel(ShikooAlert kind) =>
      unawaited(_channel.invokeMethod<bool>('cancel', kind.name));

  Future<void> _fromNative(MethodCall call) async {
    switch (call.method) {
      case 'open':
        _open(call.arguments as String);
      case 'muted':
        await _ref
            .read(
              call.arguments == ShikooAlert.noTraffic.name
                  ? shikooAlertNoTrafficProvider.notifier
                  : shikooAlertDroppedProvider.notifier,
            )
            .set(false);
    }
  }

  /// `list` opens the card in use, with its servers; `card:<id>` that service's card; `home` the home alone.
  void _open(String target) {
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    final id = target == 'list'
        ? _state.service?.id
        : int.tryParse(target.replaceFirst('card:', ''));
    if (id != null) _controller.openService(id);
  }
}
