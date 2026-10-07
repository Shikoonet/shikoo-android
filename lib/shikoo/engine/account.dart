import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpHeaders, InternetAddress;

import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter/foundation.dart' hide mergeSort;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign-in with Telegram through the shop bot, against shikoo-platform's
/// `apps/ingest-worker/src/appApi.ts`. The token, the poll secret and the code are never logged:
/// they travel in bodies and headers only, and nothing here prints a request or a response.

enum LoginPhase {
  starting,
  startFailed,
  waiting,
  expired,
  rejected,
  syncing,
  approved,
  servicesFailed,
  noService,
}

@immutable
class TelegramAccount {
  const TelegramAccount({this.name, this.username});

  final String? name;

  /// Without the `@`.
  final String? username;
}

@immutable
class ShikooLogin {
  const ShikooLogin(
    this.phase, {
    this.code,
    this.botUrl,
    this.account,
    this.services = const [],
    this.clock = false,
  });

  final LoginPhase phase;

  final String? code;
  final String? botUrl;
  final TelegramAccount? account;
  final List<String> services;
  final bool clock;
}

@immutable
class LinkedService {
  const LinkedService({
    required this.id,
    required this.title,
    required this.status,
    this.profileId,
    this.expiresAt,
  });

  /// The statuses of shikoo-platform's `/services` that mean ended; `on_hold` has not started.
  static const finishedStatuses = {
    'expired',
    'exhausted',
    'removed',
    'disabled',
    'failed',
  };

  final int id;
  final String title;

  final String status;
  final int? profileId;
  final DateTime? expiresAt;

  bool get renews => finishedStatuses.contains(status);

  /// Turned off by the shop, maybe before its end date: no «ended N days ago».
  bool get disabled => const {'removed', 'disabled', 'failed'}.contains(status);
}

const finishedMaxDays = 30;

/// A row of «سرویس‌های تمام‌شده»: a service of this device ([profileId]) or of the account.
typedef Finished = ({
  String name,
  bool exhausted,
  DateTime? ended,
  int? renewId,
  int? profileId,
  LinkedService? linked,
});

DateTime? _sortEnd(Finished row) =>
    (row.linked?.disabled ?? false) ? null : row.ended;

Finished finishedOf(ShikooService service, {String? name, int? renewId}) => (
  name: name ?? service.name,
  exhausted: service.ended == ShikooServiceStatus.exhausted,
  ended: service.expire,
  renewId: renewId,
  profileId: service.id,
  linked: null,
);

/// Latest end first, undated last; an end over [finishedMaxDays] ago is left out.
List<Finished> finishedOrder(Iterable<Finished> all, DateTime now) {
  final shown = [
    for (final row in all)
      if (row.ended == null ||
          now.difference(row.ended!) <= const Duration(days: finishedMaxDays))
        row,
  ];
  mergeSort(
    shown,
    compare: (a, b) => switch ((_sortEnd(a), _sortEnd(b))) {
      (final x?, final y?) => y.compareTo(x),
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
    },
  );
  return shown;
}

@immutable
class ShikooAccount {
  const ShikooAccount({this.who, this.bot, this.services = const []});

  /// Signed in when not null.
  final TelegramAccount? who;
  final String? bot;
  final List<LinkedService> services;

  List<LinkedService> get withoutLink => [
    for (final service in services)
      if (service.profileId == null) service,
  ];

  int? serviceOf(int? profileId) => profileId == null
      ? null
      : services.firstWhereOrNull((s) => s.profileId == profileId)?.id;
}

final shikooAccountProvider =
    NotifierProvider<ShikooCell<ShikooAccount>, ShikooAccount>(
      () => ShikooCell(const ShikooAccount()),
    );

/// A sign-in on screen; null before one starts and once it is done.
final shikooLoginProvider =
    NotifierProvider<ShikooCell<ShikooLogin?>, ShikooLogin?>(
      () => ShikooCell(null),
    );

final _notAllowed = RegExp(r'[^A-Za-z0-9 _()-]+');

/// What the bot shows under «وصل شود؟». The server takes only ASCII letters, digits, space and
/// `_ ( ) -`, 1 to 40 of them: `.` `+` `@` `/` `:` would make Telegram links.
String deviceName(String manufacturer, String model, {required bool tv}) {
  final full = model.toLowerCase().startsWith(manufacturer.toLowerCase())
      ? model
      : '$manufacturer $model';
  final name = full.replaceAll(_notAllowed, ' ').replaceAll(RegExp(' +'), ' ');
  final cut = (name.length > 40 ? name.substring(0, 40) : name).trim();
  return cut.isNotEmpty ? cut : (tv ? 'Android TV' : 'Android phone');
}

final shikooDeviceProvider =
    Provider<Future<({String name, bool tv})> Function()>(
      (_) => () async {
        final info = await DeviceInfoPlugin().androidInfo;
        final tv = system.isTV;
        return (
          name: deviceName(info.manufacturer, info.model, tv: tv),
          tv: tv,
        );
      },
    );

class ShikooApiFailure implements Exception {
  const ShikooApiFailure({this.clock = false});

  final bool clock;
}

class LoginCode {
  const LoginCode({
    required this.code,
    required this.secret,
    required this.botUrl,
    required this.lifetime,
  });

  final String code;
  final String secret;
  final String botUrl;
  final Duration lifetime;
}

enum PollStatus { waiting, approved, refused, expired, gone, unknown }

class PollAnswer {
  const PollAnswer(this.status, {this.token, this.account});

  final PollStatus status;
  final String? token;
  final TelegramAccount? account;
}

class AccountServiceRow {
  AccountServiceRow.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      title = json['title'] as String,
      location = json['location'] as String?,
      status = json['status'] as String,
      subUrl = json['sub_url'] as String?,
      expiresAt = switch (json['expires_at']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      };

  final int id;
  final String title;
  final String? location;
  final String status;
  final String? subUrl;
  final DateTime? expiresAt;

  String get label => location == null ? title : '$title · $location';
}

class ShikooApi {
  ShikooApi(this.bases, [Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (_) => true,
            ),
          );

  final List<String> bases;
  final Dio _dio;

  /// The address that answered last goes first; the next is the backup for a blocked one.
  int _first = 0;

  Future<Response<Object?>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async {
    (DioException, String)? failed;
    for (var i = 0; i < bases.length; i++) {
      final at = (_first + i) % bases.length;
      try {
        final response = await _dio.request<Object?>(
          '${bases[at]}/api/v1/app$path',
          data: body,
          options: Options(
            method: method,
            headers: {
              if (token != null)
                HttpHeaders.authorizationHeader: 'Bearer $token',
            },
          ),
        );
        _first = at;
        learnClock(response.headers.value(HttpHeaders.dateHeader));
        return response;
      } on DioException catch (error) {
        failed = (error, bases[at]);
      }
    }
    throw ShikooApiFailure(
      clock: failed != null && await clockFailed(failed.$1, failed.$2),
    );
  }

  static Map<String, dynamic>? _json(Response<Object?> response) =>
      switch (response.data) {
        final Map<String, dynamic> body => body,
        _ => null,
      };

  Future<LoginCode> start({
    required String deviceName,
    required bool tv,
  }) async {
    final response = await _call(
      'POST',
      '/login/start',
      body: {'device_name': deviceName, 'device_kind': tv ? 'tv' : 'phone'},
    );
    final body = _json(response);
    if (response.statusCode != 200 || body == null) {
      throw const ShikooApiFailure();
    }
    return LoginCode(
      code: body['code'] as String,
      secret: body['poll_secret'] as String,
      botUrl: body['bot_url'] as String,
      lifetime: DateTime.parse(
        body['expires_at'] as String,
      ).difference(_serverNow(response)),
    );
  }

  /// A box's clock can be hours off; the server's own clock measures the code's life.
  static DateTime _serverNow(Response<Object?> response) => DateTime.now().add(
    skewOf(response.headers.value(HttpHeaders.dateHeader)) ?? Duration.zero,
  );

  /// A 429 or a server error is only "ask again later".
  Future<PollAnswer> poll(String code, String secret) async {
    final response = await _call(
      'POST',
      '/login/poll',
      body: {'code': code, 'poll_secret': secret},
    );
    final body = _json(response);
    return switch (response.statusCode) {
      200 when body?['token'] is String => PollAnswer(
        PollStatus.approved,
        token: body!['token'] as String,
        account: switch (body['account']) {
          final Map<String, dynamic> who => TelegramAccount(
            name: who['name'] as String?,
            username: who['username'] as String?,
          ),
          _ => null,
        },
      ),
      410 => switch (body?['error']) {
        'refused' => const PollAnswer(PollStatus.refused),
        'expired' || 'used' => const PollAnswer(PollStatus.expired),
        _ => const PollAnswer(PollStatus.gone),
      },
      404 => const PollAnswer(PollStatus.unknown),
      _ => const PollAnswer(PollStatus.waiting),
    };
  }

  /// Null once the token stopped working: signed out, removed in the bot, or the customer blocked.
  Future<({String? bot, List<AccountServiceRow> services})?> services(
    String token,
  ) async {
    final response = await _call('GET', '/services', token: token);
    if (response.statusCode == 401) return null;
    final body = _json(response);
    if (response.statusCode != 200 || body == null) {
      throw const ShikooApiFailure();
    }
    return (
      bot: body['bot'] as String?,
      services: [
        for (final row in body['services'] as List)
          AccountServiceRow.fromJson(row as Map<String, dynamic>),
      ],
    );
  }

  Future<void> logout(String token) async {
    await _call('POST', '/logout', token: token);
  }
}

final shikooApiProvider = Provider<ShikooApi>((_) => ShikooApi(shikooApiBases));

Rule apiDirectRule(String base, int id) {
  final host = Uri.parse(base).host;
  return Rule.parse(
    InternetAddress.tryParse(host) == null
        ? 'DOMAIN,$host,DIRECT'
        : 'IP-CIDR,$host/32,DIRECT,no-resolve',
    id: id,
  );
}

Future<void> keepApiDirect() async {
  for (final (i, base) in shikooApiBases.indexed) {
    await database.rulesDao.putGlobalRule(apiDirectRule(base, 7470000 + i));
  }
}

final shikooSignInProvider = Provider<ShikooSignIn>(ShikooSignIn.new);

/// Kept with no link: the bot has not made it yet, or the server holds it back until renewal.
const _keepsLink = {'active', 'on_hold', 'expired', 'exhausted'};

class ShikooSignIn {
  ShikooSignIn(this._ref) {
    _ref.onDispose(() => _attempt++);
    _ref.listen(
      shikooStateProvider.select((s) => s.refresh == ShikooRefresh.running),
      (_, running) {
        if (running) unawaited(sync());
      },
    );
  }

  final Ref _ref;
  static const _key = 'shikoo.account';

  bool foreground = true;

  @visibleForTesting
  Duration pollEvery = const Duration(seconds: 3);

  @visibleForTesting
  Duration startLimit = const Duration(seconds: 30);
  String? _token;
  bool _servicesClock = false;

  /// A newer code, a sign-out or a paste ends whatever the one before was waiting for.
  int _attempt = 0;
  DateTime? _lastSync;
  (String?, Future<bool?>)? _syncing;

  ShikooApi get _api => _ref.read(shikooApiProvider);

  ShikooAccount get _account => _ref.read(shikooAccountProvider);

  void _setAccount(ShikooAccount account) =>
      _ref.read(shikooAccountProvider.notifier).set(account);

  void _login(ShikooLogin? login) =>
      _ref.read(shikooLoginProvider.notifier).set(login);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    ({String token, ShikooAccount account, Set<int?> brought})? stored;
    try {
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final services = json['services'] as List;
        stored = (
          token: json['token'] as String,
          account: ShikooAccount(
            who: TelegramAccount(
              name: json['name'] as String?,
              username: json['username'] as String?,
            ),
            bot: json['bot'] as String?,
            services: [
              for (final s in services)
                LinkedService(
                  id: s['id'] as int,
                  title: s['title'] as String,
                  status: s['status'] as String,
                  profileId: s['profileId'] as int?,
                  expiresAt: DateTime.tryParse(s['expiresAt'] as String? ?? ''),
                ),
            ],
          ),
          brought: {
            for (final s in services)
              if (s['owned'] != false) s['profileId'] as int?,
          },
        );
      }
    } catch (_) {
      await prefs.remove(_key);
    }
    // Versions before the pasted list: whatever the stored account did not bring was pasted.
    if (!prefs.containsKey(shikooPastedKey)) {
      await markPasted([
        for (final profile in _ref.read(profilesProvider))
          if (!(stored?.brought.contains(profile.id) ?? false)) profile.id,
      ]);
    }
    if (stored == null) return;
    _token = stored.token;
    _setAccount(stored.account);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _token;
    if (token == null) {
      await prefs.remove(_key);
      return;
    }
    final account = _account;
    await prefs.setString(
      _key,
      jsonEncode({
        'token': token,
        'name': account.who?.name,
        'username': account.who?.username,
        'bot': account.bot,
        'services': [
          for (final s in account.services)
            {
              'id': s.id,
              'title': s.title,
              'status': s.status,
              'profileId': s.profileId,
              'expiresAt': s.expiresAt?.toIso8601String(),
            },
        ],
      }),
    );
  }

  /// A code that stays until approved, refused or expired; its bot link, for the phone to open.
  Future<String?> start() async {
    final attempt = ++_attempt;
    _login(const ShikooLogin(LoginPhase.starting));
    try {
      final code = await _ref
          .read(shikooDeviceProvider)()
          .then((device) => _api.start(deviceName: device.name, tv: device.tv))
          .timeout(startLimit);
      if (attempt != _attempt) return null;
      _login(
        ShikooLogin(LoginPhase.waiting, code: code.code, botUrl: code.botUrl),
      );
      unawaited(_poll(attempt, code, DateTime.now().add(code.lifetime)));
      return code.botUrl;
    } catch (error) {
      if (attempt == _attempt) {
        _login(
          ShikooLogin(
            LoginPhase.startFailed,
            clock: error is ShikooApiFailure && error.clock,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _poll(int attempt, LoginCode code, DateTime deadline) async {
    void end(LoginPhase phase) =>
        _login(ShikooLogin(phase, code: code.code, botUrl: code.botUrl));
    while (true) {
      await Future<void>.delayed(pollEvery);
      if (attempt != _attempt) return;
      if (!foreground) continue;
      if (!DateTime.now().isBefore(deadline)) {
        end(LoginPhase.expired);
        return;
      }
      final PollAnswer answer;
      try {
        answer = await _api.poll(code.code, code.secret);
      } catch (_) {
        continue;
      }
      if (attempt != _attempt) return;
      switch (answer.status) {
        case PollStatus.waiting:
          continue;
        case PollStatus.approved:
          await _approved(answer.token!, answer.account);
        case PollStatus.refused:
          end(LoginPhase.rejected);
        case PollStatus.expired || PollStatus.unknown:
          end(LoginPhase.expired);
        // A server that gives no reason with its 410: the clock tells a refusal from the end.
        case PollStatus.gone:
          end(
            DateTime.now().isBefore(deadline.subtract(pollEvery))
                ? LoginPhase.rejected
                : LoginPhase.expired,
          );
      }
      return;
    }
  }

  Future<void> _approved(String token, TelegramAccount? who) async {
    // Without the list, the next start would read this account as an older version's.
    await markPasted(const []);
    _token = token;
    _setAccount(ShikooAccount(who: who ?? const TelegramAccount()));
    await _save();
    await retry();
  }

  Future<void> retry() async {
    final attempt = _attempt;
    _login(ShikooLogin(LoginPhase.syncing, account: _account.who));
    final synced = await sync();
    if (attempt != _attempt) return;
    final account = _account;
    _login(switch (synced) {
      null => null,
      false => ShikooLogin(
        LoginPhase.servicesFailed,
        account: account.who,
        clock: _servicesClock,
      ),
      true when account.services.isEmpty => ShikooLogin(
        LoginPhase.noService,
        account: account.who,
      ),
      true => ShikooLogin(
        LoginPhase.approved,
        account: account.who,
        services: [for (final s in account.services) s.title],
      ),
    });
  }

  void finish() {
    _attempt++;
    _login(null);
  }

  Future<void> notMine() async {
    _attempt++;
    final token = _token;
    final named = [for (final s in _account.services) ?s.profileId];
    _token = null;
    _setAccount(const ShikooAccount());
    _login(null);
    await _save();
    if (token != null) unawaited(_logout(token));
    for (final profile in [..._ref.read(profilesProvider)]) {
      await _drop(profile.id);
    }
    for (final id in named) {
      if (_existing(id) != null) {
        unawaited(_ref.read(shikooControllerProvider).renameFromPanel(id));
      }
    }
  }

  Future<void> signOut() async {
    final controller = _ref.read(shikooControllerProvider);
    if (_token == null) {
      _attempt++;
      _login(null);
      return controller.forgetServices();
    }
    await controller.disconnect();
    await notMine();
  }

  /// Offline, the device stays in the bot's list until the customer removes it there.
  Future<void> _logout(String token) async {
    try {
      await _api.logout(token);
    } catch (_) {}
  }

  /// Back from the bot, a service without a link is asked about again at once.
  void onForeground() {
    if (_token != null &&
        (isDue(_lastSync, DateTime.now(), refreshEvery) ||
            _account.withoutLink.isNotEmpty)) {
      unawaited(sync());
    }
  }

  /// Makes this device hold the account's services. True once done, false when the list did
  /// not come or no service could be added, null when the token stopped working.
  /// A new account's sync waits for the old one to take back what it brought.
  Future<bool?> sync() {
    final token = _token;
    if (_syncing case (final owner, final running) when owner == token) {
      return running;
    }
    final previous = _syncing?.$2;
    late final Future<bool?> run;
    run = Future(() async {
      try {
        await previous;
      } catch (_) {}
      try {
        return await _sync();
      } finally {
        if (identical(_syncing?.$2, run)) _syncing = null;
      }
    });
    _syncing = (token, run);
    return run;
  }

  Future<bool?> _sync() async {
    final token = _token;
    if (token == null) return true;
    _lastSync = DateTime.now();
    final ({String? bot, List<AccountServiceRow> services})? answer;
    try {
      answer = await _api.services(token);
      _servicesClock = false;
    } catch (error) {
      _servicesClock = error is ShikooApiFailure && error.clock;
      return false;
    }
    if (token != _token) return null;
    if (answer == null) {
      await notMine();
      return null;
    }
    final before = {for (final s in _account.services) s.id: s};
    final kept = <LinkedService>[];
    var failed = false;
    for (final row in answer.services) {
      if (token != _token) return null;
      final was = before.remove(row.id);
      var profileId = _existing(was?.profileId);
      final url = row.subUrl == null ? null : shikooLink(row.subUrl!);
      if (url != null && _urlOf(profileId) != url) {
        final added = await _add(url, row.label);
        if (token != _token) {
          await _drop(added);
          return null;
        }
        if (added == null) {
          failed = true;
        } else {
          if (profileId != added) await _drop(profileId);
          profileId = added;
        }
      } else if (url == null && !_keepsLink.contains(row.status)) {
        await _drop(profileId);
        if (!LinkedService.finishedStatuses.contains(row.status)) continue;
        profileId = null;
      }
      if (profileId != null || url == null) {
        kept.add(
          LinkedService(
            id: row.id,
            title: row.label,
            status: row.status,
            profileId: profileId,
            expiresAt: row.expiresAt,
          ),
        );
      }
    }
    for (final gone in before.values) {
      await _drop(gone.profileId);
    }
    if (token != _token) return null;
    _setAccount(
      ShikooAccount(
        who: _account.who,
        bot: answer.bot ?? _account.bot,
        services: kept,
      ),
    );
    await _save();
    return !(failed && kept.isEmpty);
  }

  int? _existing(int? profileId) =>
      _ref.read(profilesProvider).any((p) => p.id == profileId)
      ? profileId
      : null;

  String? _urlOf(int? profileId) => switch (_ref
      .read(profilesProvider)
      .firstWhereOrNull((p) => p.id == profileId)) {
    final profile? => normalLink(profile.url),
    null => null,
  };

  int? _profileOf(String url) => _ref
      .read(profilesProvider)
      .firstWhereOrNull((p) => normalLink(p.url) == url)
      ?.id;

  Future<int?> _add(String url, String label) async {
    final failure = await _ref
        .read(shikooControllerProvider)
        .addService(url, label, false);
    return failure == null ? _profileOf(url) : null;
  }

  Future<void> _drop(int? profileId) async {
    final pasted = await pastedProfiles();
    if (_existing(profileId) case final id? when !pasted.contains(id)) {
      await _ref.read(profilesActionProvider.notifier).deleteProfile(id);
    }
  }
}
