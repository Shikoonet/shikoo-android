import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

enum _Look { phone, tv, windows }

final _screen = GlobalKey();

/// As the sync leaves it: [status] is the panel's end, `active` with [loadFailed] a link that failed.
ShikooAccount _account(String status, {bool loadFailed = false}) =>
    ShikooAccount(
      who: const TelegramAccount(name: 'مریم'),
      bot: 'shikoonet_bot',
      services: [
        LinkedService(
          id: 41,
          title: 'user123 · OpenVPN',
          status: 'expired',
          expiresAt: DateTime.now().subtract(const Duration(days: 3)),
          renewable: false,
        ),
        LinkedService(
          id: 42,
          title: 'user456 · پاسارگاد',
          status: status,
          expiresAt: DateTime.now().add(const Duration(days: 20)),
          loadFailed: loadFailed,
          renewable: true,
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester,
  _Look look,
  ShikooAccount account, {
  required String locale,
  required Brightness brightness,
}) async {
  SharedPreferences.setMockInitialValues({});
  final tv = look == _Look.tv;
  tester.view
    ..physicalSize = switch (look) {
      _Look.phone => const Size(824, 1830),
      _Look.tv => const Size(1920, 1080),
      _Look.windows => const Size(1100, 760),
    }
    ..devicePixelRatio = look == _Look.windows ? 1 : 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooVersionProvider.overrideWithValue('1.0.0'),
        shikooAccountProvider.overrideWith(() => ShikooCell(account)),
        shikooStateProvider.overrideWithValue(
          ShikooState(
            connection: ShikooConnection.off,
            connectedFor: Duration.zero,
            isTV: tv,
            servers: const [],
          ),
        ),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(brightness, tv: tv),
        builder: (_, child) => RepaintBoundary(
          key: _screen,
          child: tv ? ShikooTvCanvas(child: child!) : child!,
        ),
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// With `SHIKOO_SHOTS=<folder>`, the screen as a PNG there.
Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SHIKOO_SHOTS'];
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screen),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _finished(
  WidgetTester tester,
  _Look look,
  String locale,
  Brightness brightness, {
  String status = 'exhausted',
}) async {
  await _pump(
    tester,
    look,
    _account(status),
    locale: locale,
    brightness: brightness,
  );
  final l = lookupShikooL10n(Locale(locale));
  final tv = look == _Look.tv;
  final used = status == 'exhausted';
  final summary = used
      ? (tv ? l.summaryExhaustedTv : l.summaryExhausted)
      : (tv ? l.summaryExpiredNoDateTv : l.summaryExpiredNoDate);
  final card = find
      .ancestor(of: find.text(summary), matching: find.byType(Column))
      .first;
  Finder inCard(Finder finder) => find.descendant(of: card, matching: finder);
  final why = '${look.name} $locale ${brightness.name} $status';
  expect(
    inCard(find.text(used ? l.stateExhausted : l.chipExpired)),
    findsOneWidget,
    reason: why,
  );
  for (final label in [l.renew, l.support]) {
    expect(
      inCard(find.widgetWithText(ShikooButton, label)),
      findsOneWidget,
      reason: '$label, $why',
    );
  }
  if (!tv) {
    expect(
      inCard(find.widgetWithText(ShikooButton, l.retry)),
      findsNothing,
      reason: why,
    );
  }
  expect(find.text(l.loadFailedChip), findsNothing, reason: why);
  expect(find.text(l.loadFailedHelp), findsNothing, reason: why);
  expect(find.text(l.finishedServices(1)), findsOneWidget, reason: why);
  final label = used ? l.stateExhausted : l.powerExpired;
  expect(find.text(label), findsNWidgets(used ? 2 : 1), reason: why);
  await _shot(tester, '${look.name}-$locale-${brightness.name}-$status');
}

Future<void> _before(WidgetTester tester, _Look look) async {
  await _pump(
    tester,
    look,
    _account('active', loadFailed: true),
    locale: 'fa',
    brightness: Brightness.light,
  );
  final l = lookupShikooL10n(const Locale('fa'));
  expect(find.text(l.loadFailedChip), findsOneWidget);
  expect(find.text(l.loadFailedHelp), findsOneWidget);
  expect(find.text(l.chipExpired), findsOneWidget, reason: 'OpenVPN on top');
  expect(find.text(l.powerExpired), findsOneWidget, reason: 'from OpenVPN');
  await _shot(tester, '${look.name}-fa-light-before');
}

Future<void> _all(WidgetTester tester, _Look look) async {
  for (final locale in ['fa', 'en']) {
    for (final brightness in Brightness.values) {
      await _finished(tester, look, locale, brightness);
    }
  }
  await _finished(tester, look, 'fa', Brightness.light, status: 'expired');
  await _before(tester, look);
}

void main() {
  setUpAll(loadShikooFonts);

  testWidgets(
    'a service its panel calls used up or past its date is a '
    'finished card with «تمدید», never «باز نشد», on the phone',
    (tester) => _all(tester, _Look.phone),
  );

  testWidgets('and on the TV', (tester) => _all(tester, _Look.tv));

  testWidgets(
    'and in the Windows window',
    (tester) => _all(tester, _Look.windows),
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
