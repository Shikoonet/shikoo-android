import 'dart:async';
import 'dart:io';

import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/state.dart' show serviceTexts;
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rust_api/rust_api.dart';

/// FlClash's `lib/main.dart` (v0.8.98) with ShikooApp; copy upstream changes to it by hand.
void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _hideLinksInLogs();
      FlutterError.onError = (details) {
        Future.microtask(() {
          commonPrint.log(
            'exception: ${details.exception} stack: ${details.stack}',
            logLevel: LogLevel.warning,
          );
        });
      };
      try {
        await loadShikooFonts();
        await RustLib.init();
        final version = await system.init();
        if (clockTooEarly(DateTime.now())) await _untilClockRight();
        serviceTexts = shikooServiceTexts;
        final container = await bootstrap.init(version);
        await keepApiDirect();
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
        runApp(const ShikooInitErrorApp());
      }
    },
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

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
    ShikooClockApp(
      look: look,
      onRetry: () {
        if (!clockTooEarly(DateTime.now()) && !right.isCompleted) {
          right.complete();
        }
      },
    ),
  );
  await right.future;
}

/// FlClash logs every url it fetches, tokens included (`lib/common/http.dart:25`).
void _hideLinksInLogs() {
  final print = debugPrint;
  final link = RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false);
  debugPrint = (message, {wrapWidth}) =>
      print(message?.replaceAll(link, '<link>'), wrapWidth: wrapWidth);
}
