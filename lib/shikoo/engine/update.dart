import 'dart:async';
import 'dart:convert' show ChunkedConversionSink;
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:fl_clash/providers/providers.dart'
    show coreHandlerProvider, runTimeProvider, versionProvider;
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart' show clockFailed;
import 'package:fl_clash/shikoo/engine/controller.dart'
    show ShikooCell, shikooControllerProvider;
import 'package:fl_clash/shikoo/engine/diag.dart' show shikooDiagProvider;
import 'package:fl_clash/shikoo/engine/ping.dart' show isDue;
import 'package:fl_clash/shikoo/engine/settings.dart' show shikooTestDoor;
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const updateEvery = Duration(hours: 6);

/// With the window closed nobody waits on the answer: a failed check is tried again after this, not every minute.
const hiddenRetryEvery = Duration(minutes: 15);

@visibleForTesting
String sealKeyFor({required bool testDoor}) =>
    testDoor ? windowsSealKeyStaging : windowsSealKeyProduction;

const _abiNames = {
  Abi.androidArm: 'armeabi-v7a',
  Abi.androidArm64: 'arm64-v8a',
  Abi.androidX64: 'x86_64',
  Abi.windowsX64: 'windows-x64',
};

enum UpdatePhase { offered, downloading, ready }

/// [clock]: TLS refused the door for this device's clock, as `clockFailed` judges it.
enum UpdateError { network, checksum, noSpace, install, clock }

/// What Android still needs before installing: this app's own permission (8 and up), or
/// Unknown sources for every app (7).
enum InstallAsk { nothing, thisApp, unknownSources }

@immutable
class UpdateOffer {
  const UpdateOffer(
    this.release, {
    this.forced = false,
    this.phase = UpdatePhase.offered,
    this.received = 0,
    this.error,
  });

  final AppRelease release;

  /// The installed build is below the door's minimum: nothing else until it updates.
  final bool forced;
  final UpdatePhase phase;

  /// Bytes on disk; above 0 while [UpdatePhase.offered], a download continues from here.
  final int received;
  final UpdateError? error;

  int get percent => (received * 100 ~/ release.size).clamp(0, 100);
}

/// Null when the installed build is the newest, or nothing is known yet.
final shikooUpdateOfferProvider =
    NotifierProvider<ShikooCell<UpdateOffer?>, UpdateOffer?>(
      () => ShikooCell(null),
    );

final shikooUpdateProvider = Provider<ShikooUpdate>(ShikooUpdate.new);

/// A top-level function, so the isolate gets only the path and not the engine around it.
/// Not `openRead`: a failed read there never closes the file (`_FileStream._closeFile` while `_readInProgress`).
Future<String> _sha256Of(String path) => Isolate.run(() {
  late Digest digest;
  final hash = sha256.startChunkedConversion(
    ChunkedConversionSink.withCallback((digests) => digest = digests.single),
  );
  final file = File(path).openSync();
  try {
    for (
      var chunk = file.readSync(1 << 16);
      chunk.isNotEmpty;
      chunk = file.readSync(1 << 16)
    ) {
      hash.add(chunk);
    }
  } finally {
    file.closeSync();
  }
  hash.close();
  return '$digest';
});

class ShikooUpdate {
  ShikooUpdate(this._ref);

  final Ref _ref;
  static const _channel = MethodChannel('shikoo/update');

  /// The running process's ABI: a 32-bit build on a 64-bit phone stays 32-bit.
  @visibleForTesting
  late String abi = _abiNames[Abi.current()] ?? '';

  /// Its versionCode; a local build's (2026091401 and up) is above every release's.
  @visibleForTesting
  late int installed = int.tryParse(globalState.packageInfo.buildNumber) ?? 0;

  @visibleForTesting
  Future<Directory> Function() cacheDir = getApplicationCacheDirectory;

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  @visibleForTesting
  String sealKey = sealKeyFor(testDoor: shikooTestDoor);

  @visibleForTesting
  late Future<bool?> Function(String key, String message, String sig)
  checkSeal = _ref.read(coreHandlerProvider).checkSeal;

  @visibleForTesting
  Future<Process> Function(String exe, List<String> arguments) startInstaller =
      (exe, arguments) =>
          Process.start(exe, arguments, mode: ProcessStartMode.inheritStdio);

  DateTime? _checked;
  DateTime? _asked;
  Future<UpdateError?>? _checking;
  Future<void>? _downloading;
  Future<void>? _installing;
  CancelToken? _cancel;
  bool _awaitingPermission = false;

  ShikooApi get _api => _ref.read(shikooApiProvider);

  bool get _windows => abi.startsWith('windows-');

  UpdateOffer? get _offer => _ref.read(shikooUpdateOfferProvider);

  void _show(UpdateOffer? offer) =>
      _ref.read(shikooUpdateOfferProvider.notifier).set(offer);

  void _move(UpdatePhase phase, {int? received, UpdateError? error}) {
    final offer = _offer;
    if (offer == null) return;
    _show(
      UpdateOffer(
        offer.release,
        forced: offer.forced,
        phase: phase,
        received: received ?? offer.received,
        error: error,
      ),
    );
  }

  Future<Directory> _dir() async =>
      Directory('${(await cacheDir()).path}/update').create(recursive: true);

  /// `res/xml/update_paths.xml` shares `<cache>/update/` with the installer.
  File _part(Directory dir, AppRelease release) =>
      File('${dir.path}/${release.sha256}.part');

  File _installer(Directory dir, AppRelease release) =>
      File('${dir.path}/${release.sha256}.${_windows ? 'exe' : 'apk'}');

  /// Start and resume. Back from Android's install permission page, installs if it was given.
  Future<void> onForeground() async {
    if (_awaitingPermission) {
      _awaitingPermission = false;
      if (await _native('canInstall')) await _launch();
    }
    await check();
  }

  /// [hidden]: the window is closed, so a failure waits [hiddenRetryEvery].
  Future<void> check({bool hidden = false}) async {
    if (!isDue(_checked, now(), updateEvery)) return;
    if (hidden && !isDue(_asked, now(), hiddenRetryEvery)) return;
    await checkNow();
  }

  /// Settings' «بررسی به‌روزرسانی», past [updateEvery]; null once the door answered.
  Future<UpdateError?> checkNow() =>
      _checking ??= _check().whenComplete(() => _checking = null);

  Future<UpdateError?> _check() async {
    _asked = now();
    AppRelease? release;
    try {
      release = await _api.update(abi);
    } catch (error) {
      return error is ShikooApiFailure && error.clock
          ? UpdateError.clock
          : UpdateError.network;
    }
    // Not offered, so never forced: an unsigned build would hold every Windows user on the forced page.
    if (_windows && release != null && installed < release.versionCode) {
      final sealed = await _sealed(release);
      if (sealed == null) return UpdateError.network;
      if (!sealed) {
        _ref
            .read(shikooDiagProvider)
            .add('T', 'update ${release.versionCode} not sealed');
        release = null;
      }
    }
    _checked = now();
    await _take(release);
    return null;
  }

  Future<bool?> _sealed(AppRelease release) async {
    final sig = release.sig;
    if (sig == null) return false;
    try {
      return await checkSeal(
        sealKey,
        'shikoonet-windows-update:${release.versionCode}:${release.sha256}',
        sig,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _take(AppRelease? release) async {
    final newer = release != null && installed < release.versionCode
        ? release
        : null;
    final dir = await _dir();
    final keep = {
      if (newer != null)
        for (final file in [_part(dir, newer), _installer(dir, newer)])
          p.basename(file.path),
    };
    try {
      await for (final file in dir.list()) {
        if (!keep.contains(p.basename(file.path))) {
          await file.delete(recursive: true);
        }
      }
    } on FileSystemException {
      // ponytail: a file that would not go is tried again at the next check.
    }
    if (newer == null) return _show(null);
    final forced = installed < newer.minVersionCode;
    final current = _offer;
    if (current != null && current.release.sha256 == newer.sha256) {
      return _show(
        UpdateOffer(
          newer,
          forced: forced,
          phase: current.phase,
          received: current.received,
          error: current.error,
        ),
      );
    }
    final part = _part(dir, newer);
    _show(
      await _installer(dir, newer).exists()
          ? UpdateOffer(
              newer,
              forced: forced,
              phase: UpdatePhase.ready,
              received: newer.size,
            )
          : UpdateOffer(
              newer,
              forced: forced,
              received: await part.exists() ? await part.length() : 0,
            ),
    );
  }

  Future<void> download() =>
      _downloading ??= _download().whenComplete(() => _downloading = null);

  Future<void> _download() async {
    final offer = _offer;
    if (offer == null || offer.phase != UpdatePhase.offered) return;
    final release = offer.release;
    bool stale() => _offer?.release.sha256 != release.sha256;
    final cancel = _cancel = CancelToken();
    final dir = await _dir();
    final part = _part(dir, release);
    try {
      var have = await part.exists() ? await part.length() : 0;
      if (have > release.size) {
        await part.delete();
        have = 0;
      }
      _move(UpdatePhase.downloading, received: have);
      if (have < release.size) await _fetch(release, part, have, cancel, stale);
      if (stale()) return;
      final digest = await _sha256Of(part.path);
      if (stale()) return;
      if (digest != release.sha256) {
        await part.delete();
        return _move(
          UpdatePhase.offered,
          received: 0,
          error: UpdateError.checksum,
        );
      }
      await part.rename(_installer(dir, release).path);
      _move(UpdatePhase.ready);
    } catch (error) {
      final clock =
          !cancel.isCancelled && await clockFailed(error, release.url);
      if (stale()) return;
      final noSpace =
          error is FileSystemException && error.osError?.errorCode == 28;
      var kept = 0;
      try {
        if (await part.exists()) kept = await part.length();
      } on FileSystemException catch (_) {}
      _move(
        UpdatePhase.offered,
        received: kept,
        error: cancel.isCancelled
            ? null
            : noSpace
            ? UpdateError.noSpace
            : clock
            ? UpdateError.clock
            : UpdateError.network,
      );
    }
  }

  Future<void> _fetch(
    AppRelease release,
    File part,
    int have,
    CancelToken cancel,
    bool Function() stale,
  ) async {
    final response = await _api.download(release.url, have, cancel);
    final status = response.statusCode;
    final resumed =
        status == 206 &&
        (response.headers
                .value(HttpHeaders.contentRangeHeader)
                ?.startsWith('bytes $have-') ??
            false);
    if (status != 200 && !resumed) {
      await response.data?.stream.listen(null).cancel();
      // A range the door cannot serve means the part is not a prefix of its file.
      if (status == 206 || status == 416) await part.delete();
      throw const ShikooApiFailure();
    }
    var received = resumed ? have : 0;
    final file = await part.open(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response.data!.stream) {
        if (stale()) return;
        received += chunk.length;
        if (received > release.size) throw const ShikooApiFailure();
        await file.writeFrom(chunk);
        if (received * 100 ~/ release.size != _offer!.percent) {
          _move(UpdatePhase.downloading, received: received);
        }
      }
    } finally {
      await file.close();
    }
    if (received < release.size) throw const ShikooApiFailure();
  }

  Future<void> cancel() async {
    _cancel?.cancel();
    await _downloading;
  }

  /// Anything but [InstallAsk.nothing]: the screen explains that, then [allow].
  Future<InstallAsk> install() async {
    if (_offer?.phase != UpdatePhase.ready) return InstallAsk.nothing;
    _move(UpdatePhase.ready);
    if (!_windows && !await _native('canInstall')) {
      return _ref.read(versionProvider) < 26
          ? InstallAsk.unknownSources
          : InstallAsk.thisApp;
    }
    await _launch();
    return InstallAsk.nothing;
  }

  Future<void> allow() async {
    if (_offer?.phase != UpdatePhase.ready) return;
    _awaitingPermission = true;
    if (await _native('openInstallSettings')) return;
    _awaitingPermission = false;
    await _launch();
  }

  /// Installing ends this process and its VPN; the app comes back off.
  Future<void> _launch() async {
    final offer = _offer;
    if (offer == null) return;
    final release = offer.release;
    final file = _installer(await _dir(), release);
    // Android empties the cache directory when storage runs low.
    if (!_windows && !await file.exists()) {
      return _move(UpdatePhase.offered, received: 0);
    }
    if (!_windows) {
      final opened = await _native('install', file.path);
      return _move(
        UpdatePhase.ready,
        error: opened ? null : UpdateError.install,
      );
    }
    return _installing ??= _installWindows(
      file,
      release,
    ).whenComplete(() => _installing = null);
  }

  Future<void> _installWindows(File file, AppRelease release) async {
    void damaged() {
      try {
        file.deleteSync();
      } on FileSystemException catch (_) {}
      _move(UpdatePhase.offered, received: 0, error: UpdateError.checksum);
    }

    if (await _sha256Of(file.path).catchError((_) => '') != release.sha256) {
      return damaged();
    }
    if (await _sealed(release) != true) {
      return _move(UpdatePhase.ready, error: UpdateError.install);
    }
    final wasOn = _ref.read(runTimeProvider) != null;
    final controller = _ref.read(shikooControllerProvider);
    await controller.disconnect();
    var same = false;
    // Hashed and started in one turn. PrepareToInstall kills this app: an exit seen here means it never installed.
    try {
      same = '${sha256.convert(file.readAsBytesSync())}' == release.sha256;
      if (same) {
        await (await startInstaller(file.path, [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
        ])).exitCode;
      }
    } catch (_) {}
    if (wasOn && _ref.read(runTimeProvider) == null) {
      unawaited(controller.connectAgain());
    }
    if (!same) return damaged();
    _move(UpdatePhase.ready, error: UpdateError.install);
  }

  Future<bool> _native(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } catch (_) {
      return false;
    }
  }
}

// dart format off
/// Base64 SubjectPublicKeyInfo of the Android signing keys, `CN=ShikooNet` and `CN=ShikooNet Staging`; CI greps these two lines.
const windowsSealKeyProduction = 'MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAvz9upEmGJR+ztlRWX0Dxic10CU995o1UtojYE4T6JwmbkyxHFn7m53kJsUNpY+69n1WmN8GprvH67tZPfizJL9GjR42tXY9qt6UdBzOaSb1EcRzYVvPMdjPO6fb5tuwSikm+UrmO1ry+6KeYqIx5pcpfpIFUCZe9u6QYxCREVGY4AgrZ7KKMVSvK5B1AmwAFHw87gq8863wka28oBtr6GU9NW4ruC/iwQ3B/200AT67uY9qM7XNVQmtsqzt1AncCr65xZ20l+GlVr8+Mq2lZkl95SxIgpCE6cwk/k4NtMeuJyV3PFtKEUbyZSa6jvD11garS5GL/Fgx17c81tPkDQ675ODVAvDN3WIX/Lc2O0xJBrw2FFwchPLtXCnx6d4kqtEderugOnzkJy1kOaDmWNYcbAO5eOPtQUJnrpTV6mlS+qKYsnjlnCfKUxQ7y7AEuvEWFq5vrMpAcBWRIHgGZL8hy9p4q/UHTkZ7gxumYEDNlDViiCUGYodiwqEQ6WREjepFJf2Eze8LOC/EOtm9Jzg4kANjkwdcvcP0EdFPI4l3TxbpzZ3chX3JB0V+aTIHjpGq3U7UsR2oRPewiS9D5qvQPtiRQispHzR3W25y1CJU/JXVTsrUdWXPoYQeVC0O0zhF2IaU3X4sDLsz9jfchSasNt7BmHSuBGr1ap1QRi80CAwEAAQ==';
const windowsSealKeyStaging = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyrjHPpyE7NsQHBPbefTqkO29s35v7M5HcV74NYA4DIBwgd3BVB/OS3NKh4akrtb+iB9uhXosGz8fIjiQIxGnq2UXoC4e9IRxoMxN6zrH72onEcaW0UIPK+L3J5alHW+Avi3Bt6IXCF/lPITfw01DWBbUmQL5myAvBpazGEeDqYcuLRcG3YsZxFuHePO1xVZaSD4uQ3rS4iAHx1YhoJ2TvH7buF71B9wcQ0FDoszyZFhYo48J4+S4UmJAkM8nCJnmcwWWWsU2M/3kBkXuFuLtLa/bqBFlfS9nYrLJI7ajnEtRv8BVkw7wcDgdyn3zk4S59xC2O3idrBe9svrtDcvziQIDAQAB';
