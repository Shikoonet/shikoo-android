import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/providers/providers.dart' show versionProvider;
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart' show shikooSkew;
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

final _apk = Uint8List.fromList(List.generate(20000, (i) => i * 7 % 256));
final _sha = '${sha256.convert(_apk)}';

const _key = 'test-key';

/// Stands in for Ed25519, which the core's tests check against RFC 8032: only [_key] seals.
String _sealOf(String message) => 'seal($message)';

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
  late List<String> ran;
  late bool windowsStarts;

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
    ran = [];
    windowsStarts = true;
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
      ],
    );
    addTearDown(container.dispose);
    return container.read(shikooUpdateProvider)
      ..abi = abi
      ..installed = installed
      ..cacheDir = (() async => cache)
      ..now = (() => clock)
      ..sealKey = _key
      ..checkSeal = (key, message, sig) async {
        seals.add(message);
        return coreAnswers == null
            ? null
            : key == _key && sig == _sealOf(message);
      }
      ..runInstaller = (exe) async {
        ran.add(exe);
        return windowsStarts;
      };
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

  test('each build reads only its own entry', () {
    expect(abiNames, {
      Abi.androidArm: 'armeabi-v7a',
      Abi.androidArm64: 'arm64-v8a',
      Abi.androidX64: 'x86_64',
      Abi.windowsX64: 'windows-x64',
    });
    expect(abiNames[Abi.windowsArm64], isNull);
  });

  group('windows', () {
    const windows = 'windows-x64';
    final message = '56:$_sha';

    File exe() => File('${cache.path}/update/$_sha.exe');

    setUp(() {
      door
        ..abi = windows
        ..code = 56
        ..minimum = 0
        ..entryVersion = '1.0.56'
        ..sig = _sealOf(message)
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

    test('a seal that is missing, wrong or made for another number is never '
        'offered, forced or not', () async {
      door.minimum = 56;
      for (final sig in [null, 'seal(57:$_sha)', 'seal($_sha)', 'x' * 88]) {
        door.sig = sig;
        expect(await onWindows().checkNow(), isNull, reason: '$sig');
        expect(offer(), isNull, reason: '$sig');
      }
      door.sig = _sealOf(message);
      await onWindows().check();
      expect(offer()!.forced, isTrue);
    });

    test('without the real key nothing is offered, whatever the door '
        'signed', () async {
      final update = onWindows()..sealKey = windowsSealKey;
      await update.check();
      expect(windowsSealKey, isEmpty);
      expect(offer(), isNull);
      expect(seals, isEmpty);
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

    test('installs the checked file with no Android permission and no '
        'channel', () async {
      final update = onWindows();
      await update.check();
      await update.download();
      expect(await update.install(), InstallAsk.nothing);
      expect(ran, [exe().path]);
      expect(native, isEmpty);
      expect(offer()!.phase, UpdatePhase.ready);
      expect(offer()!.error, isNull);
      expect(seals, [message, message]);
    });

    test('a file changed after the download is deleted, never run', () async {
      final update = onWindows();
      await update.check();
      await update.download();
      exe().writeAsBytesSync([..._apk.sublist(0, 19999), 0]);
      await update.install();
      expect(ran, isEmpty);
      expect(exe().existsSync(), isFalse);
      expect(offer()!.phase, UpdatePhase.offered);
      expect(offer()!.error, UpdateError.checksum);
    });

    test('a seal the core no longer confirms, or an installer Windows would '
        'not start, says the installer did not open', () async {
      final update = onWindows();
      await update.check();
      await update.download();
      coreAnswers = null;
      await update.install();
      expect(ran, isEmpty);
      expect(offer()!.error, UpdateError.install);

      coreAnswers = true;
      windowsStarts = false;
      await update.install();
      expect(ran, [exe().path]);
      expect(offer()!.phase, UpdatePhase.ready);
      expect(offer()!.error, UpdateError.install);
    });
  });
}
