import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/boot_record.dart' show AppExitReason;
import 'package:fl_clash/common/constant.dart'
    show appHelperService, shikooStagingBuild;
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/core/desktop/helper_client.dart'
    show HelperReadiness, helperClient;
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:win32_registry/win32_registry.dart'
    show CURRENT_USER, LOCAL_MACHINE;

/// docs/app-diagnostics.md: a clean record kept on the device, sent to the door only when the
/// customer taps. The door's side of the report is shikoo-platform's `appReport.ts`.

const _bullet = '·';

final _space = RegExp(r'\s+');
final _goFile = RegExp(r'^\w[\w.-]*\.go:\d+$');

/// The doc's three link shapes (`\S*://\S*`, `\S*%[0-9a-f]{2}\S*`, `host/path`), found inside a
/// word without a leading `\S*`, which made a long word without spaces cost quadratic time.
final _linkShape = RegExp(
  r'://|%[0-9a-f]{2}|[\p{L}\p{Nd}]\.\p{L}{2,}(?::\d+)?/',
  caseSensitive: false,
  unicode: true,
);
final _gaps = RegExp(r'[\s(),=]+');
const _lead = '[({<"\'';
const _trail = '])}>"\':;,.!?،؛؟';
const _atom =
    r'(?:\p{L}[\p{L}\p{M}\u200c]{0,23}|\p{Nd}{1,6}(?:ms|s|%|x)?|[\p{L}\p{Nd}]{1,6})';
final _kept = RegExp(
  '^(?:$_atom(?:-$_atom){0,2}'
  r'|[-=<>|]+|#\p{Nd}{1,6}'
  r'|[A-Z]{1,24}(?:_[A-Z]{1,24}){1,4}'
  r'|(?:[a-z][a-z0-9_]*\.)+_?[A-Z][A-Za-z_$]{0,39}(?:\.<?[A-Za-z_$]{1,40}>?){0,3}'
  r'|_?[A-Z][A-Za-z_$]{0,39}(?:\.<?[A-Za-z_$]{1,40}>?){1,3}'
  r'|package:\w+(?:/\w+)*\.dart:\d+(?::\d+)?'
  r'|dart:[a-z_]+(?:/\w+\.dart)?(?::\d+){0,2}'
  r'|\w+\.(?:dart|kt|java|go):\d+(?::\d+)?)$',
  unicode: true,
);

/// Each secret of 4+ characters anywhere, longest first, and [words] only as whole words.
RegExp? _knownPattern(
  Iterable<String> values, [
  Iterable<String> words = const [],
]) {
  const edge = r'[\p{L}\p{N}\p{M}_\u200c]';
  List<String> longestFirst(Iterable<String> items) =>
      items.sorted((a, b) => b.length - a.length);
  final parts = [
    ...longestFirst({
      for (final value in values)
        if (value.length >= 4) value,
    }).map(RegExp.escape),
    for (final word in longestFirst(words))
      '(?<!$edge)${RegExp.escape(word)}(?!$edge)',
  ];
  return parts.isEmpty
      ? null
      : RegExp(parts.join('|'), caseSensitive: false, unicode: true);
}

/// The Windows user, its profile folder (a renamed account keeps the old one) and the PC's names.
Set<String> windowsNames(Map<String, String> env, String host) => {
  for (final raw in [
    env['USERNAME'],
    env['COMPUTERNAME'],
    host,
    env['USERPROFILE']?.split(RegExp(r'[\\/]')).last,
  ])
    if (raw?.trim() case final name? when name.isNotEmpty) name,
};

String reportAbi(Abi abi) => '$abi'.replaceFirst('windows_', 'windows-');

/// Another app's proxy is only `other`: its address never leaves the PC.
List<String> windowsLines({
  required int? proxyEnable,
  required String? proxyServer,
  required String? pac,
  required int port,
  required bool installed,
  required bool running,
}) {
  final on = proxyEnable == 1;
  final proxy = on && proxyServer == '127.0.0.1:$port'
      ? 'ours'
      : on || (pac ?? '').isNotEmpty
      ? 'other'
      : 'off';
  final helper = running
      ? 'running'
      : installed
      ? 'installed'
      : 'missing';
  return ['windows proxy $proxy', 'helper service $helper'];
}

/// What the helper registers as with Windows; its file is [appHelperService] in both builds.
const helperServiceName = shikooStagingBuild
    ? 'ShikooNetTestHelperService'
    : appHelperService;

Future<List<String>> _readWindows(ProviderContainer container) async {
  var installed = true;
  try {
    LOCAL_MACHINE
        .open(r'SYSTEM\CurrentControlSet\Services\' + helperServiceName)
        .close();
  } catch (_) {
    installed = false;
  }
  final running =
      await helperClient.readiness(
        timeout: const Duration(seconds: 2),
        logFailure: false,
      ) ==
      HelperReadiness.ready;
  final internet = CURRENT_USER.open(
    r'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
  );
  try {
    return windowsLines(
      proxyEnable: internet.getInt('ProxyEnable'),
      proxyServer: internet.getString('ProxyServer'),
      pac: internet.getString('AutoConfigURL'),
      port: container.read(patchClashConfigProvider).mixedPort,
      installed: installed,
      running: running,
    );
  } finally {
    internet.close();
  }
}

String _eachWord(String text, String Function(String word) clean) =>
    text.splitMapJoin(_space, onMatch: (m) => m[0]!, onNonMatch: clean);

/// A whole word goes, before any finer split, so a `,` or `)` inside a link leaves no tail.
String _unlinked(String text) =>
    _eachWord(text, (word) => _linkShape.hasMatch(word) ? _bullet : word);

String _goFrame(String word) {
  final file = word.substring(word.lastIndexOf('/') + 1);
  return _goFile.hasMatch(file) ? file : word;
}

/// Steps 1 to 5 of the doc's allowlist sanitizer: a word, number, code name or code place stays,
/// anything else becomes `·`.
String cleanLine(String line, RegExp? known, {bool go = false}) {
  var text = go ? _eachWord(line, _goFrame) : line;
  if (known != null) text = text.replaceAll(known, _bullet);
  return _unlinked(
    text,
  ).splitMapJoin(_gaps, onMatch: (m) => m[0]!, onNonMatch: _cleanToken);
}

String _cleanToken(String token) {
  var start = 0;
  var end = token.length;
  while (start < end && _lead.contains(token[start])) {
    start++;
  }
  while (end > start && _trail.contains(token[end - 1])) {
    end--;
  }
  final core = token.substring(start, end);
  if (core.isEmpty || _kept.hasMatch(core)) return token;
  return '${token.substring(0, start)}$_bullet${token.substring(end)}';
}

String _cut(String text, int? max) =>
    max == null || text.length <= max ? text : text.substring(0, max);

/// What a refresh or a door call ended with, as the report and the timeline name it.
String failureKind(Object? error) => switch (error) {
  DioException(type: DioExceptionType.badResponse, :final response) =>
    'http_${response?.statusCode}',
  DioException(
    type: DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout,
  ) ||
  TimeoutException() => 'timeout',
  DioException(type: DioExceptionType.badCertificate) ||
  DioException(error: TlsException()) ||
  TlsException() => 'tls',
  DioException(error: SocketException(:final message))
      when message.contains('host lookup') =>
    'dns',
  // A connection that broke or answered no HTTP, whatever the reason Dart gives.
  DioException() => 'tcp',
  ShikooApiFailure(clock: true) => 'clock',
  _ => 'failed',
};

typedef Probe = ({String result, int ms});
typedef ProbeChecks = ({Probe domestic, Probe international, Probe door});

const probeLimit = Duration(seconds: 5);

/// Plain http, so a wrong clock fails neither; any answer from an Iranian site counts.
const domesticProbes = ['http://www.aparat.com/', 'http://www.digikala.com/'];
const internationalProbe = 'http://connectivitycheck.gstatic.com/generate_204';

/// Direct, but for [proxy] ([ownerAside]): through FlClash's local proxy its own 502 is no Iranian site's answer.
Future<ProbeChecks> runProbes({
  List<String> domestic = domesticProbes,
  String international = internationalProbe,
  List<String> doors = shikooApiBases,
  Duration limit = probeLimit,
  String? proxy,
}) async {
  final dio =
      Dio(BaseOptions(followRedirects: false, validateStatus: (_) => true))
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () =>
              HttpClient()..findProxy = (_) => proxy ?? 'DIRECT',
        );
  Future<Probe> one(String url, {String method = 'GET', int? want}) async {
    final watch = Stopwatch()..start();
    String result;
    try {
      final response = await dio
          .request<void>(url, options: Options(method: method))
          .timeout(limit);
      final code = response.statusCode;
      final proxyFailed = proxy != null && code == HttpStatus.badGateway;
      result = !proxyFailed && (want == null || code == want)
          ? 'ok'
          : 'http_$code';
    } catch (error) {
      result = failureKind(error);
    }
    return (result: result, ms: watch.elapsedMilliseconds);
  }

  Future<Probe> first(
    List<String> urls,
    Future<Probe> Function(String) probe,
  ) async {
    final watch = Stopwatch()..start();
    var result = 'tcp';
    for (final url in urls) {
      result = (await probe(url)).result;
      if (result == 'ok') break;
    }
    return (result: result, ms: watch.elapsedMilliseconds);
  }

  try {
    final (home, abroad, door) = await (
      first(domestic, (url) => one(url, method: 'HEAD')),
      one(international, want: HttpStatus.noContent),
      first(doors, (base) => one('$base/health', want: HttpStatus.ok)),
    ).wait;
    String said(Probe p) => '${p.result.replaceAll('_', ' ')} ${p.ms}ms';
    shikooDiag.add(
      'T',
      'probe domestic ${said(home)}, international ${said(abroad)}, '
          'door ${said(door)}',
    );
    return (domestic: home, international: abroad, door: door);
  } finally {
    dio.close(force: true);
  }
}

Map<String, Object?> _checksOf(ProbeChecks checks) => {
  for (final (name, probe) in [
    ('domestic', checks.domestic),
    ('international', checks.international),
    ('door', checks.door),
  ])
    name: {'result': probe.result, 'ms': probe.ms},
};

enum ProbeReading { checking, ok, offline, noAbroad, noDoor, noServer }

ProbeReading readProbes(ProbeChecks? checks, List<ShikooServer> servers) {
  if (checks == null) return ProbeReading.checking;
  bool ok(Probe probe) => probe.result == 'ok';
  if (!ok(checks.door)) {
    return ok(checks.domestic) || ok(checks.international)
        ? ProbeReading.noDoor
        : ProbeReading.offline;
  }
  if (!ok(checks.international)) return ProbeReading.noAbroad;
  if (servers.isNotEmpty && servers.every((server) => server.ping == -1)) {
    return ProbeReading.noServer;
  }
  return ProbeReading.ok;
}

/// The card after a failed connect: null without one, loading while the probes run.
class ShikooProbes extends Notifier<AsyncValue<ProbeChecks>?> {
  ShikooProbes([this._probe = runProbes]);

  final Future<ProbeChecks> Function() _probe;
  int _round = 0;

  /// Microtasks: Riverpod forbids writing a provider while another is being built.
  @override
  AsyncValue<ProbeChecks>? build() {
    ref.listen(shikooStateProvider.select((s) => (s.connection, s.lastError)), (
      _,
      now,
    ) {
      switch (now) {
        case (ShikooConnection.connecting, _):
          _round++;
          scheduleMicrotask(() => state = null);
        case (
          ShikooConnection.error,
          ShikooError.connectTimeout || ShikooError.noServer,
        ):
          scheduleMicrotask(() => unawaited(run()));
        default:
      }
    });
    return null;
  }

  /// The same probes, the card left alone: Diagnostics shows its own.
  Future<ProbeChecks> probe() => _probe();

  Future<void> run() async {
    final round = ++_round;
    state = const AsyncLoading();
    final checks = await _probe();
    if (round == _round) state = AsyncData(checks);
  }
}

final shikooProbeProvider =
    NotifierProvider<ShikooProbes, AsyncValue<ProbeChecks>?>(ShikooProbes.new);

Future<void> openNetworkSettings({
  bool? windows,
  Future<bool> Function(Uri) launch = launchUrl,
}) async {
  if (windows ?? Platform.isWindows) {
    await launch(Uri.parse('ms-settings:network-status'));
    return;
  }
  await ShikooDiag._invoke<bool>('netSettings');
}

String _backendOf(String? rendererLine) =>
    switch (rendererLine?.toLowerCase()) {
      final line? when line.contains('vulkan') => 'vulkan',
      final line? when line.contains('opengles') => 'opengles',
      _ => 'unknown',
    };

final _usernameShape = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

String? frameSummary(int frames, int slow, int build, int raster) => slow == 0
    ? null
    : 'frames $frames slow $slow build ${build}ms raster ${raster}ms';

String _reasonName(Object? code) => AppExitReason.fromCode(
  code,
).name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();

/// The door's limits (`appReport.ts`).
const _reportBytes = 1468006;
const _imageChars = 400 * 1024;
const _logLines = 700;
const _lineChars = 300;
const _crashChars = 8192;
const _chars = {
  'trigger': 32,
  'version': 32,
  'core': 64,
  'abi': 32,
  'language': 16,
  'theme': 16,
  'manufacturer': 64,
  'brand': 64,
  'model': 64,
  'device': 64,
  'release': 32,
  'security_patch': 32,
  'time_zone': 64,
  'locale': 32,
  'navigation_mode': 32,
  'network_name': 64,
  'network_code': 8,
  'sim_name': 64,
  'sim_code': 8,
  'data_saver': 16,
  'state': 32,
  'last_error': 64,
  'username': 64,
  'status': 32,
  'last_refresh': 32,
  'label': 100,
  'reason': 64,
  'text': _crashChars,
};
const _items = {
  'abis': 8,
  'transports': 8,
  'sims': 4,
  'services': 20,
  'servers': 300,
  'crashes': 10,
  'log': _logLines,
  'logcat': 100,
};
const _itemChars = {
  'abis': 32,
  'transports': 16,
  'log': _lineChars,
  'logcat': _lineChars,
};

Object? _tidy(Object? value, [String? key]) => switch (value) {
  final Map<String, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries)
      if (value != null) key: _tidy(value, key),
  },
  final List<Object?> list => [
    for (final item in list.take(_items[key] ?? list.length))
      if (item is String)
        _cut(_unlinked(item), _itemChars[key])
      else if (item != null)
        _tidy(item),
  ],
  final String text => _cut(_unlinked(text), _chars[key]),
  _ => value,
};

/// Within the door's limits always, or it refuses the whole report: nulls out, strings and
/// lists cut, no link shape left, and both images dropped while the UTF-8 body is too big.
Map<String, Object?> fitReport(Map<String, Object?> report) {
  final images = report['images'];
  final fitted = _tidy({...report}..remove('images'))! as Map<String, Object?>;
  if (images == null) return fitted;
  final whole = {...fitted, 'images': images};
  if (utf8.encode(jsonEncode(whole)).length <= _reportBytes) return whole;
  return {
    ...fitted,
    'images': {'note': 'too_large'},
  };
}

Future<Map<String, Object?>> _imagesOf({
  Uint8List? app,
  Uint8List? screen,
  bool on = true,
}) async {
  if (!on) return {'note': 'off'};
  var dropped = false;
  Future<String?> fit(Uint8List? png) async {
    if (png == null) return null;
    var text = base64.encode(png);
    if (text.length > _imageChars) {
      final half = await _halve(png);
      text = half == null ? '' : base64.encode(half);
    }
    if (text.isNotEmpty && text.length <= _imageChars) return text;
    dropped = true;
    return null;
  }

  final appText = await fit(app);
  final screenText = await fit(screen);
  return {
    'app': ?appText,
    'screen': ?screenText,
    if (dropped) 'note': 'too_large',
  };
}

Future<Uint8List?> _halve(Uint8List png) async {
  try {
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(png),
      getTargetSize: (width, height) =>
          ui.TargetImageSize(width: width ~/ 2, height: height ~/ 2),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// The newest `E` lines first, then the newest of the rest, in their own order.
List<String> _pickLog(List<String> lines) {
  bool error(String line) => line.split(' ').elementAtOrNull(1) == 'E';
  final keep = <int>{};
  for (var i = lines.length - 1; i >= 0 && keep.length < _logLines; i--) {
    if (error(lines[i])) keep.add(i);
  }
  for (var i = lines.length - 1; i >= 0 && keep.length < _logLines; i--) {
    keep.add(i);
  }
  return [
    for (var i = 0; i < lines.length; i++)
      if (keep.contains(i)) _cut(lines[i], _lineChars),
  ];
}

final _threadtime = RegExp(
  r'^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\s+\d+\s+\d+\s+([VDIWEF])\s+[^:]*:\s?(.*)$',
);

List<String> _logcatLines(String? tail, RegExp? known) => [
  for (final line in LineSplitter.split(tail ?? ''))
    if (_threadtime.firstMatch(line) case final m?)
      '${m[1]} ${m[2]} ${cleanLine(m[3]!, known)}',
];

Map<String, Object?> _box(EdgeInsets e) => {
  'top': e.top,
  'right': e.right,
  'bottom': e.bottom,
  'left': e.left,
};

/// The report's app, device, screen, graphics, network and power sections from typed values;
/// [native] is `ShikooDiag.kt`'s `state`.
Map<String, Object?> aboutSections({
  required BaseDeviceInfo device,
  required bool tv,
  required String version,
  required int? build,
  required String abi,
  required bool signedIn,
  required ShikooLook look,
  required MediaQueryData media,
  required List<ConnectivityResult> transports,
  required Map<Object?, Object?>? native,
  required String backend,
  required DateTime now,
  required String locale,
}) {
  final dns = native?['privateDns'];
  final ignores = native?['ignoresOptimizations'];
  return {
    'app': {
      'version': version,
      'build': build,
      'core': 'FlClash $flclashVersion, ${coreName()}',
      'abi': abi,
      'env': shikooApiBases.first == 'https://app.chopon.uk'
          ? 'production'
          : 'staging',
      'signed_in': signedIn,
      'language': look.language,
      'theme': look.theme.name,
    },
    'device': {
      'tv': tv,
      ...switch (device) {
        final AndroidDeviceInfo device => {
          'manufacturer': device.manufacturer,
          'brand': device.brand,
          'model': device.model,
          'device': device.device,
          'release': device.version.release,
          'sdk': device.version.sdkInt,
          'security_patch': device.version.securityPatch,
          'abis': device.supportedAbis,
          'low_ram': device.isLowRamDevice,
          'ram_total_mb': device.physicalRamSize,
          'ram_free_mb': device.availableRamSize,
          'disk_free_mb': device.freeDiskSize ~/ (1024 * 1024),
        },
        // The door refuses the whole report over a key it does not know.
        final WindowsDeviceInfo device => {
          'model': device.productName,
          'release':
              '${device.majorVersion}.${device.minorVersion}.${device.buildNumber}',
          'ram_total_mb': device.systemMemoryInMegabytes,
        },
        _ => const <String, Object?>{},
      },
      'time_zone': now.timeZoneName,
      'tz_offset_min': now.timeZoneOffset.inMinutes,
      'locale': locale,
    },
    'screen': {
      'width_dp': media.size.width,
      'height_dp': media.size.height,
      'pixel_ratio': media.devicePixelRatio,
      'text_scale': media.textScaler.scale(14) / 14,
      'padding': _box(media.padding),
      'insets': _box(media.viewInsets),
      'bold_text': media.boldText,
      'navigation_mode': switch (native?['navigation']) {
        0 => 'buttons',
        1 => 'two_buttons',
        2 => 'gesture',
        _ => null,
      },
    },
    'graphics': {'backend': backend},
    'network': {
      'transports': [for (final t in transports) t.name],
      'airplane': native?['airplane'],
      'sim_slots': native?['simSlots'],
      'sims': [
        for (final sim in (native?['sims'] as List?) ?? const [])
          if (sim case final Map<Object?, Object?> sim)
            {
              'slot': sim['slot'],
              'network_name': sim['network'],
              'network_code': sim['networkCode'],
              'sim_name': sim['sim'],
              'sim_code': sim['simCode'],
              'data': sim['data'],
            },
      ],
      'private_dns_active': dns == null ? null : dns != 'off',
      'private_dns_strict': dns == null ? null : dns == 'strict',
      'data_saver': switch (native?['dataSaver']) {
        1 => 'disabled',
        2 => 'allowed',
        3 => 'enabled',
        _ => null,
      },
    },
    'power': {
      'battery_saver': native?['batterySaver'],
      'idle': native?['idle'],
      'battery_optimized': ignores is bool ? !ignores : null,
      'background_restricted': native?['backgroundRestricted'],
      'standby_bucket': native?['standbyBucket'],
    },
  };
}

typedef _Line = (DateTime, String, String);

enum LogTab { connection, subscription, core, errors }

enum LogMark { none, warning, error }

/// A log level never reaches the record, so an `A` line is an error, and a `T` line a warning, by its words.
final _trouble = RegExp(
  r'error|exception|fail|timed? ?out|denied|refused|died|crash',
  caseSensitive: false,
);
final _entry = RegExp(r'^(\S+) (\S) ?(.*?)(?: ×(\d+))?$');

/// One record line as the Logs page shows it; «کپی» copies [line] as written.
class LogEntry {
  const LogEntry(this.line, this.at, this.kind, this.text, this.repeats);

  static LogEntry? parse(String line) {
    final m = _entry.firstMatch(line);
    final at = DateTime.tryParse(m?[1] ?? '');
    if (m == null || at == null) return null;
    return LogEntry(line, at, m[2]!, m[3]!, int.tryParse(m[4] ?? '') ?? 1);
  }

  final String line;
  final DateTime at;
  final String kind;
  final String text;
  final int repeats;

  bool get _refresh => text.startsWith('refresh ');

  LogTab? get tab => switch (kind) {
    'T' => _refresh ? LogTab.subscription : LogTab.connection,
    'C' => LogTab.core,
    'E' => LogTab.errors,
    'A' when _trouble.hasMatch(text) => LogTab.errors,
    _ => null,
  };

  LogMark get mark => switch (kind) {
    _ when tab == LogTab.errors => LogMark.error,
    'C' => switch (text.split(' ').first) {
      'error' => LogMark.error,
      'warning' => LogMark.warning,
      _ => LogMark.none,
    },
    'T' when (_refresh && text != 'refresh ok') || _trouble.hasMatch(text) =>
      LogMark.warning,
    _ => LogMark.none,
  };
}

/// The recorder. It starts in `main()` before FlClash does, holds what comes before [attach]
/// raw in memory (the secrets it must remove are known only then), and writes cleaned lines
/// to `<support dir>/shikoo/diag.log`. Kinds: `A` app log, `C` core, `E` Dart error,
/// `T` timeline, `U` UI event.
class ShikooDiag with CoreEventListener, WidgetsBindingObserver {
  ShikooDiag({
    Set<String>? machine,
    Future<List<String>> Function(ProviderContainer)? windows,
  }) : _machine =
           machine ??
           (Platform.isWindows
               ? windowsNames(Platform.environment, Platform.localHostname)
               : const {}),
       _windows = windows ?? (Platform.isWindows ? _readWindows : null);

  final Future<List<String>> Function(ProviderContainer)? _windows;

  static const _channel = MethodChannel('shikoo/diag');
  static const _ringBytes = 256 * 1024;
  static const keep = Duration(days: 7);
  static const _seenExitKey = 'shikoo.diag.seenExit';
  static const _sentExitKey = 'shikoo.diag.sentExit';
  static const _askedCrashKey = 'shikoo.diag.askedCrash';
  static const _crashed = {
    AppExitReason.crash,
    AppExitReason.crashNative,
    AppExitReason.anr,
  };

  String? _home;
  RandomAccessFile? _out;
  int _size = 0;
  final _early = <_Line>[];
  bool _holding = true;
  ProviderContainer? _container;
  final _secrets = <String>{};
  final Set<String> _machine;
  late RegExp? _known = _knownPattern(const [], _machine);
  String? _lastKind;
  String? _lastText;
  int _repeats = 0;
  DateTime _repeatAt = DateTime(0);
  String _backend = 'unknown';
  final _refreshes = <int, String>{};
  FocusNode? _focused;
  Timer? _framesTimer;
  int _frames = 0;
  int _slow = 0;
  int _worstBuild = 0;
  int _worstRaster = 0;

  final appKey = GlobalKey();
  late final NavigatorObserver routes = _Routes(this);

  String get _dir => '$_home/shikoo';

  String get _ring => '$_dir/diag.log';

  Future<void> start(String home) async {
    try {
      Directory('$home/shikoo').createSync(recursive: true);
      _home = home;
      final file = File(_ring);
      _size = file.existsSync() ? file.lengthSync() : 0;
      _out = file.openSync(mode: FileMode.append);
    } catch (_) {
      _out = null;
    }
    add('T', 'app start');
  }

  /// Every line of [text], cleaned; an identical line right after itself only counts.
  void add(String kind, String text, {DateTime? at}) {
    final when = at ?? DateTime.now();
    for (final line in LineSplitter.split(text)) {
      if (_holding) {
        if (_early.length < 2000) _early.add((when, kind, line));
      } else {
        _record(when, kind, line);
      }
    }
  }

  void error(Object error, StackTrace? stack) {
    add('E', '$error');
    add('E', LineSplitter.split('${stack ?? ''}').take(30).join('\n'));
  }

  /// Writes what waited: after [attach] with the secrets known, or with the shape filter alone
  /// when init failed and no attach will come.
  void release() {
    _holding = false;
    for (final (at, kind, line) in _early) {
      _record(at, kind, line);
    }
    _early.clear();
  }

  void _record(DateTime at, String kind, String line) {
    // Room for the 20-character time, the kind and a « ×n» count within the line's 300.
    final text = _cut(cleanLine(line, _knownNow()), _lineChars - 30);
    if (kind == _lastKind && text == _lastText) {
      _repeats++;
      _repeatAt = at;
      return;
    }
    _flushRepeat();
    _lastKind = kind;
    _lastText = text;
    _write(at, kind, text);
  }

  void _flushRepeat() {
    if (_repeats == 0) return;
    _write(_repeatAt, _lastKind!, '$_lastText ×${_repeats + 1}');
    _repeats = 0;
    // The count took the plain line in: one more repeat starts over from a plain line.
    _lastText = null;
  }

  static String _stamp(DateTime at) =>
      '${at.toUtc().toIso8601String().substring(0, 19)}Z';

  void _write(DateTime at, String kind, String text) {
    final out = _out;
    if (out == null) return;
    try {
      final bytes = utf8.encode('${_stamp(at)} $kind $text\n');
      out.writeFromSync(bytes);
      _size += bytes.length;
      if (_size > _ringBytes) {
        out.closeSync();
        File(_ring).renameSync('$_ring.1');
        _out = File(_ring).openSync(mode: FileMode.append);
        _size = 0;
      }
    } catch (_) {}
  }

  RegExp? _knownNow() {
    final container = _container;
    if (container == null) return _known;
    final before = _secrets.length;
    try {
      _secrets.addAll(container.read(shikooSignInProvider).secrets);
      final auth = container.read(networkSettingProvider).authentication;
      _secrets.addAll([auth.username, auth.password]);
      for (final profile in container.read(profilesProvider)) {
        _secrets.add(profile.url);
        final uri = Uri.tryParse(profile.url);
        if (uri == null) continue;
        _secrets
          ..add(uri.host)
          ..addAll(uri.pathSegments)
          // A short one is a format (`target=clash`), and would eat the word FlClash.
          ..addAll(uri.queryParameters.values.where((v) => v.length >= 8));
      }
    } catch (_) {}
    // Kept once seen: a crash file read later still holds a password or token since replaced.
    if (_secrets.length != before) _known = _knownPattern(_secrets, _machine);
    return _known;
  }

  /// The panel's account name, never one of the secrets the app holds, a link's path included.
  String _username(String name) {
    final lower = name.toLowerCase();
    return _usernameShape.hasMatch(name) &&
            ![
              ..._secrets,
              ..._machine,
            ].any((secret) => secret.toLowerCase() == lower)
        ? name
        : _bullet;
  }

  /// After `bootstrap.attach()`: the secrets are known, and the start's records are read.
  Future<void> attach(ProviderContainer container) {
    _container = container;
    release();
    coreEventManager.addListener(this);
    container.listen(
      shikooStateProvider.select((s) => (s.connection, s.lastError)),
      (_, next) => add('T', ['vpn', next.$1.name, ?next.$2?.name].join(' ')),
    );
    container.listen(shikooStateProvider.select((s) => s.pinging == null), (
      was,
      done,
    ) {
      if (was == false && done) {
        _pingRound(container.read(shikooStateProvider).servers);
      }
    });
    container.listen(shikooStateProvider.select((s) => s.switching), (
      _,
      shift,
    ) {
      if (shift?.stage == ShikooSwitchStage.failed) {
        add('T', 'server switch failed ${withoutFlags(shift!.to)}');
      }
    });
    container.listen(shikooStateProvider.select((s) => s.notice), (_, notice) {
      if (notice case SilentReplaced(:final silent, :final replacement)) {
        add(
          'T',
          'server silent ${withoutFlags(silent)} -> ${withoutFlags(replacement)}',
        );
      }
    });
    // After the two above, so a cause changing with the server is told first.
    container.listen(shikooStateProvider.select(_serverLine), (_, line) {
      if (line != null) add('T', line);
    });
    return _onStart();
  }

  static String? _serverLine(ShikooState state) =>
      switch ((state.connection, state.selectedServer?.label)) {
        (ShikooConnection.on, final label?) => 'server in use $label',
        (ShikooConnection.error, final label?) => 'server tried $label',
        _ => null,
      };

  Future<void> _onStart() async {
    final prefs = await SharedPreferences.getInstance();
    final exits = await _exits(prefs.getInt(_seenExitKey) ?? 0);
    for (final exit in exits.sortedBy<num>((e) => e['time'] as num)) {
      add(
        'T',
        'exit ${_reasonName(exit['reason'])} status ${exit['status']}',
        at: DateTime.fromMillisecondsSinceEpoch(exit['time'] as int),
      );
    }
    if (exits.isNotEmpty) {
      await prefs.setInt(_seenExitKey, exits.map((e) => e['time'] as int).max);
    }
    _offerCrash(prefs, exits);
    _backend = _backendOf(await _invoke<String>('renderer'));
    add('T', 'renderer $_backend');
    await takeEvents();
  }

  // ponytail: an exit record is read on one start only, so a crash known from it alone is offered then.
  void _offerCrash(SharedPreferences prefs, List<Map<Object?, Object?>> exits) {
    // A sent crash file is emptied in place, not deleted (send).
    int? written(File file) =>
        _home != null && file.existsSync() && file.lengthSync() > 0
        ? file.lastModifiedSync().millisecondsSinceEpoch
        : null;
    final times = [
      for (final exit in exits)
        if (_crashed.contains(AppExitReason.fromCode(exit['reason'])))
          exit['time'] as int,
      ?written(File('$_dir/java-crash.txt')),
      ?written(File('$_home/go-crash.txt')),
    ];
    final newest = times.maxOrNull;
    if (newest != null && newest > (prefs.getInt(_askedCrashKey) ?? 0)) {
      _container?.read(shikooCrashProvider.notifier).set(newest);
    }
  }

  Future<void> crashAsked() async {
    final container = _container;
    final at = container?.read(shikooCrashProvider);
    if (container == null || at == null) return;
    container.read(shikooCrashProvider.notifier).set(null);
    await (await SharedPreferences.getInstance()).setInt(_askedCrashKey, at);
  }

  /// Kotlin's `events.txt` (screen, airplane mode, revoked, alive) into the timeline.
  Future<void> takeEvents() async {
    if (_home == null) return;
    final File taken;
    try {
      taken = File('$_dir/events.txt').renameSync('$_dir/events.taken');
    } on FileSystemException {
      return;
    }
    for (final line in LineSplitter.split(_read(taken))) {
      final space = line.indexOf(' ');
      final at = int.tryParse(line.substring(0, math.max(space, 0)));
      if (at == null) continue;
      add(
        'T',
        line.substring(space + 1),
        at: DateTime.fromMillisecondsSinceEpoch(at),
      );
    }
    try {
      taken.deleteSync();
    } on FileSystemException {
      return;
    }
  }

  static String _read(File file) =>
      utf8.decode(file.readAsBytesSync(), allowMalformed: true);

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<Object?, Object?>>> _exits(int since) async => [
    for (final exit in await _invoke<List<Object?>>('exits', since) ?? const [])
      if (exit case final Map<Object?, Object?> exit) exit,
  ];

  void _pingRound(List<ShikooServer> servers) {
    final answered = [
      for (final server in servers)
        if ((server.ping ?? 0) > 0) server.ping!,
    ];
    final silent = servers.where((server) => server.ping == -1).length;
    add(
      'T',
      'ping ${answered.length} answered, $silent silent'
          '${answered.isEmpty ? '' : ', best ${answered.min}ms'}',
    );
  }

  @override
  void onLog(Log log) => add('C', '${log.logLevel.name} ${log.payload}');

  @override
  void onCrash(String message) => add('T', 'core died $message');

  void network(List<ConnectivityResult> results) =>
      add('T', 'network ${results.map((r) => r.name).join(',')}');

  void refreshed(int id, Object? error) {
    final kind = error == null ? 'ok' : failureKind(error);
    _refreshes[id] = kind;
    add('T', 'refresh ${kind.replaceAll('_', ' ')}');
  }

  /// Keys, focus, metrics, scrolls and frames, from ShikooApp's first frame on; the frame
  /// summary's timer is returned.
  Timer watchUi() {
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_onFocus);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _framesTimer?.cancel();
    _framesTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (frameSummary(_frames, _slow, _worstBuild, _worstRaster)
          case final line?) {
        add('T', line);
      }
      _frames = _slow = _worstBuild = _worstRaster = 0;
    });
    return _framesTimer!;
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      final raster = timing.rasterDuration.inMilliseconds;
      _frames++;
      if (raster > 32) _slow++;
      _worstBuild = math.max(_worstBuild, timing.buildDuration.inMilliseconds);
      _worstRaster = math.max(_worstRaster, raster);
    }
  }

  /// No text a field holds is recorded: a printable key is only `char`.
  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      final printable = event.character?.trim().isNotEmpty ?? false;
      add('U', 'key ${printable ? 'char' : event.logicalKey.keyLabel}');
    }
    return false;
  }

  static const _wrappers = {
    'Focus',
    'Semantics',
    'Actions',
    'Shortcuts',
    'MouseRegion',
    'DefaultSelectionStyle',
    'GestureDetector',
    'FocusableActionDetector',
    'Pressable',
  };

  static String _named(BuildContext context) {
    String? name(Widget widget) {
      final type = '${widget.runtimeType}'.split('<').first;
      return type.startsWith('_') || _wrappers.contains(type) ? null : type;
    }

    var found = name(context.widget);
    context.visitAncestorElements((element) {
      found ??= name(element.widget);
      return found == null;
    });
    return found ?? '';
  }

  static String _rect(Rect rect) =>
      'at ${rect.left.round()},${rect.top.round()} '
      'size ${rect.width.round()},${rect.height.round()}';

  void _onFocus() {
    final node = FocusManager.instance.primaryFocus;
    if (identical(node, _focused)) return;
    _focused = node;
    final context = node?.context;
    final box = context?.findRenderObject();
    if (context == null || box is! RenderBox || !box.hasSize) return;
    add(
      'U',
      'focus ${_named(context)} '
          '${_rect(box.localToGlobal(Offset.zero) & box.size)}',
    );
  }

  bool onScrollEnd(ScrollEndNotification notification) {
    final metrics = notification.metrics;
    add(
      'U',
      'scroll ${metrics.axis.name} ${metrics.pixels.round()} '
          'of ${metrics.maxScrollExtent.round()}',
    );
    return false;
  }

  static String _insets(EdgeInsets e) =>
      [e.left, e.top, e.right, e.bottom].map((v) => v.round()).join(',');

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null) return;
    final media = MediaQueryData.fromView(view);
    add(
      'U',
      'metrics ${media.size.width.round()},${media.size.height.round()} '
          'ratio ${(media.devicePixelRatio * 100).round()}% '
          'pad ${_insets(media.padding)} inset ${_insets(media.viewInsets)}',
    );
  }

  @override
  void didChangeTextScaleFactor() {
    final scale = WidgetsBinding.instance.platformDispatcher.textScaleFactor;
    add('U', 'text scale ${(scale * 100).round()}%');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      add('T', 'app resumed');
      unawaited(takeEvents());
    } else if (state == AppLifecycleState.paused) {
      add('T', 'app paused');
      _flushRepeat();
    }
  }

  /// What the app drew, one pixel per dp, from the `RepaintBoundary` at [appKey].
  Future<Uint8List?> captureApp() async {
    final boundary = appKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// What was on the window: a `PixelCopy` of the Flutter surface, one pixel per dp.
  Future<Uint8List?> captureScreen() => _invoke<Uint8List>('screen');

  Future<Map<String, Object?>> about() async {
    final container = _container!;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return aboutSections(
      device: await DeviceInfoPlugin().deviceInfo,
      tv: system.isTV,
      version: container.read(shikooVersionProvider),
      build: int.tryParse(globalState.packageInfo.buildNumber),
      abi: reportAbi(Abi.current()),
      signedIn: container.read(shikooAccountProvider).who != null,
      look: container.read(shikooLookProvider),
      media: MediaQueryData.fromView(view),
      transports: await Connectivity().checkConnectivity(),
      native: await _invoke<Map<Object?, Object?>>('state'),
      backend: _backend,
      now: DateTime.now(),
      locale: view.platformDispatcher.locale.toLanguageTag(),
    );
  }

  List<String> _ringLines(DateTime now, RegExp? known) {
    final since = now.subtract(keep);
    return [
      for (final file in [File('$_ring.1'), File(_ring)])
        if (_home != null && file.existsSync())
          for (final line in LineSplitter.split(_read(file)))
            if (DateTime.tryParse(line.split(' ').first)?.isAfter(since) ??
                false)
              _again(line, known),
    ];
  }

  /// The Logs page's lines, in the record's order: what [report] reads, the lines a tab shows.
  List<LogEntry> logEntries() {
    _flushRepeat();
    return [
      for (final line in _ringLines(DateTime.now(), _knownNow()))
        if (LogEntry.parse(line) case final entry? when entry.tab != null)
          entry,
    ];
  }

  /// A line written before a name or secret was known: its text past the stamp and kind loses it now.
  static String _again(String line, RegExp? known) =>
      known == null || line.length < 23
      ? line
      : line.replaceRange(
          23,
          null,
          line.substring(23).replaceAll(known, _bullet),
        );

  static String _cleanText(
    Iterable<String> lines,
    RegExp? known, {
    bool go = false,
  }) => _cut(
    lines.map((line) => cleanLine(line, known, go: go)).join('\n').trim(),
    _crashChars,
  );

  Future<List<Map<String, Object?>>> _crashes(
    DateTime now,
    RegExp? known,
  ) async {
    final since = now.subtract(keep).millisecondsSinceEpoch;
    final java = File('$_dir/java-crash.txt');
    final go = File('$_home/go-crash.txt');
    final prefs = await SharedPreferences.getInstance();
    final sent = prefs.getInt(_sentExitKey) ?? 0;
    final all = <Map<String, Object?>>[
      if (java.existsSync())
        for (final block in _read(java).split(RegExp('^--- ', multiLine: true)))
          if (int.tryParse(block.split(' ').first) case final at?)
            {
              'source': 'java',
              'time_ms': at,
              'text': _cleanText(LineSplitter.split(block).skip(1), known),
            },
      if (go.existsSync() && go.lengthSync() > 0)
        {
          'source': 'go',
          'time_ms': go.lastModifiedSync().millisecondsSinceEpoch,
          'text': _cleanText(LineSplitter.split(_read(go)), known, go: true),
        },
      for (final exit in await _exits(math.max(sent, since)))
        {
          'source': 'exit',
          'time_ms': exit['time'],
          'reason': _reasonName(exit['reason']),
          'status': exit['status'],
          'text': _cleanText(
            LineSplitter.split(
              '${exit['description'] ?? ''}\n${exit['trace'] ?? ''}',
            ),
            known,
          ),
        },
    ];
    return all
        .where((crash) => (crash['time_ms'] as int) >= since)
        .sortedBy<num>((crash) => -(crash['time_ms'] as int))
        .take(_items['crashes']!)
        .toList();
  }

  /// The whole report, cleaned and within the door's limits; [checks] measured now unless given.
  Future<Map<String, Object?>> report({
    required String trigger,
    required Map<String, Object?> about,
    Uint8List? appImage,
    Uint8List? screenImage,
    bool images = true,
    ProbeChecks? checks,
  }) async {
    final probed =
        checks ??
        await runProbes(
          proxy: ownerAside(_container!.read, Uri.parse(internationalProbe)),
        );
    try {
      for (final line
          in await _windows?.call(_container!) ?? const <String>[]) {
        add('T', line);
      }
    } catch (_) {}
    final state = _container!.read(shikooStateProvider);
    if (_serverLine(state) case final line?) add('T', line);
    _flushRepeat();
    final now = DateTime.now();
    final known = _knownNow();
    final transports = ((about['network'] as Map?)?['transports'] as List?)
        ?.cast<String>();
    final services = [?state.service, ...state.others];
    return fitReport({
      'meta': {
        'schema': 1,
        'device_time_ms': now.millisecondsSinceEpoch,
        'trigger': trigger,
      },
      ...about,
      'vpn': {
        'state': state.connection.name,
        'last_error': state.lastError?.name,
        'other_vpn':
            state.connection == ShikooConnection.off &&
            (transports?.contains('vpn') ?? false),
      },
      'checks': _checksOf(probed),
      'services': [
        for (final service in services)
          {
            'username': _username(service.account ?? service.username),
            'status': service.revoked
                ? 'revoked'
                : service.statusAt(shikooNow()).name,
            'days_left': service.expire?.difference(shikooNow()).inDays,
            'used_gb': service.usageKnown
                ? (service.usedBytes / (1 << 30) * 100).round() / 100
                : null,
            'total_gb': (service.totalBytes / (1 << 30) * 100).round() / 100,
            'last_refresh': _refreshes[service.id],
            'minutes_since_update': switch (service.updatedAt) {
              final at? => now.difference(at).inMinutes,
              null => null,
            },
          },
      ],
      'servers': [
        for (final server in state.servers)
          {'label': cleanLine(server.label, known), 'ping_ms': server.ping},
      ],
      'crashes': await _crashes(now, known),
      'log': _pickLog(_ringLines(now, known)),
      'logcat': _logcatLines(await _invoke<String>('logTail'), known),
      'images': await _imagesOf(app: appImage, screen: screenImage, on: images),
    });
  }

  /// The crash files are emptied once the door has them, and the exit records sent are not
  /// sent again. Emptied in place: the Go core keeps go-crash.txt open from its init, and a
  /// deleted file would take every later panic of this process with it.
  Future<({String code, bool linked})> send(Map<String, Object?> report) async {
    final answer = await _container!.read(shikooSignInProvider).report(report);
    for (final file in [
      File('$_dir/java-crash.txt'),
      File('$_home/go-crash.txt'),
    ]) {
      try {
        if (file.existsSync()) file.writeAsBytesSync(const []);
      } on FileSystemException {
        continue;
      }
    }
    final sent = [
      for (final crash in (report['crashes'] as List?) ?? const [])
        if (crash case {'source': 'exit', 'time_ms': final int at}) at,
    ];
    if (sent.isNotEmpty) {
      await (await SharedPreferences.getInstance()).setInt(
        _sentExitKey,
        sent.max,
      );
    }
    return answer;
  }
}

class _Routes extends NavigatorObserver {
  _Routes(this._diag);

  final ShikooDiag _diag;

  String _page(Route<dynamic> route) => switch (route.settings.name) {
    '/' => 'home',
    final String name => name,
    null => '${route.runtimeType}'.split('<').first,
  };

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _diag.add('U', 'push ${_page(route)}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _diag.add('U', 'pop ${_page(route)}');
}

final shikooDiag = ShikooDiag();

/// The screens reach the recorder here, so a test can stand in for the device's pictures.
final shikooDiagProvider = Provider<ShikooDiag>((_) => shikooDiag);

final shikooCrashProvider = NotifierProvider<ShikooCell<int?>, int?>(
  () => ShikooCell(null),
);
