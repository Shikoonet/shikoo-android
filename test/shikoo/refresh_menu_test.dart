import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
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
  servers: _servers,
  selected: 'آلمان ۲',
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
}) async {
  SharedPreferences.setMockInitialValues({});
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
      final node = Focus.of(
        tester.element(
          find
              .descendant(
                of: find.ancestor(
                  of: find.text(_l.refresh),
                  matching: find.byType(Pressable),
                ),
                matching: find.byType(GestureDetector),
              )
              .first,
        ),
      );
      node.requestFocus();
      await tester.pumpAndSettle();
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

    testWidgets('one press down from the head lands on the failure\'s other '
        'way', (tester) async {
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
