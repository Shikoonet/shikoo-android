import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

class _Controller extends Mock implements ShikooController {}

const _servers = [
  ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
  ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 96),
  ShikooServer(name: 'فنلاند ۲', type: 'Vless', ping: 112),
  ShikooServer(name: 'آمریکا ۲', type: 'Vless', ping: 188),
];

ShikooState _state({
  bool tv = false,
  ShikooConnection connection = ShikooConnection.on,
  ShikooRefresh refresh = ShikooRefresh.idle,
  ShikooLeg? leg,
  ShikooNotice? notice,
  DateTime? updatedAt,
  String selected = 'آلمان ۲',
}) => ShikooState(
  connection: connection,
  connectedFor: const Duration(minutes: 12, seconds: 47),
  isTV: tv,
  service: ShikooService(
    name: '5550123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
    expire: DateTime.now().add(const Duration(days: 23)),
    updatedAt: updatedAt ?? DateTime.now().subtract(const Duration(minutes: 5)),
    leg: leg,
  ),
  servers: [
    if (selected != 'آلمان ۲')
      ShikooServer(name: selected, type: 'Vless', ping: 80),
    ..._servers,
  ],
  selected: selected,
  refresh: refresh,
  notice: notice,
);

typedef _Rig = ({_Controller controller, ValueNotifier<ShikooState> holder});

Future<_Rig> _pump(
  WidgetTester tester,
  ShikooState state, {
  Size? size,
  Brightness brightness = Brightness.light,
  String locale = 'fa',
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final tv = state.isTV;
  final view = size ?? (tv ? const Size(960, 540) : const Size(412, 915));
  tester.view
    ..physicalSize = view * 2
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  FocusManager.instance.highlightStrategy = tv
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  final controller = _Controller();
  when(
    () => controller.refreshService(via: any(named: 'via')),
  ).thenAnswer((_) async {});
  final holder = ValueNotifier(state);
  addTearDown(holder.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooControllerProvider.overrideWithValue(controller),
        shikooStateProvider.overrideWith((ref) {
          void changed() => ref.invalidateSelf();
          holder.addListener(changed);
          ref.onDispose(() => holder.removeListener(changed));
          return holder.value;
        }),
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
  return (controller: controller, holder: holder);
}

final _l = lookupShikooL10n(const Locale('fa'));
final _screen = GlobalKey();

Finder get _caret => find.bySemanticsLabel(_l.refreshWays);

/// The remote's place: a button's label, `▾`, or a menu item's first line.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context as Element?;
  if (context == null) return null;
  final label = context.findAncestorWidgetOfExactType<ShikooButton>()?.label;
  if (label != null) return label.isEmpty ? '▾' : label;
  String? text;
  void visit(Element element) {
    if (text != null) return;
    if (element.widget case final Text found) {
      text = found.data;
      return;
    }
    element.visitChildren(visit);
  }

  visit(context);
  return text;
}

/// Puts the remote on the button [target] is in, or holds.
Future<void> _focusOn(WidgetTester tester, Finder target) async {
  final above = find.ancestor(of: target, matching: find.byType(Pressable));
  final pressable = above.evaluate().isNotEmpty
      ? above.first
      : find.descendant(of: target, matching: find.byType(Pressable)).first;
  final node = Focus.of(
    tester.element(
      find
          .descendant(of: pressable, matching: find.byType(GestureDetector))
          .first,
    ),
  );
  FocusTraversalGroup.of(node.context!).invalidateScopeData(node.nearestScope!);
  node.requestFocus();
  await tester.pumpAndSettle();
}

/// The «▾» icon, its size and colour.
SvgIcon _caretIcon(WidgetTester tester) => tester.widget<SvgIcon>(
  find.descendant(
    of: _caret,
    matching: find.byWidgetPredicate(
      (w) => w is SvgIcon && w.icon == ShikooIcon.chevronDown,
    ),
  ),
);

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

/// With `SHIKOO_SHOTS=<folder>`, the screen as a PNG there, for the designer and the verifier.
Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SHIKOO_SHOTS'];
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screen),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    registerFallbackValue(ShikooRoute.direct);
    await loadShikooFonts();
  });

  group('phone', () {
    testWidgets('«▾» opens the two ways; through the server names the server '
        'and updates only that way, once', (tester) async {
      final rig = await _pump(tester, _state());
      await tester.tap(_caret);
      await tester.pumpAndSettle();
      expect(find.text(_l.refreshDirect), findsOneWidget);
      expect(find.text(_l.refreshDirectHint), findsOneWidget);
      expect(
        find.text(_l.refreshViaServerHint(serverName('آلمان ۲'))),
        findsOneWidget,
      );
      await _shot(tester, 'phone-menu-on-light');

      await tester.tap(find.text(_l.refreshViaServer));
      await tester.pumpAndSettle();
      verify(
        () => rig.controller.refreshService(via: ShikooRoute.server),
      ).called(1);
      expect(find.text(_l.refreshViaServer), findsNothing);
    });

    testWidgets('disconnected, through the server is grey with «اول وصل شو» '
        'and does nothing; a tap outside closes the menu', (tester) async {
      final rig = await _pump(tester, _state(connection: ShikooConnection.off));
      await tester.tap(_caret);
      await tester.pumpAndSettle();
      expect(find.text(_l.refreshConnectFirst), findsOneWidget);
      await _shot(tester, 'phone-menu-off-light');

      await tester.tap(find.text(_l.refreshViaServer));
      await tester.pumpAndSettle();
      expect(find.text(_l.refreshViaServer), findsOneWidget, reason: 'open');
      await tester.tapAt(const Offset(200, 880));
      await tester.pumpAndSettle();
      expect(find.text(_l.refreshViaServer), findsNothing);
      verifyNever(() => rig.controller.refreshService(via: any(named: 'via')));
    });

    testWidgets('a tap on the update is the automatic way, a long press '
        'opens the menu', (tester) async {
      final rig = await _pump(tester, _state());
      final update = find.bySemanticsLabel(_l.refreshServers);
      await tester.tap(update);
      await tester.pumpAndSettle();
      verify(() => rig.controller.refreshService()).called(1);
      expect(find.text(_l.refreshDirect), findsNothing);

      await tester.longPress(update);
      await tester.pumpAndSettle();
      expect(find.text(_l.refreshDirect), findsOneWidget);
    });

    testWidgets('«▾» is a small icon, muted, and the text colour while its '
        'menu is open', (tester) async {
      await _pump(tester, _state());
      final t = ShikooTheme.of(tester.element(_caret));
      expect(_caretIcon(tester).size, ShikooSizes.phone.iconSm);
      expect(_caretIcon(tester).color, t.c.textMuted);
      await _shot(tester, 'phone-caret-closed');
      await tester.tap(_caret);
      await tester.pumpAndSettle();
      expect(_caretIcon(tester).color, t.c.text);
      await _shot(tester, 'phone-caret-open');
    });

    testWidgets('at font ×1.45 the other way and the report wrap, the link '
        'kept on one line', (tester) async {
      for (final (width, scale) in [
        (412.0, 1.0),
        (412.0, 1.45),
        (360.0, 1.45),
      ]) {
        await _pump(
          tester,
          _state(
            refresh: ShikooRefresh.failed,
            updatedAt: DateTime.now().subtract(const Duration(days: 2)),
            notice: const RefreshFailed(way: ShikooFailedWay.direct),
          ),
          size: Size(width, 915),
          textScale: scale,
        );
        final link = tester.getSize(find.text(_l.reportSendToSupport));
        final label = tester.getSize(find.text(_l.refreshViaServer));
        expect(
          link.height,
          closeTo(label.height, 1),
          reason: '$width ×$scale: one line, as the button label',
        );
        expect(tester.takeException(), isNull);
        if (scale == 1) {
          expect(
            tester.getCenter(find.text(_l.reportSendToSupport)).dy,
            closeTo(tester.getCenter(find.text(_l.refreshViaServer)).dy, 2),
            reason: 'with room, the link sits beside the button',
          );
        }
        if (width == 412) {
          await _shot(tester, 'phone-failed-direct-x${scale == 1 ? 100 : 145}');
        }
      }
    });

    testWidgets('dark, connected', (tester) async {
      await _pump(tester, _state(), brightness: Brightness.dark);
      await tester.tap(_caret);
      await tester.pumpAndSettle();
      await _shot(tester, 'phone-menu-on-dark');
    });

    testWidgets('the status line names the way it is on', (tester) async {
      final rig = await _pump(tester, _state());
      for (final (leg, text, shot) in [
        (ShikooLeg.direct, _l.updatingDirect, null),
        (ShikooLeg.directOff, _l.updatingDirect, null),
        (ShikooLeg.server, _l.updatingViaServer, 'phone-status-via'),
        (ShikooLeg.fallback, _l.updatingFallback, 'phone-status-fallback'),
      ]) {
        rig.holder.value = _state(refresh: ShikooRefresh.running, leg: leg);
        await tester.pump();
        expect(find.text(text), findsOneWidget, reason: '$leg');
        if (shot != null) await _shot(tester, shot);
      }
    });

    testWidgets('a failed update says which way went unanswered and offers '
        'the other as a button where there is one', (tester) async {
      final rig = await _pump(tester, _state());
      final old = DateTime.now().subtract(const Duration(days: 2));
      for (final (way, connection, rest, other, shot) in [
        (
          ShikooFailedWay.directOff,
          ShikooConnection.off,
          _l.updateFailedDirectOff,
          null,
          'phone-failed-direct-off',
        ),
        (
          ShikooFailedWay.direct,
          ShikooConnection.on,
          _l.updateFailedDirect,
          ShikooRoute.server,
          'phone-failed-direct',
        ),
        (
          ShikooFailedWay.direct,
          ShikooConnection.off,
          _l.updateFailedDirect,
          null,
          null,
        ),
        (
          ShikooFailedWay.server,
          ShikooConnection.on,
          _l.updateFailedViaServer(serverName('آلمان ۲')),
          ShikooRoute.direct,
          'phone-failed-via-server',
        ),
        (
          ShikooFailedWay.both,
          ShikooConnection.on,
          _l.updateFailedBoth(serverName('آلمان ۲')),
          null,
          'phone-failed-both',
        ),
        (
          ShikooFailedWay.panel,
          ShikooConnection.on,
          _l.updateFailedPanel,
          null,
          'phone-failed-panel',
        ),
        (
          ShikooFailedWay.notConnected,
          ShikooConnection.off,
          _l.updateFailedConnectFirst,
          null,
          null,
        ),
      ]) {
        rig.holder.value = _state(
          connection: connection,
          refresh: ShikooRefresh.failed,
          updatedAt: old,
          notice: RefreshFailed(way: way, server: 'آلمان ۲'),
        );
        await tester.pumpAndSettle();
        final why = '$way $connection';
        expect(find.textContaining(rest), findsOneWidget, reason: why);
        expect(find.text(_l.reportSendToSupport), findsOneWidget, reason: why);
        final button = switch (other) {
          ShikooRoute.server => _l.refreshViaServer,
          ShikooRoute.direct => _l.refreshDirect,
          null => null,
        };
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is ShikooButton &&
                {_l.refreshViaServer, _l.refreshDirect}.contains(w.label),
          ),
          button == null ? findsNothing : findsOneWidget,
          reason: why,
        );
        if (shot != null) await _shot(tester, shot);
        if (button == null) continue;
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        verify(() => rig.controller.refreshService(via: other)).called(1);
      }
    });
  });

  group('TV', () {
    Future<_Rig> onRefresh(WidgetTester tester, ShikooState state) async {
      final rig = await _pump(tester, state);
      await _focusOn(tester, find.text(_l.refresh));
      expect(_focused(), _l.refresh);
      return rig;
    }

    const towardPower = LogicalKeyboardKey.arrowLeft;
    const ok = LogicalKeyboardKey.select;

    testWidgets('the head goes update, «▾», ping; OK on «▾» opens the menu '
        'on «مستقیم», down and up move, OK runs and closes, the remote back '
        'on «▾»', (tester) async {
      final rig = await onRefresh(tester, _state(tv: true));
      expect(await _press(tester, towardPower), '▾');
      expect(await _press(tester, towardPower), _l.ping);
      expect(await _press(tester, LogicalKeyboardKey.arrowRight), '▾');

      expect(await _press(tester, ok), _l.refreshDirect);
      await _shot(tester, 'tv-menu-on-light');
      expect(
        await _press(tester, LogicalKeyboardKey.arrowDown),
        _l.refreshViaServer,
      );
      expect(
        await _press(tester, LogicalKeyboardKey.arrowUp),
        _l.refreshDirect,
      );
      expect(await _press(tester, ok), '▾');
      expect(find.text(_l.refreshViaServer), findsNothing);
      verify(
        () => rig.controller.refreshService(via: ShikooRoute.direct),
      ).called(1);
    });

    testWidgets('Back only closes the menu, the remote back on «▾»; '
        'disconnected, down stays on «مستقیم»', (tester) async {
      final rig = await onRefresh(
        tester,
        _state(tv: true, connection: ShikooConnection.off),
      );
      await _press(tester, towardPower);
      expect(await _press(tester, ok), _l.refreshDirect);
      expect(
        await _press(tester, LogicalKeyboardKey.arrowDown),
        _l.refreshDirect,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_l.refreshDirect), findsNothing);
      expect(_focused(), '▾');
      verifyNever(() => rig.controller.refreshService(via: any(named: 'via')));
    });

    testWidgets('while an update runs, «▾» keeps the remote and does '
        'nothing', (tester) async {
      final rig = await onRefresh(tester, _state(tv: true));
      await _press(tester, towardPower);
      rig.holder.value = _state(
        tv: true,
        refresh: ShikooRefresh.running,
        leg: ShikooLeg.fallback,
      );
      await tester.pumpAndSettle();
      expect(await _press(tester, ok), '▾');
      expect(find.text(_l.refreshDirect), findsNothing);
      expect(find.text(_l.updatingFallback), findsOneWidget);
      await _shot(tester, 'tv-status-fallback');
    });

    testWidgets('«▾» is a small icon on the TV too', (tester) async {
      await onRefresh(tester, _state(tv: true));
      expect(_caretIcon(tester).size, ShikooSizes.tv.iconSm);
      await _press(tester, towardPower);
      await _shot(tester, 'tv-caret-closed');
      await _press(tester, ok);
      await _shot(tester, 'tv-caret-open');
    });

    testWidgets('one press down from anywhere in the head lands on the '
        "failure's other way; up from renew comes back to it, up from support "
        'to the report', (tester) async {
      final rig = await onRefresh(
        tester,
        _state(
          tv: true,
          refresh: ShikooRefresh.failed,
          updatedAt: DateTime.now().subtract(const Duration(days: 2)),
          notice: const RefreshFailed(
            way: ShikooFailedWay.server,
            server: 'آلمان ۲',
          ),
        ),
      );
      final wrong = <String>[];
      for (final (from, start, key, to) in [
        (
          'update',
          find.text(_l.refresh),
          LogicalKeyboardKey.arrowDown,
          _l.refreshDirect,
        ),
        ('▾', _caret, LogicalKeyboardKey.arrowDown, _l.refreshDirect),
        (
          'ping',
          find.text(_l.ping),
          LogicalKeyboardKey.arrowDown,
          _l.refreshDirect,
        ),
        (
          'renew',
          find.text(_l.renew),
          LogicalKeyboardKey.arrowUp,
          _l.refreshDirect,
        ),
        (
          'support',
          find.text(_l.support),
          LogicalKeyboardKey.arrowUp,
          _l.reportSendToSupport,
        ),
      ]) {
        await _focusOn(tester, start);
        final got = await _press(tester, key);
        if (got != to) wrong.add('$from ${key.debugName}: $got, not $to');
        if (from == 'renew') await _shot(tester, 'tv-up-from-renew');
      }
      expect(wrong, isEmpty);
      await _focusOn(tester, find.text(_l.refresh));
      expect(
        await _press(tester, LogicalKeyboardKey.arrowDown),
        _l.refreshDirect,
      );
      await _shot(tester, 'tv-failed-via-server');
      await _press(tester, ok);
      verify(
        () => rig.controller.refreshService(via: ShikooRoute.direct),
      ).called(1);
    });
  });

  testWidgets("the menu hangs under «▾», its end on «▾»'s and inside the "
      'card: a TV of 960, 1280 and 1920, phones of 352, 360 and 412, both '
      'languages, a long server name', (tester) async {
    // Long enough that the menu always reaches the card's far edge, in both languages.
    const long =
        'آلمان ۲ - Hetzner Falkenstein premium dedicated 10 Gbit unmetered';
    final wrong = <String>[];
    for (final language in ['fa', 'en']) {
      final l = lookupShikooL10n(Locale(language));
      for (final (tv, size) in const [
        (true, Size(960, 540)),
        (true, Size(1280, 720)),
        (true, Size(1920, 1080)),
        (false, Size(352, 780)),
        (false, Size(360, 780)),
        (false, Size(412, 915)),
      ]) {
        final at = '$language ${tv ? 'TV' : 'phone'} $size';
        // The TV canvas is drawn ×k: Space.s1 under «▾» is that many pixels.
        final k = tv ? math.min(size.width / 960, size.height / 540) : 1.0;
        await _pump(
          tester,
          _state(tv: tv, selected: long),
          size: size,
          locale: language,
        );
        final caret = find.bySemanticsLabel(l.refreshWays).first;
        await tester.ensureVisible(caret);
        await tester.pumpAndSettle();
        final c = tester.getRect(caret);
        final card = tester.getRect(
          find.ancestor(of: caret, matching: find.byType(ServiceCard)).first,
        );
        await tester.tap(caret);
        await tester.pumpAndSettle();
        final menu = tester.getRect(
          find
              .ancestor(
                of: find.text(l.refreshDirect),
                matching: find.byType(IntrinsicWidth),
              )
              .first,
        );
        if ((menu.top - c.bottom - Space.s1 * k).abs() > 0.5) {
          wrong.add('$at: menu $menu not under «▾» $c');
        }
        final end = language == 'fa'
            ? menu.left - c.left
            : menu.right - c.right;
        if (end.abs() > 0.5) wrong.add('$at: menu ends $end off «▾»');
        if (menu.left < card.left - 0.5 || menu.right > card.right + 0.5) {
          wrong.add('$at: menu $menu out of the card $card');
        }
        final start = language == 'fa'
            ? menu.right - card.right
            : menu.left - card.left;
        if (start.abs() > 0.5) {
          wrong.add('$at: menu starts $start off the card');
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    }
    expect(wrong, isEmpty);
  });

  testWidgets('on a phone of 320 at font ×1.15 the card has no room for the '
      'menu beside «▾»: it keeps its 248, stays on the screen and wraps no '
      'line past two, in both languages', (tester) async {
    const screen = Size(320, 700);
    final wrong = <String>[];
    for (final language in ['fa', 'en']) {
      final l = lookupShikooL10n(Locale(language));
      await _pump(
        tester,
        _state(),
        size: screen,
        locale: language,
        textScale: 1.15,
      );
      await tester.tap(find.bySemanticsLabel(l.refreshWays).first);
      await tester.pumpAndSettle();
      await _shot(tester, 'phone-320-menu-$language');
      final box = find
          .ancestor(
            of: find.text(l.refreshDirect),
            matching: find.byType(IntrinsicWidth),
          )
          .first;
      final menu = tester.getRect(box);
      if (menu.width < 248) wrong.add('$language: menu $menu under 248');
      if (menu.left < Space.s2 - 0.5 ||
          menu.right > screen.width - Space.s2 + 0.5) {
        wrong.add('$language: menu $menu off the screen');
      }
      for (final p in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: box, matching: find.byType(RichText)),
      )) {
        final text = p.text.toPlainText();
        final lines = p
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length),
              boxHeightStyle: ui.BoxHeightStyle.max,
            )
            .map((b) => b.top.round())
            .toSet()
            .length;
        if (lines > 2) wrong.add('$language: «$text» in $lines lines');
      }
    }
    expect(wrong, isEmpty);
  });

  testWidgets('a wide window: a right-click on the update opens the menu, '
      'Esc closes it', (tester) async {
    await _pump(tester, _state(), size: const Size(864, 492));
    final update = find.bySemanticsLabel(_l.refreshServers);
    await tester.tap(update, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text(_l.refreshDirect), findsOneWidget);
    await _shot(tester, 'wide-menu-on-light');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(_l.refreshDirect), findsNothing);
  });
}
