import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/window.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/app/desktop.dart';
import 'package:fl_clash/shikoo/app/windows_proxy.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/ui/clock.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rust_api/rust_api.dart';

/// FlClash's `lib/main.dart` (v0.8.98) with ShikooApp; copy upstream changes to it by hand.
void main(List<String> args) {
  shikooAutostarted = args.contains(shikooAutostartArg);
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (Platform.isWindows && args.contains('--restore-proxy')) {
        await restoreProxyAndExit();
      }
      hideLinksInLogs();
      FlutterError.onError = (details) {
        shikooDiag.error(details.exception, details.stack);
        Future.microtask(() {
          commonPrint.log(
            'exception: ${details.exception} stack: ${details.stack}',
            logLevel: LogLevel.warning,
          );
        });
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        shikooDiag.error(error, stack);
        return false;
      };
      try {
        await shikooDiag.start(await appPath.homeDirPath);
        await loadShikooFonts();
        await RustLib.init();
        final version = await system.init();
        if (clockTooEarly(DateTime.now())) await _untilClockRight();
        fillFlClashHooks();
        await forgetUnfinishedLaunch();
        final container = await bootstrap.init(version);
        if (system.isWindows) await shikooWindowStart(container);
        shikooStaging =
            shikooStagingBuild ||
            globalState.packageInfo.packageName.endsWith('.dev');
        await keepApiDirect();
        await followSubscriptions(container);
        await container.read(shikooLookProvider.notifier).load();
        await container.read(shikooSignInProvider).load();
        HttpOverrides.global = FlClashHttpOverrides(container);
        request.attach(container.read);
        runApp(
          UncontrolledProviderScope(
            container: container,
            child: const ShikooApp(),
          ),
        );
      } catch (e, s) {
        commonPrint.log('init failed: $e $s', logLevel: LogLevel.error);
        shikooDiag.release();
        runApp(const ShikooInitErrorApp());
        unawaited(window?.showInitFailure());
      }
    },
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

/// Keeps FlClash's boot guard from its English dialogs and from dropping the service: below Android 11
/// any stop before `markRunning` counts as a crash. Real ones reach `ShikooDiag._offerCrash`.
Future<void> forgetUnfinishedLaunch() =>
    preferences.saveBootRecord(const BootRecord());

/// Before bootstrap: on Android the core loads only once Dart asks the service channel for it.
Future<void> _untilClockRight() async {
  commonPrint.log('clock before ${shikooClockFloor.year}: core held back');
  final looks = ProviderContainer();
  await looks.read(shikooLookProvider.notifier).load();
  final look = looks.read(shikooLookProvider);
  looks.dispose();
  if (system.isTV) {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  }
  final right = Completer<void>();
  runApp(
    bareApp(
      ClockPage(
        onRetry: () {
          if (clockTooEarly(DateTime.now())) return false;
          if (!right.isCompleted) right.complete();
          return true;
        },
      ),
      look: look,
    ),
  );
  // The desktop window shows itself only once bootstrap ran.
  unawaited(window?.showInitFailure());
  await right.future;
}

/// FlClash logs every url it fetches, tokens included (`lib/common/http.dart:25`).
@visibleForTesting
void hideLinksInLogs() {
  final print = debugPrint;
  final link = RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false);
  debugPrint = (message, {wrapWidth}) {
    if (message != null) shikooDiag.add('A', message);
    print(message?.replaceAll(link, '<link>'), wrapWidth: wrapWidth);
  };
}
