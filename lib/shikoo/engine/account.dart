import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, HttpClient, HttpHeaders, InternetAddress;

import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/direct_dns.dart';
import 'package:fl_clash/shikoo/engine/order.dart';
import 'package:fl_clash/shikoo/engine/paste.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/warp.dart';
import 'package:flutter/foundation.dart' hide mergeSort;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show join;
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
  choosing,
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
    this.choices = const [],
    this.clock = false,
  });

  final LoginPhase phase;

  final String? code;
  final String? botUrl;
  final TelegramAccount? account;
  final List<String> services;
  final List<LinkedService> choices;
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
    this.loadFailed = false,
    this.renewable,
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

  /// The panel gave a link whose servers did not load: the bot cannot help, a retry can.
  final bool loadFailed;

  /// The door's answer by the bot's own renewal rule; null from a door older than it.
  final bool? renewable;

  bool get botRenews => renewable != false;

  bool get finished => finishedStatuses.contains(status);

  /// The bot renews a disabled service but not a removed one, and a failed one never ran.
  bool get renews =>
      botRenews && const {'expired', 'exhausted', 'disabled'}.contains(status);

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
  const ShikooAccount({
    this.who,
    this.bot,
    this.services = const [],
    this.total = 0,
  });

  /// Signed in when not null.
  final TelegramAccount? who;
  final String? bot;
  final List<LinkedService> services;

  /// The account's services at the last sync, with those left off this device at sign-in.
  final int total;

  List<LinkedService> get withoutLink => [
    for (final service in services)
      if (service.profileId == null) service,
  ];

  LinkedService? _linked(int? profileId) => profileId == null
      ? null
      : services.firstWhereOrNull((s) => s.profileId == profileId);

  int? serviceOf(int? profileId) => _linked(profileId)?.id;

  bool renewsOn(int? profileId) => _linked(profileId)?.botRenews ?? true;
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
String deviceName(String manufacturer, String model, {required String kind}) {
  final full = model.toLowerCase().startsWith(manufacturer.toLowerCase())
      ? model
      : '$manufacturer $model';
  final name = full.replaceAll(_notAllowed, ' ').replaceAll(RegExp(' +'), ' ');
  final cut = (name.length > 40 ? name.substring(0, 40) : name).trim();
  return cut.isNotEmpty ? cut : _unnamed[kind]!;
}

const _unnamed = {
  'phone': 'Android phone',
  'tv': 'Android TV',
  'desktop': 'Windows PC',
};

final shikooDeviceProvider =
    Provider<Future<({String name, String kind})> Function()>(
      (_) => () async {
        if (system.isWindows) {
          final info = await DeviceInfoPlugin().windowsInfo;
          return (
            name: deviceName('', info.computerName, kind: 'desktop'),
            kind: 'desktop',
          );
        }
        final info = await DeviceInfoPlugin().androidInfo;
        final kind = system.isTV ? 'tv' : 'phone';
        return (
          name: deviceName(info.manufacturer, info.model, kind: kind),
          kind: kind,
        );
      },
    );

class ShikooApiFailure implements Exception {
  const ShikooApiFailure({this.clock = false, this.status});

  final bool clock;

  /// The door answered, and refused; null when it was not reached.
  final int? status;
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
      },
      renewable = switch (json['renewable']) {
        final bool renewable => renewable,
        _ => null,
      };

  final int id;
  final String title;
  final String? location;
  final String status;
  final String? subUrl;
  final DateTime? expiresAt;
  final bool? renewable;

  String get label => location == null ? title : '$title · $location';
}

/// One ABI's build at the app door (`appRelease.ts`).
@immutable
class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.minVersionCode,
    required this.size,
    required this.sha256,
    required this.url,
    this.sig,
  });

  final String versionName;
  final int versionCode;

  final int minVersionCode;
  final int size;

  final String sha256;
  final String url;

  /// Base64 RSA PKCS#1 v1.5 over SHA-256 by the Android signing key; Windows installs only what it signed.
  final String? sig;
}

final _sha256 = RegExp(r'^[0-9a-f]{64}$');

class ShikooApi {
  ShikooApi(this.bases, [Dio? dio, this.bridge])
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

  /// The WARP bridge's `PROXY …` for HttpClient, tried once no address answered; null while it is off.
  final Future<String?> Function()? bridge;

  /// The address that answered last goes first; the next is the backup for a blocked one.
  int _first = 0;

  Future<Response<Object?>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
    Duration? sendTimeout,
  }) async {
    final name = path.split('/').where((part) => part.isNotEmpty).join('-');
    (DioException, String)? failed;
    Future<Response<Object?>?> each(Dio dio) async {
      for (var i = 0; i < bases.length; i++) {
        final at = (_first + i) % bases.length;
        try {
          final response = await dio.request<Object?>(
            '${bases[at]}/api/v1/app$path',
            data: body,
            options: Options(
              method: method,
              sendTimeout: sendTimeout,
              headers: {
                if (token != null)
                  HttpHeaders.authorizationHeader: 'Bearer $token',
              },
            ),
          );
          _first = at;
          learnClock(response.headers.value(HttpHeaders.dateHeader));
          if ((response.statusCode ?? 0) >= 400) {
            shikooDiag.add('T', 'door $name http ${response.statusCode}');
          }
          return response;
        } on DioException catch (error) {
          failed = (error, bases[at]);
        }
      }
      return null;
    }

    if (await each(_dio) case final response?) return response;
    if (await bridge?.call() case final proxy?) {
      final bridged = Dio(_dio.options)
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpClient()..findProxy = (_) => proxy,
        );
      try {
        if (await each(bridged) case final response?) return response;
      } finally {
        bridged.close(force: true);
      }
    }
    final last = failed;
    final clock = last != null && await clockFailed(last.$1, last.$2);
    shikooDiag.add(
      'T',
      'door $name ${clock ? 'clock' : failureKind(last?.$1)}',
    );
    throw ShikooApiFailure(clock: clock);
  }

  static Map<String, dynamic>? _json(Response<Object?> response) =>
      switch (response.data) {
        final Map<String, dynamic> body => body,
        _ => null,
      };

  Future<LoginCode> start({
    required String deviceName,
    required String kind,
  }) async {
    final response = await _call(
      'POST',
      '/login/start',
      body: {'device_name': deviceName, 'device_kind': kind},
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

  /// `POST /report` (shikoo-platform's `appReport.ts`); a 1.4 MB body gets its own minute.
  Future<({String code, bool linked})> report(
    Map<String, Object?> body, {
    String? token,
  }) async {
    final response = await _call(
      'POST',
      '/report',
      body: body,
      token: token,
      sendTimeout: const Duration(seconds: 60),
    );
    if (_json(response) case {
      'code': final String code,
      'linked': final bool linked,
    } when response.statusCode == 200) {
      return (code: code, linked: linked);
    }
    throw ShikooApiFailure(status: response.statusCode);
  }

  Future<void> logout(String token) async {
    await _call('POST', '/logout', token: token);
  }

  /// Null before the first release, for another ABI, and for a file anywhere but the door that
  /// answered: its sha256 vouches only for that door's file.
  Future<AppRelease?> update(String abi) async {
    final response = await _call('GET', '/update');
    if (response.statusCode == 404) return null;
    final body = _json(response);
    if (response.statusCode != 200 || body == null) {
      throw const ShikooApiFailure();
    }
    final apk = (body['apks'] as Map?)?[abi];
    if (apk == null) return null;
    if (apk case {
      'version_code': final int code,
      'size': final int size,
      'sha256': final String sha256,
      'url': final String url,
    } when size > 0 && _sha256.hasMatch(sha256)) {
      final door = response.requestOptions.uri;
      final at = door.resolve(url);
      if (at.scheme != door.scheme ||
          at.host != door.host ||
          at.port != door.port) {
        return null;
      }
      return AppRelease(
        versionName:
            apk['version_name'] as String? ??
            body['version_name'] as String? ??
            '',
        versionCode: code,
        minVersionCode: apk['min_version_code'] as int? ?? 0,
        size: size,
        sha256: sha256,
        url: '$at',
        sig: apk['sig'] as String?,
      );
    }
    throw const ShikooApiFailure();
  }

  Future<Response<ResponseBody>> download(
    String url,
    int from,
    CancelToken cancel,
  ) => _dio.get<ResponseBody>(
    url,
    cancelToken: cancel,
    options: Options(
      responseType: ResponseType.stream,
      headers: {
        // Ranges count stored bytes; HttpClient would ask for gzip and unpack it.
        HttpHeaders.acceptEncodingHeader: 'identity',
        if (from > 0) HttpHeaders.rangeHeader: 'bytes=$from-',
      },
    ),
  );
}

final shikooApiProvider = Provider<ShikooApi>(
  (ref) => ShikooApi(shikooApiBases, null, () => warpProxy(ref.read)),
);

Rule apiDirectRule(String base, int id) {
  final host = Uri.parse(base).host;
  return Rule.parse(
    InternetAddress.tryParse(host) == null
        ? 'DOMAIN,$host,DIRECT'
        : 'IP-CIDR,$host/32,DIRECT,no-resolve',
    id: id,
  );
}

/// The door, and the internet check's sites, so the check answers alike with the VPN on.
Future<void> keepApiDirect() async {
  for (final (i, base) in shikooApiBases.indexed) {
    await database.rulesDao.putGlobalRule(
      apiDirectRule(base, shikooDirectIds + i),
    );
  }
  for (final (i, url) in [...domesticProbes, internationalProbe].indexed) {
    await database.rulesDao.putGlobalRule(
      apiDirectRule(url, shikooDirectIds + 100 + i),
    );
  }
}

/// Banks and payment gateways refuse a foreign address. One transaction a call: quick turns land in order.
Future<void> keepIranDirect(bool on) => database.transaction(() async {
  if (!on) return database.rulesDao.delRules(iranDirectRules.map((r) => r.id));
  for (final rule in iranDirectRules) {
    await database.rulesDao.putGlobalRule(rule);
  }
});

/// Left alone when unchanged: a tunnel still up from the last run may be reading them.
/// A failed write only sends Iranian sites through the server; the app still starts.
Future<void> writeRuleSets(String home) async {
  try {
    for (final name in shikooRuleSets.keys) {
      final asset = await rootBundle.load('assets/data/$name.mrs');
      final bytes = asset.buffer.asUint8List();
      final file = File(join(home, '$name.mrs'));
      if (await file.exists() && listEquals(await file.readAsBytes(), bytes)) {
        continue;
      }
      await file.writeAsBytes(bytes, flush: true);
    }
  } catch (e) {
    commonPrint.log('rule sets not written: $e', logLevel: LogLevel.warning);
  }
}

// shortcut: later hosts get no rule; raise it if an account can hold that many.
const _subscriptionHosts = 500;

Future<bool> keepSubscriptionsDirect(Iterable<String> urls) {
  final hosts = {
    for (final url in urls)
      if (Uri.tryParse(url)?.host case final host? when host.isNotEmpty) host,
  }.sorted().take(_subscriptionHosts);
  final want = {
    for (final (i, host) in hosts.indexed)
      subscriptionDirectIds + i: subscriptionDirectRule(
        host,
        subscriptionDirectIds + i,
      ).rawValue,
  };
  return database.transaction(() async {
    final have = {
      for (final rule in await database.rulesDao.queryGlobalAddedRules().get())
        if (rule.id >= subscriptionDirectIds &&
            rule.id < subscriptionDirectIds + _subscriptionHosts)
          rule.id: rule.rawValue,
    };
    if (const MapEquality<int, String>().equals(have, want)) return false;
    await database.rulesDao.delRules(have.keys);
    for (final MapEntry(:key, :value) in want.entries) {
      await database.rulesDao.putGlobalRule(Rule.parse(value, id: key));
    }
    return true;
  });
}

/// While connected, a change of services reaches the core before the next update needs it.
Future<void> followSubscriptions(ProviderContainer container) async {
  Future<void> follow(Iterable<Profile> profiles) async {
    if (await keepSubscriptionsDirect(profiles.map((p) => p.url)) &&
        container.read(isStartProvider)) {
      await container
          .read(setupActionProvider.notifier)
          .applyProfile(silence: true);
    }
  }

  await follow(await database.profilesDao.query().get());
  container.listen(
    profilesProvider,
    (_, profiles) => unawaited(follow(profiles)),
  );
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

  @visibleForTesting
  Duration botWindow = const Duration(minutes: 30);
  DateTime? _botOpened;
  String? _token;
  LoginCode? _live;
  bool _servicesClock = false;

  /// The checklist's pick; null, as for a sign-in before it, is every service, later ones too.
  Set<int>? _chosen;
  bool _choosing = false;
  List<LinkedService> _offer = const [];

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
    ({
      String token,
      ShikooAccount account,
      Set<int?> brought,
      Set<int>? chosen,
      bool choosing,
    })?
    stored;
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
                  loadFailed: s['loadFailed'] == true,
                  renewable: switch (s['renewable']) {
                    final bool renewable => renewable,
                    _ => null,
                  },
                ),
            ],
            total: json['total'] as int? ?? 0,
          ),
          brought: {
            for (final s in services)
              if (s['owned'] != false) s['profileId'] as int?,
          },
          chosen: switch (json['chosen']) {
            final List<Object?> ids => {for (final id in ids) id! as int},
            _ => null,
          },
          choosing: json['choosing'] == true,
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
    _chosen = stored.chosen;
    _choosing = stored.choosing;
    _setAccount(stored.account);
    if (_choosing) unawaited(retry());
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
              'loadFailed': s.loadFailed,
              'renewable': s.renewable,
            },
        ],
        'total': account.total,
        if (_chosen case final chosen?) 'chosen': [...chosen],
        if (_choosing) 'choosing': true,
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
          .then(
            (device) => _api.start(deviceName: device.name, kind: device.kind),
          )
          .timeout(startLimit);
      _live = code;
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
    _chosen = null;
    _choosing = true;
    _setAccount(ShikooAccount(who: who ?? const TelegramAccount()));
    await _save();
    await retry();
  }

  Future<void> choose(Set<int> ids) async {
    _chosen = ids;
    _choosing = false;
    await _save();
    await retry(home: true);
  }

  Future<void> retry({bool home = false}) async {
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
      true when _choosing => ShikooLogin(
        LoginPhase.choosing,
        account: account.who,
        choices: _offer,
      ),
      true when account.services.isEmpty => ShikooLogin(
        LoginPhase.noService,
        account: account.who,
      ),
      true when home => null,
      true => ShikooLogin(
        LoginPhase.approved,
        account: account.who,
        services: [for (final s in account.services) s.title],
      ),
    });
  }

  Iterable<String> get secrets => [?_token, ?_live?.code, ?_live?.secret];

  Future<({String code, bool linked})> report(Map<String, Object?> body) =>
      _api.report(body, token: _token);

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
    // The order leaves with the account it arranged; pasted cards that stay go back to arrival order.
    await _ref.read(savedOrderProvider.notifier).save(const []);
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

  /// Back from the bot, a service to renew or without a link is asked about again at once.
  void onForeground() {
    if (_token != null &&
        (_unsettled || isDue(_lastSync, DateTime.now(), refreshEvery))) {
      unawaited(sync());
    }
  }

  /// A TV stays on screen while its QR is paid for on the phone.
  void onMinute() {
    if (_token != null &&
        _unsettled &&
        !isDue(_botOpened, DateTime.now(), botWindow)) {
      unawaited(sync());
    }
  }

  void botOpened() => _botOpened = DateTime.now();

  bool get _unsettled => _account.services.any(
    (s) => s.renews || s.profileId == null || _ended(s.profileId),
  );

  bool _ended(int? profileId) =>
      switch (_ref.read(profilesProvider).getProfile(profileId)) {
        final profile? => profileFinished(profile),
        null => false,
      };

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
    final listed = [
      for (final row in answer.services)
        if (_linkOf(row) != null ||
            _keepsLink.contains(row.status) ||
            LinkedService.finishedStatuses.contains(row.status))
          row,
    ];
    if (_choosing) {
      if (listed.length > 1) {
        _offer = [
          for (final row in listed)
            LinkedService(id: row.id, title: row.label, status: row.status),
        ];
        return true;
      }
      _choosing = false;
      // An account with none keeps nothing fixed: the service it buys next is its first.
      if (listed case [final only]) _chosen = {only.id};
    }
    final chosen = _chosen;
    final before = {for (final s in _account.services) s.id: s};
    final kept = <LinkedService>[];
    final renewed = <int>{};
    var failed = false;
    var unloaded = 0;
    for (final row in listed) {
      if (token != _token) return null;
      if (chosen != null && !chosen.contains(row.id)) continue;
      final was = before.remove(row.id);
      var profileId = _existing(was?.profileId);
      var loadFailed = false;
      var status = row.status;
      final url = _linkOf(row);
      if (url != null && _urlOf(profileId) != url) {
        final (added, failure) = await _add(url, row.label);
        if (token != _token) {
          await _drop(added);
          return null;
        }
        if (added == null) {
          failed = true;
          final ended = switch (failure) {
            ShikooPasteError.expired => 'expired',
            ShikooPasteError.exhausted => 'exhausted',
            _ => null,
          };
          // shortcut: the server's date stays, so its row may read «امروز تمام شد»; carry the panel's expire if seen.
          status = ended ?? status;
          loadFailed = profileId == null && ended == null;
          if (loadFailed) unloaded++;
        } else {
          if (profileId != added) await _drop(profileId);
          profileId = added;
        }
      } else if (url == null && !_keepsLink.contains(row.status)) {
        await _drop(profileId);
        profileId = null;
      } else if (url != null && _ended(profileId)) {
        renewed.add(profileId!);
      }
      kept.add(
        LinkedService(
          id: row.id,
          title: row.label,
          status: status,
          profileId: profileId,
          expiresAt: row.expiresAt,
          loadFailed: loadFailed,
          renewable: row.renewable,
        ),
      );
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
        total: listed.length,
      ),
    );
    await _save();
    if (renewed.isNotEmpty) {
      unawaited(
        _ref.read(shikooControllerProvider).refreshDue(renewed: renewed),
      );
    }
    return !(failed && kept.length == unloaded);
  }

  static String? _linkOf(AccountServiceRow row) =>
      row.subUrl == null ? null : shikooLink(row.subUrl!);

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

  Future<(int?, ShikooPasteError?)> _add(String url, String label) async {
    final failure = await _ref
        .read(shikooControllerProvider)
        .addService(url, label, false);
    return (failure == null ? _profileOf(url) : null, failure);
  }

  Future<void> _drop(int? profileId) async {
    final pasted = await pastedProfiles();
    if (_existing(profileId) case final id? when !pasted.contains(id)) {
      await _ref.read(profilesActionProvider.notifier).deleteProfile(id);
    }
  }
}
