import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/providers/providers.dart'
    show runTimeProvider, versionProvider;
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart' show shikooSkew;
import 'package:fl_clash/shikoo/engine/controller.dart'
    show ShikooController, shikooControllerProvider;
import 'package:fl_clash/shikoo/engine/diag.dart'
    show ShikooDiag, shikooDiagProvider;
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

/// Over three of the hash's 64 KiB reads, so hashing only the first one fails.
final _apk = Uint8List.fromList(List.generate(200000, (i) => i * 7 % 256));
final _sha = '${sha256.convert(_apk)}';

/// Stands in for RSA, which the core's tests check against openssl: a seal holds only for its own key and message.
String _sealOf(String key, String message) => 'seal($key|$message)';

String _message(int code, String sha) => 'shikoonet-windows-update:$code:$sha';

/// The connection, in the order the update drives it.
class _Controller implements ShikooController {
  _Controller(this.events, this.onDisconnect);

  final List<String> events;
  void Function() onDisconnect;

  @override
  Future<void> disconnect() async {
    events.add('disconnect');
    onDisconnect();
  }

  @override
  Future<void> connectAgain() async => events.add('connect again');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Diag extends ShikooDiag {
  final lines = <String>[];

  @override
  void add(String kind, String text, {DateTime? at}) =>
      lines.add('$kind $text');
}

/// Inno's loader: it exits only when it did not install, as installing kills the app.
class _Installer extends Fake implements Process {
  final exited = Completer<int>();

  @override
  Future<int> get exitCode => exited.future;
}

/// The app door as docs/app-update.md pins it: the manifest, and `/dl/` with Range.
class _Door implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final dead = <String>{};
  int manifestStatus = 200;
  String abi = 'arm64-v8a';
  String sha = _sha;
  String? url;
  bool ranges = true;
  int code = 2057;
  int minimum = 2050;
  String? entryVersion;
  String? sig;
  Map<String, Object?> others = {};

  /// The connection drops once a download reaches this byte of the file.
  int? dropAt;

  /// A download stalls at this byte until it is cancelled.
  int? holdAt;

  /// Android refuses the door's certificate with this reason.
  String? refusedFor;

  Iterable<RequestOptions> get downloads =>
      requests.where((r) => r.uri.path.startsWith('/dl/'));

  int get checks => requests.length - downloads.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (dead.contains(options.uri.host)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'unreachable',
      );
    }
    if (refusedFor case final reason?) {
      throw DioException(
        requestOptions: options,
        error: HandshakeException(
          'Handshake error in client',
          OSError('CERTIFICATE_VERIFY_FAILED: $reason(handshake.cc:297)'),
        ),
      );
    }
    if (options.uri.path == '/api/v1/app/update') {
      return ResponseBody.fromString(
        jsonEncode(
          manifestStatus == 200
              ? {
                  'ok': true,
                  'version_name': '1.0.57',
                  'published_at': '2026-10-06T00:00:00.000Z',
                  'apks': {
                    ...others,
                    abi: {
                      'version_code': code,
                      'min_version_code': minimum,
                      'size': _apk.length,
                      'sha256': sha,
                      'url':
                          url ??
                          '/dl/ShikooNet-1.0.57-$abi.'
                              '${abi.startsWith('windows') ? 'exe' : 'apk'}',
                      'version_name': ?entryVersion,
                      'sig': ?sig,
                    },
                  },
                }
              : {'ok': false, 'error': 'no_release'},
        ),
        manifestStatus,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    final asked = RegExp(
      r'^bytes=(\d+)-$',
    ).firstMatch('${options.headers[HttpHeaders.rangeHeader] ?? ''}');
    final from = ranges && asked != null ? int.parse(asked[1]!) : 0;
    return ResponseBody(
      _body(from, cancelFuture),
      from > 0 ? 206 : 200,
      headers: {
        if (from > 0)
          HttpHeaders.contentRangeHeader: [
            'bytes $from-${_apk.length - 1}/${_apk.length}',
          ],
      },
    );
  }

  Stream<Uint8List> _body(int from, Future<void>? cancelled) async* {
    for (var at = from; at < _apk.length; at += 1000) {
      if (dropAt != null && at >= dropAt!) {
        throw const SocketException('dropped');
      }
      if (holdAt != null && at >= holdAt!) {
        // Dio stops reading when cancelled and reports the cancel itself.
        await cancelled;
        return;
      }
      yield _apk.sublist(at, min(at + 1000, _apk.length));
    }
  }

  @override
  void close({bool force = false}) {}
}

/// The door's plain http, which only `clockFailed` asks: it answers with its own [clock].
Future<String> _plainDoor(DateTime clock) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) {
    request.response.headers.date = clock;
    unawaited(request.response.close());
  });
  return 'http://127.0.0.1:${server.port}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Door door;
  late Directory cache;
  late ProviderContainer container;
  late DateTime clock;
  late List<MethodCall> native;
  late bool canInstall;
  late bool hasSettings;
  late bool installerOpens;
  late List<String> seals;
  late bool? coreAnswers;
  late List<String> events;
  late List<List<String>> started;
  late _Installer installer;
  late bool startFails;
  late _Diag diag;

  setUp(() async {
    door = _Door();
    cache = await Directory.systemTemp.createTemp('shikoo_update');
    addTearDown(() => cache.delete(recursive: true));
    clock = DateTime(2026, 10, 6, 12);
    native = [];
    canInstall = true;
    hasSettings = true;
    installerOpens = true;
    seals = [];
    coreAnswers = true;
    events = [];
    started = [];
    installer = _Installer();
    startFails = false;
    diag = _Diag();
    const channel = MethodChannel('shikoo/update');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      native.add(call);
      return switch (call.method) {
        'canInstall' => canInstall,
        'openInstallSettings' => hasSettings,
        'install' => installerOpens,
        _ => true,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  ShikooUpdate start({
    List<String> bases = const ['http://door.test'],
    int installed = 2051,
    String abi = 'arm64-v8a',
    int sdk = 35,
  }) {
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = door;
    container = ProviderContainer(
      overrides: [
        shikooApiProvider.overrideWithValue(ShikooApi(bases, dio)),
        versionProvider.overrideWithBuild((_, _) => sdk),
        shikooControllerProvider.overrideWithValue(
          _Controller(
            events,
            () => container.read(runTimeProvider.notifier).value = null,
          ),
        ),
        shikooDiagProvider.overrideWithValue(diag),
      ],
    );
    addTearDown(container.dispose);
    container.listen(runTimeProvider, (_, _) {});
    return container.read(shikooUpdateProvider)
      ..abi = abi
      ..installed = installed
      ..cacheDir = (() async => cache)
      ..now = (() => clock)
      ..sealKey = windowsSealKeyStaging
      ..checkSeal = (key, message, sig) async {
        seals.add(message);
        return coreAnswers == null ? null : sig == _sealOf(key, message);
      }
      ..startInstaller = (exe, arguments) async {
        events.add('start');
        started.add([exe, ...arguments]);
        if (startFails) throw const ProcessException('setup', [], 'refused');
        return installer;
      };
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  UpdateOffer? offer() => container.read(shikooUpdateOfferProvider);

  File part() => File('${cache.path}/update/$_sha.part');

  File apk() => File('${cache.path}/update/$_sha.apk');

  group('check', () {
    test('offers a newer build, and forces one below the minimum', () async {
      await start().check();
      expect(offer()!.release.versionName, '1.0.57');
      expect(offer()!.release.versionCode, 2057);
      expect(offer()!.forced, isFalse);
      expect(offer()!.phase, UpdatePhase.offered);

      await start(installed: 2049).check();
      expect(offer()!.forced, isTrue);

      await start(installed: 2050).check();
      expect(
        offer()!.forced,
        isFalse,
        reason: 'the minimum itself is still accepted',
      );
    });

    test('a local build and the published build itself get nothing', () async {
      for (final installed in [2026091401, 2026093401, 2057]) {
        await start(installed: installed).check();
        expect(offer(), isNull, reason: '$installed');
      }
    });

    test(
      'nothing before the first release or for an ABI the door lacks',
      () async {
        door.manifestStatus = 404;
        await start().check();
        expect(offer(), isNull);

        door.manifestStatus = 200;
        await start(abi: 'x86_64').check();
        expect(offer(), isNull);

        await start(abi: '').check();
        expect(offer(), isNull, reason: 'Windows on Arm has no build');
      },
    );

    test('a /dl/ path belongs to the base that answered', () async {
      door.dead.add('blocked.test');
      await start(bases: ['https://blocked.test', 'https://door.test']).check();
      expect(
        offer()!.release.url,
        'https://door.test/dl/ShikooNet-1.0.57-arm64-v8a.apk',
      );
    });

    test('a file on another door, or over http from an https door, is not '
        'offered', () async {
      for (final elsewhere in [
        'https://elsewhere.test/dl/ShikooNet-1.0.57-arm64-v8a.apk',
        'http://door.test/dl/ShikooNet-1.0.57-arm64-v8a.apk',
        'http://door.test:443/dl/ShikooNet-1.0.57-arm64-v8a.apk',
        'https://door.test:8443/dl/ShikooNet-1.0.57-arm64-v8a.apk',
      ]) {
        door.url = elsewhere;
        await start(bases: ['https://door.test']).check();
        expect(offer(), isNull, reason: elsewhere);
      }
      door.url = 'https://door.test/dl/ShikooNet-1.0.57-arm64-v8a.apk';
      await start(bases: ['https://door.test']).check();
      expect(offer()!.release.url, door.url);
    });

    test('checkNow does not wait out the six hours, and says whether the '
        'door answered', () async {
      final update = start();
      await update.check();
      expect(door.checks, 1);
      expect(await update.checkNow(), isNull);
      expect(door.checks, 2);
      door.dead.add('door.test');
      expect(await update.checkNow(), UpdateError.network);
      expect(door.checks, 3);
    });

    test('asks once in six hours, and again soon after a failure', () async {
      final update = start();
      door.dead.add('door.test');
      await update.check();
      expect(door.checks, 1);
      await update.check();
      expect(door.checks, 2);

      door.dead.clear();
      await update.check();
      expect(door.checks, 3);
      clock = clock.add(const Duration(hours: 5, minutes: 59));
      await update.check();
      expect(door.checks, 3);
      clock = clock.add(const Duration(minutes: 1));
      await update.check();
      expect(door.checks, 4);
    });

    test(
      'with the window closed it asks once in six hours, and after a '
      'failure once in 15 minutes; an open window asks again at once',
      () async {
        const minute = Duration(minutes: 1);
        const retry = Duration(minutes: 15);
        final update = start();
        await update.check(hidden: true);
        expect(door.checks, 1);
        clock = clock.add(const Duration(hours: 5, minutes: 59));
        await update.check(hidden: true);
        expect(door.checks, 1);

        clock = clock.add(minute);
        door.dead.add('door.test');
        await update.check(hidden: true);
        expect(door.checks, 2);
        clock = clock.add(retry - minute);
        await update.check(hidden: true);
        expect(door.checks, 2);
        await update.check();
        expect(door.checks, 3);

        clock = clock.add(retry - minute);
        await update.check(hidden: true);
        expect(door.checks, 3);
        clock = clock.add(minute);
        await update.check(hidden: true);
        expect(door.checks, 4);
        door.dead.clear();
        clock = clock.add(retry);
        await update.check(hidden: true);
        expect(door.checks, 5);
        clock = clock.add(retry);
        await update.check(hidden: true);
        expect(door.checks, 5, reason: 'answered: six hours again');
      },
    );

    test('keeps this build\'s part and clears everything else', () async {
      final old = File('${cache.path}/update/old.apk');
      await old.create(recursive: true);
      await part().writeAsBytes(_apk.sublist(0, 3000));
      await start().check();
      expect(old.existsSync(), isFalse);
      expect(offer()!.received, 3000);

      await start(installed: 2057).check();
      expect(part().existsSync(), isFalse);
    });
  });

  group('download', () {
    test('downloads, verifies, and is ready to install', () async {
      final update = start();
      final phases = <UpdatePhase?>[];
      container.listen(
        shikooUpdateOfferProvider,
        (_, next) => phases.add(next?.phase),
      );
      await update.check();
      await update.download();
      expect(offer()!.phase, UpdatePhase.ready);
      expect(offer()!.error, isNull);
      expect(apk().readAsBytesSync(), _apk);
      expect(part().existsSync(), isFalse);
      expect(phases.toSet().toList(), [
        UpdatePhase.offered,
        UpdatePhase.downloading,
        UpdatePhase.ready,
      ]);
    });

    test('a 206 continues the part where it stopped', () async {
      await part().create(recursive: true);
      await part().writeAsBytes(_apk.sublist(0, 3000));
      final update = start();
      await update.check();
      await update.download();
      expect(
        door.downloads.single.headers[HttpHeaders.rangeHeader],
        'bytes=3000-',
      );
      expect(offer()!.phase, UpdatePhase.ready);
      expect(apk().readAsBytesSync(), _apk);
    });

    test('a 200 to a range starts the file over', () async {
      door.ranges = false;
      await part().create(recursive: true);
      await part().writeAsBytes(List.filled(3000, 0));
      final update = start();
      await update.check();
      await update.download();
      expect(offer()!.phase, UpdatePhase.ready);
      expect(apk().readAsBytesSync(), _apk);
    });

    test('a wrong checksum deletes the file and says so', () async {
      door.sha = 'ab' * 32;
      final update = start();
      await update.check();
      await update.download();
      expect(offer()!.phase, UpdatePhase.offered);
      expect(offer()!.error, UpdateError.checksum);
      expect(offer()!.received, 0);
      expect(cache.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('a dropped connection keeps the part for the next tap', () async {
      door.dropAt = 5000;
      final update = start();
      await update.check();
      await update.download();
      expect(offer()!.phase, UpdatePhase.offered);
      expect(offer()!.error, UpdateError.network);
      expect(offer()!.received, 5000);
      expect(part().lengthSync(), 5000);

      door.dropAt = null;
      await update.download();
      expect(
        door.downloads.last.headers[HttpHeaders.rangeHeader],
        'bytes=5000-',
      );
      expect(offer()!.phase, UpdatePhase.ready);
      expect(offer()!.error, isNull);
    });

    test('cancel stops where it is, and the next tap continues', () async {
      door.holdAt = 6000;
      final update = start();
      await update.check();
      final written = Completer<void>();
      container.listen(shikooUpdateOfferProvider, (_, next) {
        if (next!.received == 6000 && !written.isCompleted) written.complete();
      });
      final running = update.download();
      await written.future;
      expect(offer()!.phase, UpdatePhase.downloading);
      await update.cancel();
      await running;
      expect(offer()!.phase, UpdatePhase.offered);
      expect(offer()!.error, isNull);
      expect(offer()!.received, 6000);
      expect(part().lengthSync(), 6000);

      door.holdAt = null;
      await update.download();
      expect(
        door.downloads.last.headers[HttpHeaders.rangeHeader],
        'bytes=6000-',
      );
      expect(offer()!.phase, UpdatePhase.ready);
      expect(apk().readAsBytesSync(), _apk);
    });

    test('a full disk says so and keeps the part', () async {
      await Link(part().path).create('/dev/full', recursive: true);
      final update = start();
      await update.check();
      await update.download();
      expect(offer()!.phase, UpdatePhase.offered);
      expect(offer()!.error, UpdateError.noSpace);
      expect(Link(part().path).existsSync(), isTrue);
    }, skip: !File('/dev/full').existsSync());
  });

  group('an expired certificate', () {
    const years14 = Duration(days: 14 * 365);
    setUp(() {
      // The test binding answers every real request 400; clockFailed's plain request must reach the door.
      final mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = mocked);
    });
    tearDown(() => shikooSkew = Duration.zero);

    test('fails a check as the clock when the door\'s own clock is 14 years '
        'off, and as the network when it agrees', () async {
      door.refusedFor = 'certificate has expired';
      for (final (off, error) in [
        (years14, UpdateError.clock),
        (-years14, UpdateError.clock),
        (Duration.zero, UpdateError.network),
      ]) {
        final plain = await _plainDoor(DateTime.now().add(off));
        expect(await start(bases: [plain]).checkNow(), error, reason: '$off');
        expect(offer(), isNull);
      }
    });

    test('fails a download the same way, and the next tap continues', () async {
      for (final (off, error) in [
        (years14, UpdateError.clock),
        (Duration.zero, UpdateError.network),
      ]) {
        final update = start(
          bases: [await _plainDoor(DateTime.now().add(off))],
        );
        door.refusedFor = null;
        await update.check();
        door.refusedFor = 'certificate has expired';
        await update.download();
        expect(offer()!.phase, UpdatePhase.offered, reason: '$off');
        expect(offer()!.error, error, reason: '$off');

        door.refusedFor = null;
        await update.download();
        expect(offer()!.phase, UpdatePhase.ready);
        expect(offer()!.error, isNull);
        apk().deleteSync();
      }
    });
  });

  group('install', () {
    Future<ShikooUpdate> ready() async {
      final update = start();
      await update.check();
      await update.download();
      return update;
    }

    test('asks for the permission, then installs on the way back', () async {
      canInstall = false;
      final update = await ready();
      expect(await update.install(), InstallAsk.thisApp);
      expect(offer()!.phase, UpdatePhase.ready);
      expect(native.map((c) => c.method), isNot(contains('install')));

      await update.allow();
      expect(native.last.method, 'openInstallSettings');
      await update.onForeground();
      expect(native.map((c) => c.method), isNot(contains('install')));

      await update.allow();
      canInstall = true;
      await update.onForeground();
      expect(native.last.method, 'install');
      expect(native.last.arguments, apk().path);
      expect(offer()!.phase, UpdatePhase.ready);
    });

    test(
      'without the settings page it goes straight to the installer',
      () async {
        canInstall = false;
        hasSettings = false;
        final update = await ready();
        expect(await update.install(), InstallAsk.thisApp);
        await update.allow();
        expect(native.last.method, 'install');
        expect(offer()!.error, isNull);
      },
    );

    test(
      'an installer that did not open says so until the next install',
      () async {
        final update = await ready();
        installerOpens = false;
        expect(await update.install(), InstallAsk.nothing);
        expect(offer()!.phase, UpdatePhase.ready);
        expect(offer()!.error, UpdateError.install);

        canInstall = false;
        expect(await update.install(), InstallAsk.thisApp);
        expect(offer()!.error, isNull);
      },
    );

    test('Android 7 asks for Unknown sources on its security page, then '
        'installs on the way back', () async {
      canInstall = false;
      final update = start(sdk: 25);
      await update.check();
      await update.download();
      expect(await update.install(), InstallAsk.unknownSources);
      await update.allow();
      expect(native.last.method, 'openInstallSettings');
      canInstall = true;
      await update.onForeground();
      expect(native.last.method, 'install');
    });

    test('Android 8 (API 26) already asks per app', () async {
      canInstall = false;
      final update = start(sdk: 26);
      await update.check();
      await update.download();
      expect(await update.install(), InstallAsk.thisApp);
    });

    test('an apk the system cleared is downloaded again', () async {
      final update = await ready();
      await apk().delete();
      expect(await update.install(), InstallAsk.nothing);
      expect(offer()!.phase, UpdatePhase.offered);
      expect(native.map((c) => c.method), isNot(contains('install')));
    });
  });

  test('the pinned keys are the Android signing keys, each on its own '
      'door', () {
    String spki(String key) => '${sha256.convert(base64.decode(key))}';
    expect(
      spki(windowsSealKeyProduction),
      '429266157daac075aff8ee48280015479b62a8cb481cb2f216b5b54295fa3813',
    );
    expect(
      spki(windowsSealKeyStaging),
      '6ccafa8996adb23850ffcec057ea17247a908ebce7f5c5e064d1adaef7550e46',
    );
    expect(sealKeyFor(testDoor: false), windowsSealKeyProduction);
    expect(sealKeyFor(testDoor: true), windowsSealKeyStaging);
    final built = ProviderContainer();
    addTearDown(built.dispose);
    expect(
      built.read(shikooUpdateProvider).sealKey,
      windowsSealKeyProduction,
      reason: 'flutter test passes no SHIKOO_API',
    );
  });

  group('windows', () {
    const windows = 'windows-x64';
    final message = _message(56, _sha);

    File exe() => File('${cache.path}/update/$_sha.exe');

    setUp(() {
      door
        ..abi = windows
        ..code = 56
        ..minimum = 0
        ..entryVersion = '1.0.56'
        ..sig = _sealOf(windowsSealKeyStaging, message)
        ..others = {
          'arm64-v8a': {
            'version_code': 57,
            'min_version_code': 57,
            'size': 1,
            'sha256': 'ab' * 32,
            'url': '/dl/ShikooNet-1.0.57-arm64-v8a.apk',
          },
        };
    });

    ShikooUpdate onWindows({int installed = 55}) =>
        start(abi: windows, installed: installed);

    test('offers its own entry under its own version name, sealed over its '
        'number and checksum', () async {
      await onWindows().check();
      expect(offer()!.release.versionName, '1.0.56');
      expect(offer()!.release.versionCode, 56);
      expect(offer()!.forced, isFalse);
      expect(
        offer()!.release.url,
        'http://door.test/dl/ShikooNet-1.0.57-windows-x64.exe',
      );
      expect(seals, [message]);
    });

    test(
      'a manifest without its own name falls back to the one above',
      () async {
        door.entryVersion = null;
        await onWindows().check();
        expect(offer()!.release.versionName, '1.0.57');
      },
    );

    test('a seal that is missing, wrong, unprefixed or made for another '
        'number or file is never offered, forced or not', () async {
      door.minimum = 56;
      for (final sig in [
        null,
        _sealOf(windowsSealKeyStaging, _message(57, _sha)),
        _sealOf(windowsSealKeyStaging, _message(56, 'ab' * 32)),
        _sealOf(windowsSealKeyStaging, '56:$_sha'),
        'x' * 344,
      ]) {
        door.sig = sig;
        expect(await onWindows().checkNow(), isNull, reason: '$sig');
        expect(offer(), isNull, reason: '$sig');
      }
      expect(diag.lines.toSet(), {'T update 56 not sealed'});
      door.sig = _sealOf(windowsSealKeyStaging, message);
      await onWindows().check();
      expect(offer()!.forced, isTrue);
    });

    test('the production seal never passes on a staging build, nor the other '
        'way', () async {
      door.sig = _sealOf(windowsSealKeyProduction, message);
      await onWindows().check();
      expect(offer(), isNull);

      door.sig = _sealOf(windowsSealKeyStaging, message);
      await (onWindows()..sealKey = windowsSealKeyProduction).check();
      expect(offer(), isNull);

      door.sig = _sealOf(windowsSealKeyProduction, message);
      await (onWindows()..sealKey = windowsSealKeyProduction).check();
      expect(offer()!.release.versionCode, 56);
    });

    test(
      'a core that does not answer is a failed check, asked again soon',
      () async {
        coreAnswers = null;
        final update = onWindows();
        expect(await update.checkNow(), UpdateError.network);
        expect(offer(), isNull);
        coreAnswers = true;
        await update.check();
        expect(offer()!.release.versionCode, 56);
      },
    );

    test('the installed build or a newer one asks the core nothing', () async {
      for (final installed in [56, 57, 2026091401]) {
        await onWindows(installed: installed).check();
        expect(offer(), isNull, reason: '$installed');
      }
      expect(seals, isEmpty);
    });

    test('a file on another door is not offered', () async {
      door.url = 'http://elsewhere.test/dl/ShikooNet-1.0.56-windows-x64.exe';
      await onWindows().check();
      expect(offer(), isNull);
    });

    test('a download continues its part, and the finished .exe stays ready '
        'across checks', () async {
      await part().create(recursive: true);
      await part().writeAsBytes(_apk.sublist(0, 3000));
      final update = onWindows();
      await update.check();
      await update.download();
      expect(
        door.downloads.single.headers[HttpHeaders.rangeHeader],
        'bytes=3000-',
      );
      expect(exe().readAsBytesSync(), _apk);

      clock = clock.add(updateEvery);
      await update.check();
      expect(exe().existsSync(), isTrue);
      expect(offer()!.phase, UpdatePhase.ready);
    });

    Future<ShikooUpdate> ready({bool connected = true}) async {
      final update = onWindows();
      await update.check();
      await update.download();
      if (connected) container.read(runTimeProvider.notifier).value = 1;
      return update;
    }

    test('checks the seal while connected, then disconnects and starts the '
        'quiet installer, never the Android permission', () async {
      final update = await ready();
      final installing = update.install();
      await until(() => started.isNotEmpty);
      expect(events, ['disconnect', 'start']);
      expect(started.single, [
        exe().path,
        '/SILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
      ]);
      expect(seals, [message, message]);
      expect(native, isEmpty);
      installer.exited.complete(0);
      expect(await installing, InstallAsk.nothing);
    });

    void afterDisconnect(void Function() then) {
      final controller =
          container.read(shikooControllerProvider) as _Controller;
      final cleared = controller.onDisconnect;
      controller.onDisconnect = () {
        cleared();
        then();
      };
    }

    test('a file swapped while disconnecting is deleted, never started, and '
        'the connection comes back', () async {
      final update = await ready();
      afterDisconnect(
        () => exe().writeAsBytesSync(utf8.encode('not the sealed file')),
      );
      await update.install();
      expect(events, ['disconnect', 'connect again']);
      expect(started, isEmpty);
      expect(exe().existsSync(), isFalse);
      expect(offer()!.phase, UpdatePhase.offered);
      expect(offer()!.error, UpdateError.checksum);
    });

    test('a file gone or unreadable after the disconnect is a damaged one: the '
        'connection comes back and the card says so', () async {
      for (final unreadable in [false, true]) {
        events.clear();
        final update = await ready();
        afterDisconnect(() {
          exe().deleteSync();
          // A directory in its place: no system reads it or deletes it as a file.
          if (unreadable) Directory(exe().path).createSync();
        });
        await update.install();
        expect(events, ['disconnect', 'connect again'], reason: '$unreadable');
        expect(started, isEmpty);
        expect(offer()!.phase, UpdatePhase.offered);
        expect(offer()!.error, UpdateError.checksum);
      }
    });

    test('a file another program holds locked, as an antivirus may, is the '
        'same, and stays where it is', () async {
      final update = await ready();
      RandomAccessFile? held;
      addTearDown(() => held?.closeSync());
      afterDisconnect(
        () =>
            held = exe().openSync(mode: FileMode.append)
              ..lockSync(FileLock.exclusive),
      );
      await update.install();
      expect(events, ['disconnect', 'connect again']);
      expect(started, isEmpty);
      expect(exe().existsSync(), isTrue);
      expect(offer()!.error, UpdateError.checksum);
    }, skip: Platform.isWindows ? false : 'only Windows locks block reads');

    test('the file is started in the turn it was hashed in, so a write '
        'queued during the disconnect lands only after the start', () async {
      final update = await ready();
      final swapped = Completer<void>();
      afterDisconnect(
        () => Timer.run(() {
          exe().writeAsBytesSync(utf8.encode('swapped'));
          swapped.complete();
        }),
      );
      final startedSha = <String>[];
      final start = update.startInstaller;
      update.startInstaller = (exe, arguments) {
        startedSha.add('${sha256.convert(File(exe).readAsBytesSync())}');
        return start(exe, arguments);
      };
      final installing = update.install();
      await until(() => started.isNotEmpty);
      expect(startedSha, [_sha]);
      installer.exited.complete(1);
      await installing;
      // A busy machine can poll the start before the write's turn; tearDown must not delete under it.
      await swapped.future;
    });

    test(
      'a file changed before the install is deleted, with no disconnect',
      () async {
        final update = await ready();
        exe().writeAsBytesSync([..._apk.sublist(0, _apk.length - 1), 0]);
        await update.install();
        expect(events, isEmpty);
        expect(exe().existsSync(), isFalse);
        expect(offer()!.error, UpdateError.checksum);
      },
    );

    test('a file gone when the install is tapped is a damaged one, with no '
        'disconnect', () async {
      final update = await ready();
      exe().deleteSync();
      await update.install();
      expect(events, isEmpty);
      expect(started, isEmpty);
      expect(offer()!.phase, UpdatePhase.offered);
      expect(offer()!.error, UpdateError.checksum);
    });

    test('one locked when the install is tapped is the same, and stays where '
        'it is', () async {
      final update = await ready();
      final held = exe().openSync(mode: FileMode.append)
        ..lockSync(FileLock.exclusive);
      addTearDown(held.closeSync);
      await update.install();
      expect(events, isEmpty);
      expect(started, isEmpty);
      expect(exe().existsSync(), isTrue);
      expect(offer()!.phase, UpdatePhase.offered);
      expect(offer()!.error, UpdateError.checksum);
    }, skip: Platform.isWindows ? false : 'only Windows locks block reads');

    test('a seal the core no longer confirms keeps the connection and starts '
        'nothing', () async {
      final update = await ready();
      coreAnswers = null;
      await update.install();
      expect(events, isEmpty);
      expect(offer()!.phase, UpdatePhase.ready);
      expect(offer()!.error, UpdateError.install);
    });

    test('an installer that exits while the app lives, refused at UAC, '
        'reconnects and says the installer did not open', () async {
      final update = await ready();
      final installing = update.install();
      await until(() => started.isNotEmpty);
      installer.exited.complete(2);
      await installing;
      expect(events, ['disconnect', 'start', 'connect again']);
      expect(offer()!.phase, UpdatePhase.ready);
      expect(offer()!.error, UpdateError.install);
    });

    test('one Windows would not start is the same', () async {
      startFails = true;
      final update = await ready();
      await update.install();
      expect(events, ['disconnect', 'start', 'connect again']);
      expect(offer()!.error, UpdateError.install);
    });

    test('only a connection that was on comes back, and not over one the '
        'user started since', () async {
      startFails = true;
      await (await ready(connected: false)).install();
      expect(events, ['disconnect', 'start']);

      events.clear();
      final update = await ready();
      final controller =
          container.read(shikooControllerProvider) as _Controller;
      controller.onDisconnect = () {};
      await update.install();
      expect(events, ['disconnect', 'start']);
    });

    test('a second tap while installing starts nothing more', () async {
      final update = await ready();
      final first = update.install();
      final second = update.install();
      await until(() => started.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      installer.exited.complete(1);
      await Future.wait([first, second]);
      expect(started, hasLength(1));
    });
  });
}
