import 'dart:async';
import 'dart:io';

import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rust_api/rust_api.dart';

/// The Shikoo entry point, built with `-t lib/shikoo/main.dart`. It repeats FlClash's
/// `lib/main.dart` (v0.8.98) with ShikooApp in place of FlClash's Application; copy upstream
/// changes to that file here by hand.
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
        final container = await bootstrap.init(version);
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

/// FlClash prints every url it fetches, subscription tokens included, and logcat keeps it
/// (`find <url> proxy:` in lib/common/http.dart). Everything printed passes through
/// [debugPrint], so links are masked here without touching FlClash.
void _hideLinksInLogs() {
  final print = debugPrint;
  final link = RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false);
  debugPrint = (message, {wrapWidth}) =>
      print(message?.replaceAll(link, '<link>'), wrapWidth: wrapWidth);
}
