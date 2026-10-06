import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart' show ShikooCell;
import 'package:fl_clash/shikoo/engine/ping.dart' show isDue;
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

const updateEvery = Duration(hours: 6);

const _abiNames = {
  Abi.androidArm: 'armeabi-v7a',
  Abi.androidArm64: 'arm64-v8a',
  Abi.androidX64: 'x86_64',
  Abi.androidIA32: 'x86',
};

/// [permission]: Android must let this app install apps; [ShikooUpdate.allow] opens its page.
enum UpdatePhase { offered, downloading, verifying, ready, permission }

enum UpdateError { network, checksum, noSpace, install }

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
Future<String> _sha256Of(String path) => Isolate.run(
  () async => '${await sha256.bind(File(path).openRead()).first}',
);

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

  DateTime? _checked;
  Future<void>? _checking;
  Future<void>? _downloading;
  bool _awaitingPermission = false;

  ShikooApi get _api => _ref.read(shikooApiProvider);

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

  File _apk(Directory dir, AppRelease release) =>
      File('${dir.path}/${release.sha256}.apk');

  /// Start and resume. Back from Android's install permission page, installs if it was given.
  Future<void> onForeground() async {
    if (_awaitingPermission) {
      _awaitingPermission = false;
      if (await _native('canInstall')) await _launch();
    }
    await check();
  }

  Future<void> check() async {
    if (!isDue(_checked, now(), updateEvery)) return;
    return _checking ??= _check().whenComplete(() => _checking = null);
  }

  Future<void> _check() async {
    final AppRelease? release;
    try {
      release = await _api.update(abi);
    } catch (_) {
      return;
    }
    _checked = now();
    final newer = release != null && installed < release.versionCode
        ? release
        : null;
    final dir = await _dir();
    final keep = {
      if (newer != null) ...[_part(dir, newer).path, _apk(dir, newer).path],
    };
    try {
      await for (final file in dir.list()) {
        if (!keep.contains(file.path)) await file.delete(recursive: true);
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
      await _apk(dir, newer).exists()
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
    final dir = await _dir();
    final part = _part(dir, release);
    try {
      var have = await part.exists() ? await part.length() : 0;
      if (have > release.size) {
        await part.delete();
        have = 0;
      }
      _move(UpdatePhase.downloading, received: have);
      if (have < release.size) await _fetch(release, part, have, stale);
      if (stale()) return;
      _move(UpdatePhase.verifying);
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
      await part.rename(_apk(dir, release).path);
      _move(UpdatePhase.ready);
    } catch (error) {
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
        error: noSpace ? UpdateError.noSpace : UpdateError.network,
      );
    }
  }

  Future<void> _fetch(
    AppRelease release,
    File part,
    int have,
    bool Function() stale,
  ) async {
    final response = await _api.download(release.url, have);
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

  Future<void> install() async {
    final phase = _offer?.phase;
    if (phase != UpdatePhase.ready && phase != UpdatePhase.permission) return;
    if (!await _native('canInstall')) return _move(UpdatePhase.permission);
    await _launch();
  }

  /// A box without Android's page goes straight to the installer, which asks on its own.
  Future<void> allow() async {
    if (_offer?.phase != UpdatePhase.permission) return;
    _awaitingPermission = true;
    if (await _native('openInstallSettings')) return;
    _awaitingPermission = false;
    await _launch();
  }

  /// Installing ends this process and its VPN; the app comes back off.
  Future<void> _launch() async {
    final offer = _offer;
    if (offer == null) return;
    final apk = _apk(await _dir(), offer.release);
    // Android empties the cache directory when storage runs low.
    if (!await apk.exists()) return _move(UpdatePhase.offered, received: 0);
    final opened = await _native('install', apk.path);
    _move(UpdatePhase.ready, error: opened ? null : UpdateError.install);
  }

  Future<bool> _native(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } catch (_) {
      return false;
    }
  }
}
