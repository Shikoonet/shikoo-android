import 'dart:async';

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

const _servers = [
  ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
  ShikooServer(name: 'فنلاند ۲', type: 'Vless', ping: 112),
  ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 96),
  ShikooServer(name: 'آمریکا ۲', type: 'Vless', ping: 188),
];

final _longList = [
  for (var i = 1; i <= 12; i++)
    ShikooServer(name: 'سرور $i', type: 'Vless', ping: 80 + i),
];

ShikooState _tv(
  ShikooConnection connection, {
  List<ShikooServer> servers = _servers,
  String? selected = 'فنلاند ۲',
  ShikooPick pick = ShikooPick.server,
  ShikooError? error,
  bool waiting = false,
  ({int done, int total})? pinging,
  ShikooRefresh refresh = ShikooRefresh.idle,
  ShikooNotice? notice,
  DateTime? expire,
  DateTime? updatedAt,
  String? supportUrl,
  String? announce,
  bool sorted = true,
}) => ShikooState(
  connection: connection,
  connectedFor: const Duration(minutes: 12, seconds: 47),
  isTV: true,
  service: ShikooService(
    name: 'user123 · الماس',
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
    expire: expire,
    supportUrl: supportUrl,
    announce: announce,
    updatedAt: updatedAt ?? DateTime.now(),
  ),
  servers: servers,
  selected: selected,
  pick: pick,
  waiting: waiting,
  pinging: pinging,
  refresh: refresh,
  notice: notice,
  sorted: sorted,
  lastError:
      error ??
      (connection == ShikooConnection.error
          ? ShikooError.connectTimeout
          : null),
);

/// Swapping the state through one ProviderScope keeps focus where the remote left it.
Future<ValueNotifier<ShikooState>> _pumpTvHome(
  WidgetTester tester,
  ShikooState state, {
  String locale = 'fa',
  bool canvas = false,
}) async {
  final holder = ValueNotifier(state);
  addTearDown(holder.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
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
        theme: shikooThemeData(Brightness.dark, tv: true),
        builder: canvas ? (_, child) => ShikooTvCanvas(child: child!) : null,
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pump();
  return holder;
}

void _tvScreen(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// What the remote is on: a server name, `power`, or a button label.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final row = context.findAncestorWidgetOfExactType<ServerRow>();
  if (row != null) return row.server.name;
  if (context.findAncestorWidgetOfExactType<PowerButton>() != null) {
    return 'power';
  }
  final label = context.findAncestorWidgetOfExactType<ShikooButton>()?.label;
  return label == '' ? '▾' : label;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

Future<void> _focus(WidgetTester tester, String what) async {
  final owner = switch (what) {
    'power' => find.byType(PowerButton),
    '▾' => find.byWidgetPredicate((w) => w is ShikooButton && w.label == ''),
    _ => find.ancestor(of: find.text(what), matching: find.byType(Pressable)),
  };
  final inside = find.descendant(
    of: owner.first,
    matching: find.byType(GestureDetector),
  );
  final node = Focus.of(tester.element(inside.first));
  // Directional traversal remembers past moves; a jump by hand must start it afresh.
  FocusTraversalGroup.of(node.context!).invalidateScopeData(node.nearestScope!);
  node.requestFocus();
  await tester.pumpAndSettle();
  expect(_focused(), what);
}

List<String> _rowOrder(WidgetTester tester) => [
  for (final row in tester.widgetList<ServerRow>(find.byType(ServerRow)))
    row.server.name,
];

const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;
const _towardPower = LogicalKeyboardKey.arrowLeft;
const _towardCard = LogicalKeyboardKey.arrowRight;
const _ok = LogicalKeyboardKey.select;

void main() {
  testWidgets('the TV power button sits at 274dp, with or without a server', (
    tester,
  ) async {
    _tvScreen(tester);
    final states = {
      for (final connection in ShikooConnection.values)
        connection.name: _tv(connection),
      'finding': _tv(
        ShikooConnection.off,
        selected: null,
        pick: ShikooPick.finding,
      ),
      'finding-connect': _tv(
        ShikooConnection.connecting,
        selected: null,
        pick: ShikooPick.finding,
        waiting: true,
      ),
      'all-failed': _tv(
        ShikooConnection.error,
        selected: null,
        pick: ShikooPick.none,
        error: ShikooError.noServer,
      ),
      'none-quiet': _tv(
        ShikooConnection.off,
        selected: null,
        pick: ShikooPick.none,
      ),
    };
    final centres = <String, Offset>{};
    for (final MapEntry(:key, :value) in states.entries) {
      await _pumpTvHome(tester, value);
      expect(tester.takeException(), isNull, reason: key);
      centres[key] = tester.getCenter(find.byType(PowerButton));
    }
    // c-tv-off: with WARP off, «روشن کردن WARP» under the message lifts the button.
    final offer = centres.remove('all-failed')!;
    expect(centres.values.toSet(), hasLength(1), reason: '$centres');
    expect(centres.values.first.dy, closeTo(274, 0.5));
    expect(offer.dy, lessThan(274));
  });

  testWidgets('the remote follows the order the TV mockup sets', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(tester, _tv(ShikooConnection.off));
    expect(_focused(), 'power');
    // tv-c: along the bar, and up from the card to renew. Up from the power button is what stands
    // above it: Settings in this wide test font, «پشتیبانی» in Vazirmatn (_topBarInVazirmatn).
    final moves = [
      ('power', _up, 'تنظیمات'),
      ('power', _down, 'power'),
      ('power', _towardPower, 'power'),
      ('power', _towardCard, 'فنلاند ۲'),
      ('پشتیبانی', _towardCard, 'تمدید'),
      ('پشتیبانی', _towardPower, 'تنظیمات'),
      ('تمدید', _towardPower, 'پشتیبانی'),
      ('تنظیمات', _towardCard, 'پشتیبانی'),
      ('تنظیمات', _down, 'power'),
      ('پشتیبانی', _down, 'پینگ'),
      ('تمدید', _down, 'پینگ'),
      ('به‌روزرسانی', _up, 'تمدید'),
      ('به‌روزرسانی', _down, 'آلمان ۲'),
      ('به‌روزرسانی', _towardPower, '▾'),
      ('به‌روزرسانی', _towardCard, 'به‌روزرسانی'),
      ('▾', _up, 'تمدید'),
      ('▾', _down, 'آلمان ۲'),
      ('▾', _towardPower, 'پینگ'),
      ('▾', _towardCard, 'به‌روزرسانی'),
      ('پینگ', _up, 'تمدید'),
      ('پینگ', _down, 'آلمان ۲'),
      ('پینگ', _towardPower, 'power'),
      ('پینگ', _towardCard, '▾'),
      ('آلمان ۲', _up, 'به‌روزرسانی'),
      ('هلند ۱', _towardPower, 'power'),
    ];
    final wrong = <String>[];
    for (final (from, key, to) in moves) {
      await _focus(tester, from);
      final got = await _press(tester, key);
      if (got != to) wrong.add('$from ${key.debugName} -> $got, not $to');
    }
    expect(wrong, isEmpty);
  });

  testWidgets('back from another app with no focus left, the remote is on '
      'connect again; a focus that stayed is kept (#32)', (tester) async {
    _tvScreen(tester);
    await _pumpTvHome(tester, _tv(ShikooConnection.on));
    await tester.pumpAndSettle();
    expect(_focused(), 'power');
    Future<void> awayAndBack({required bool focusLost}) async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      if (focusLost) FocusManager.instance.rootScope.requestScopeFocus();
      await tester.pump();
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
    }

    await _focus(tester, 'هلند ۱');
    await awayAndBack(focusLost: true);
    expect(_focused(), 'power', reason: 'as on the box: nothing was focused');

    await _focus(tester, 'هلند ۱');
    await awayAndBack(focusLost: false);
    expect(_focused(), 'هلند ۱');
  });

  testWidgets('with no server chosen, the remote goes to the first row; the '
      'pill rests, and spins only while connect waits', (tester) async {
    _tvScreen(tester);
    final holder = await _pumpTvHome(
      tester,
      _tv(ShikooConnection.off, selected: null, pick: ShikooPick.auto),
    );
    expect(await _press(tester, _towardCard), 'آلمان ۲');
    expect(find.text('سرور خودکار انتخاب می‌شود'), findsOneWidget);
    expect(find.byType(Spinner), findsNothing);

    holder.value = _tv(
      ShikooConnection.connecting,
      selected: null,
      pick: ShikooPick.finding,
      waiting: true,
    );
    await tester.pump();
    expect(find.text('در حال یافتن بهترین سرور…'), findsOneWidget);
  });

  testWidgets('the card column scrolls back up once the remote leaves it', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.on, servers: _longList, selected: 'سرور 1'),
    );
    final column = find
        .ancestor(
          of: find.byType(ServiceCard),
          matching: find.byType(Scrollable),
        )
        .first;
    double offset() => tester.state<ScrollableState>(column).position.pixels;

    expect(await _press(tester, _towardCard), 'سرور 1');
    for (var i = 1; i < _longList.length; i++) {
      await _press(tester, _down);
    }
    expect(_focused(), 'سرور 12');
    expect(offset(), greaterThan(0));

    expect(await _press(tester, _towardPower), 'power');
    expect(offset(), 0);
  });

  testWidgets(
    'a notice leaving from above the list keeps the row and its ring in '
    'view, and toward the power button still goes there, not to Settings',
    (tester) async {
      ShikooState home({ShikooNotice? notice}) => _tv(
        ShikooConnection.off,
        servers: _longList,
        selected: 'سرور 1',
        notice: notice,
      );
      final wrong = <String>[];
      for (final ratio in const [2.0, 1.0]) {
        for (final locale in const ['fa', 'en']) {
          _tvScreen(tester);
          tester.view.devicePixelRatio = ratio;
          final holder = await _pumpTvHome(
            tester,
            home(
              notice: const SelectedReplaced(
                removed: 'سرور 13',
                replacement: 'سرور 1',
                moved: false,
              ),
            ),
            locale: locale,
            canvas: true,
          );
          await tester.pumpAndSettle();
          final rtl = locale == 'fa';
          await _press(tester, rtl ? _towardCard : _towardPower);
          final row = _focused();
          holder.value = home();
          await tester.pumpAndSettle();
          final shown = find.widgetWithText(ServerRow, 'سرور 1');
          final view = tester.getRect(
            find.ancestor(of: shown, matching: find.byType(Scrollable)).first,
          );
          final ring = tester.getRect(shown).inflate(ShikooSizes.ring);
          final inView = ring.top >= view.top && ring.bottom <= view.bottom;
          final got = await _press(tester, rtl ? _towardPower : _towardCard);
          if (row != 'سرور 1' || !inView || got != 'power') {
            wrong.add('$locale, ${1920 / ratio} dp: $row $inView, then $got');
          }
        }
      }
      expect(wrong, isEmpty);
    },
  );

  testWidgets('a row the list scrolled under the top bar steps toward the '
      'power button there, not to Settings beside it', (tester) async {
    final wrong = <String>[];
    for (final ratio in const [2.0, 1.0]) {
      for (final locale in const ['fa', 'en']) {
        _tvScreen(tester);
        tester.view.devicePixelRatio = ratio;
        await _pumpTvHome(
          tester,
          _tv(ShikooConnection.off, servers: _longList, selected: 'سرور 1'),
          locale: locale,
          canvas: true,
        );
        await tester.pumpAndSettle();
        final rtl = locale == 'fa';
        await _press(tester, rtl ? _towardCard : _towardPower);
        final row = find.widgetWithText(ServerRow, 'سرور 1');
        final settings = find.widgetWithText(
          ShikooButton,
          lookupShikooL10n(Locale(locale)).settings,
        );
        double above() =>
            tester.getCenter(row).dy - tester.getCenter(settings).dy;
        final list = find
            .ancestor(of: row, matching: find.byType(Scrollable))
            .first;
        final box = tester.renderObject<RenderBox>(list);
        final scale =
            box.localToGlobal(const Offset(0, 1)).dy -
            box.localToGlobal(Offset.zero).dy;
        final position = tester.state<ScrollableState>(list).position;
        position.jumpTo(position.pixels + above() / scale);
        await tester.pump();
        final level = above().abs() < 1;
        final got = await _press(tester, rtl ? _towardPower : _towardCard);
        if (!level || got != 'power') {
          wrong.add('$locale, ${1920 / ratio} dp: level $level, then $got');
        }
      }
    }
    expect(wrong, isEmpty);
  });

  testWidgets('a refresh that fails puts its message above the card\'s '
      'buttons and leaves the remote on the one it was on', (tester) async {
    final wrong = <String>[];
    for (final at in ['پشتیبانی', 'تمدید', 'پینگ', 'فنلاند ۲']) {
      _tvScreen(tester);
      final holder = await _pumpTvHome(tester, _tv(ShikooConnection.off));
      await _focus(tester, at);
      holder.value = _tv(ShikooConnection.off, refresh: ShikooRefresh.running);
      await tester.pumpAndSettle();
      holder.value = _tv(
        ShikooConnection.off,
        refresh: ShikooRefresh.failed,
        notice: const RefreshFailed(),
      );
      await tester.pumpAndSettle();
      final failed = _focused();
      holder.value = _tv(ShikooConnection.off);
      await tester.pumpAndSettle();
      if (failed != at || _focused() != at) {
        wrong.add('$at: $failed, then ${_focused()}');
      }
    }
    expect(wrong, isEmpty);
  });

  testWidgets('a new order waits while the remote is on the list', (
    tester,
  ) async {
    _tvScreen(tester);
    final holder = await _pumpTvHome(tester, _tv(ShikooConnection.on));
    final before = _rowOrder(tester);
    await _focus(tester, 'هلند ۱');

    holder.value = _tv(
      ShikooConnection.on,
      servers: [_servers[0], _servers[2], _servers[1], _servers[3]],
    );
    await tester.pumpAndSettle();
    expect(_rowOrder(tester), before);
    expect(_focused(), 'هلند ۱');
    expect(find.textContaining('وقتی از فهرست بیرون بروی'), findsOneWidget);

    expect(await _press(tester, _down), 'آمریکا ۲');
    expect(_rowOrder(tester), before, reason: 'moving inside keeps it');

    expect(await _press(tester, _towardPower), 'power');
    expect(_rowOrder(tester), ['آلمان ۲', 'هلند ۱', 'فنلاند ۲', 'آمریکا ۲']);
    expect(find.textContaining('سریع‌ترین بالا'), findsOneWidget);
  });

  testWidgets('a row being measured spins instead of showing its old ping', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.on,
        servers: const [
          ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
          ShikooServer(name: 'هلند ۱', type: 'Vless', testing: true),
        ],
        selected: 'آلمان ۲',
        pinging: (done: 4, total: 9),
      ),
    );
    final measuring = find.ancestor(
      of: find.text('هلند ۱'),
      matching: find.byType(ServerRow),
    );
    expect(
      find.descendant(of: measuring, matching: find.byType(Spinner)),
      findsOneWidget,
    );
    expect(find.text('پینگ ۴ از ۹'), findsOneWidget);
  });

  testWidgets('a failed update is red only when the user asked for it', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.off, refresh: ShikooRefresh.failed),
    );
    expect(
      find.text('به‌روز نشد'),
      findsOneWidget,
      reason: 'list from just now',
    );
    expect(find.textContaining('دکمهٔ وسط را دوباره بزن'), findsNothing);

    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.off,
        refresh: ShikooRefresh.failed,
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    );
    expect(find.text('به‌روز نشد، فهرستِ ۲\u00a0روز پیش'), findsOneWidget);

    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.off,
        refresh: ShikooRefresh.failed,
        notice: const RefreshFailed(),
      ),
    );
    expect(
      find.textContaining('از اینترنتِ خودِ دستگاه جواب نیامد'),
      findsOneWidget,
    );
  });

  testWidgets(
    "a short card starts where a long one does, at the design's 89dp",
    (tester) async {
      _tvScreen(tester);
      for (final servers in [_longList, _longList.take(2).toList()]) {
        await _pumpTvHome(
          tester,
          _tv(ShikooConnection.off, servers: servers, selected: 'سرور 1'),
        );
        expect(
          tester.getTopLeft(find.byType(ServiceCard)).dy,
          89,
          reason: '${servers.length} servers',
        );
        expect(
          tester.getTopRight(find.byType(ServiceCard)).dx,
          960 - ShikooSizes.tv.safeX - ShikooSizes.ring,
          reason:
              'the logo'
              's edge, inside the safe area by the ring',
        );
      }
    },
  );

  testWidgets('on a row the list head goes to the top; on the head buttons the '
      'column does', (tester) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.on, servers: _longList, selected: 'سرور 1'),
    );
    final column = find
        .ancestor(
          of: find.byType(ServiceCard),
          matching: find.byType(Scrollable),
        )
        .first;
    double headTop() =>
        tester.getTopLeft(find.textContaining('سریع‌ترین بالا')).dy -
        tester.getTopLeft(column).dy;
    double cardTop() =>
        tester.getTopLeft(find.byType(ServiceCard)).dy -
        tester.getTopLeft(column).dy;

    await _focus(tester, 'پینگ');
    expect(await _press(tester, _down), 'سرور 1');
    expect(headTop(), lessThan(Space.s4 * 2 + Space.s2));

    for (final button in ['پینگ', 'به‌روزرسانی']) {
      await _focus(tester, 'سرور 12');
      await _focus(tester, button);
      expect(
        cardTop(),
        Space.s2,
        reason: 'back on $button, the column is at its very top',
      );
    }
  });

  testWidgets('the update names what changed', (tester) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.on,
        selected: 'هلند ۱',
        notice: const SelectedReplaced(
          removed: '🇺🇸 آمریکا ۲',
          replacement: '🇳🇱 هلند ۱',
          moved: true,
        ),
      ),
    );
    expect(
      find.textContaining('«${bidiName('آمریکا ۲')}» دیگر در اشتراکت نیست.'),
      findsOneWidget,
    );
    final nl = bidiName('هلند ۱');
    expect(find.textContaining('سرور، «$nl»، رفت.'), findsOneWidget);

    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.on,
        selected: 'هلند ۱',
        notice: const SelectedReplaced(
          removed: '🇺🇸 آمریکا ۲',
          replacement: '🇳🇱 هلند ۱',
          moved: true,
          fastest: false,
        ),
      ),
    );
    expect(
      find.textContaining('اتصال همان لحظه به «$nl» رفت.'),
      findsOneWidget,
    );

    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.off,
        notice: const ServersChanged(added: 2, removed: ['انگلیس']),
      ),
    );
    expect(find.textContaining('۲ سرور تازه آمد.'), findsOneWidget);
    expect(find.textContaining('«\u2068انگلیس\u2069» حذف شد.'), findsOneWidget);
  });

  testWidgets('every server silent: the pill says so, and the help is red', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.error,
        selected: null,
        pick: ShikooPick.none,
        error: ShikooError.noServer,
      ),
    );
    expect(find.text('هیچ سروری جواب نداد'), findsOneWidget);
    expect(find.text('وصل نشد'), findsOneWidget);
    expect(find.textContaining('اینترنت این تلویزیون'), findsOneWidget);
  });

  testWidgets('English dates are Gregorian, Persian ones Solar Hijri', (
    tester,
  ) async {
    _tvScreen(tester);
    final expire = DateTime(2026, 10, 26, 12);
    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.off, expire: expire),
      locale: 'en',
    );
    expect(find.text('Valid until Oct 26, 2026'), findsOneWidget);
    await _pumpTvHome(tester, _tv(ShikooConnection.off, expire: expire));
    expect(find.text('اعتبار تا ۴\u00a0آبان\u00a0۱۴۰۵'), findsOneWidget);
  });

  testWidgets('renew and support show a QR for the phone; Back closes it', (
    tester,
  ) async {
    _tvScreen(tester);
    String? qr() =>
        tester.widgetList<QrTile>(find.byType(QrTile)).firstOrNull?.data;

    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.on, supportUrl: 'https://t.me/'),
    );
    await _focus(tester, 'تمدید');
    expect(await _press(tester, _ok), 'بستن');
    expect(find.text('تمدید با گوشی'), findsOneWidget);
    expect(qr(), ShikooLinks.renew);
    expect(
      find.text(
        'در فهرست ربات، سرویسِ \u2068user123\u2069 را بزن؛ اگر نبود، صفحهٔ بعدِ فهرست را ببین.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(qr(), isNull);
    expect(_focused(), 'تمدید');

    await _focus(tester, 'پشتیبانی');
    await _press(tester, _ok);
    expect(qr(), ShikooLinks.support, reason: 'the panel sends a bare t.me');
    expect(
      find.textContaining('er123\u2069 ·\u00A0\u2068الماس', findRichText: true),
      findsNWidgets(2),
      reason:
          'the card, its name cut to fit the test font, and the line under '
          'the QR',
    );
    expect(await _press(tester, _ok), 'پشتیبانی', reason: 'Close');

    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.on, supportUrl: 'https://t.me/shikoo_help'),
    );
    await _focus(tester, 'پشتیبانی');
    await _press(tester, _ok);
    expect(qr(), 'https://t.me/shikoo_help');
  });

  testWidgets("the panel's announcement shows every line, right to left even "
      'when it opens with a version', (tester) async {
    _tvScreen(tester);
    const announce =
        'آخرین نسخه کانفیگ: V3.7.9\nاگر نسخه شما پایین‌تر است، به‌روزرسانی کنید.';
    await _pumpTvHome(tester, _tv(ShikooConnection.off, announce: announce));
    final text = tester.renderObject<RenderParagraph>(find.text(announce));
    expect(text.didExceedMaxLines, isFalse);
    expect(text.size.height, greaterThan(text.preferredLineHeight * 1.5));

    const opensLatin = 'V3.7.9 آخرین نسخهٔ کانفیگ است؛ به‌روزرسانی کنید.';
    await _pumpTvHome(tester, _tv(ShikooConnection.off, announce: opensLatin));
    expect(
      tester.widget<Text>(find.text(opensLatin)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('a silent pick of the app says what took its place', (
    tester,
  ) async {
    _tvScreen(tester);
    final de = bidiName('آلمان ۲');
    for (final (moved, second) in [
      (false, 'سریع‌ترین سرور، «$de»، جایش انتخاب شد.'),
      (true, 'اتصال همان لحظه به سریع‌ترین سرور، «$de»، رفت.'),
    ]) {
      await _pumpTvHome(
        tester,
        _tv(
          moved ? ShikooConnection.on : ShikooConnection.off,
          selected: 'آلمان ۲',
          notice: SilentReplaced(
            silent: '🇫🇮 فنلاند ۲',
            replacement: 'آلمان ۲',
            moved: moved,
          ),
        ),
      );
      expect(
        find.text('«${bidiName('فنلاند ۲')}» جواب نداد. $second'),
        findsOneWidget,
      );
    }
  });

  testWidgets('connected to a silent server, the button is not green alone', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.on,
        servers: const [
          ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
          ShikooServer(name: 'shikoonetturkey', type: 'WireGuard', ping: -1),
        ],
        selected: 'shikoonetturkey',
      ),
    );
    expect(find.text('وصل، بی‌اینترنت'), findsOneWidget);
    expect(
      find.text('اینترنت از «\u2068shikoonetturkey\u2069» رد نمی‌شود.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('جواب نمی‌دهد'),
      findsNothing,
      reason: 'one message, not two',
    );

    await _pumpTvHome(tester, _tv(ShikooConnection.off, selected: 'آلمان ۲'));
    expect(find.textContaining('رد نمی‌شود'), findsNothing);
  });

  testWidgets('no internet on the TV: the remote moves to «انتخاب سرور دیگر», '
      'whose OK puts it on the fastest other server by its ping; the card '
      'leaves the round button its size; on the streaming server the grey '
      'card, the remote left on the button', (tester) async {
    _tvScreen(tester);
    final holder = await _pumpTvHome(tester, _tv(ShikooConnection.on));
    expect(_focused(), 'power');
    final ring = tester.getSize(find.byType(PowerButton));
    holder.value = ShikooState(
      connection: ShikooConnection.on,
      connectedFor: holder.value.connectedFor,
      isTV: true,
      service: holder.value.service,
      servers: const [
        ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
        ShikooServer(name: 'فنلاند ۲', type: 'Vless', ping: 112),
        ShikooServer(name: 'هلند ۱', type: 'Vless', ping: 61),
      ],
      selected: 'فنلاند ۲',
      sorted: true,
      connectedNoTraffic: true,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('وصل، بی‌اینترنت'), findsOneWidget);
    expect(
      find.text('شاید این سرور روی اینترنت تو بسته باشد.'),
      findsOneWidget,
    );
    expect(find.byType(SpeedPills), findsNothing);
    expect(_focused(), 'انتخاب سرور دیگر');
    expect(tester.getSize(find.byType(PowerButton)), ring);
    expect(
      tester
          .getSize(find.widgetWithText(ShikooButton, 'انتخاب سرور دیگر'))
          .height,
      ShikooSizes.tv.button,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(_focused(), 'هلند ۱', reason: 'the fastest by ping, not the first');

    const free = '(رایگان) نماوا | فیلیمو | شیدا | گپ فیلم';
    await _pumpTvHome(
      tester,
      ShikooState(
        connection: ShikooConnection.on,
        connectedFor: holder.value.connectedFor,
        isTV: true,
        service: holder.value.service,
        servers: [
          ..._servers,
          const ShikooServer(name: free, type: 'Shadowsocks', ping: 120),
        ],
        selected: free,
        sorted: true,
        connectedNoTraffic: true,
      ),
    );
    await tester.pump();
    expect(find.text('وصل'), findsOneWidget);
    expect(find.text('فقط برای نماوا، فیلیمو، شیدا و گپ‌فیلم'), findsOneWidget);
    expect(find.textContaining('رد نمی‌شود'), findsNothing);
    expect(_focused(), 'power');
  });

  testWidgets('a refused or missing VPN consent is not blamed on the server', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.error, error: ShikooError.vpnRefused),
    );
    expect(find.text('وصل نشد'), findsOneWidget);
    expect(find.textContaining('اجازهٔ اتصال داده نشد.'), findsOneWidget);
    expect(find.textContaining('VPN'), findsNothing);
    expect(find.textContaining('جواب نداد'), findsNothing);

    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.error, error: ShikooError.vpnMissing),
    );
    expect(find.textContaining('پنجرهٔ اجازهٔ اتصال را ندارد'), findsOneWidget);

    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.error, error: ShikooError.vpnRefused),
      locale: 'en',
    );
    expect(find.textContaining('Permission to connect'), findsOneWidget);
    expect(find.textContaining('VPN'), findsNothing);
  });

  testWidgets('a dialog is as wide as the design, however short its text', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(tester, _tv(ShikooConnection.off));
    unawaited(
      showShikooDialog<void>(
        tester.element(find.byType(ShikooHome)),
        centered: true,
        children: (_) => const [Text('x')],
      ),
    );
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('x'),
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getSize(card.first).width, ShikooSizes.tv.dialog);
  });

  testWidgets('a long Persian support link still shows a QR, Shikoo support', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.on, supportUrl: 'https://t.me/${'پ' * 480}'),
    );
    await _focus(tester, 'پشتیبانی');
    await _press(tester, _ok);
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      ShikooLinks.support,
    );
  });

  testWidgets('with no service the button is off-limits and settings takes the '
      'remote', (tester) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: true,
        servers: [],
      ),
    );
    expect(find.text('سرویسی نیست'), findsOneWidget);
    expect(find.text('سرویسی روی این تلویزیون نیست'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PowerButton),
        matching: find.byType(Pressable),
      ),
      findsNothing,
    );
    expect(tester.getCenter(find.byType(PowerButton)).dy, closeTo(293, 0.5));

    expect(_focused(), 'تنظیمات');
    final moves = [
      ('تنظیمات', _down, 'پشتیبانی'),
      ('پشتیبانی', _up, 'تنظیمات'),
      ('تنظیمات', _towardCard, 'پشتیبانی'),
      ('پشتیبانی', _towardPower, 'تنظیمات'),
    ];
    for (final (from, key, to) in moves) {
      await _focus(tester, from);
      expect(await _press(tester, key), to, reason: '$from ${key.debugName}');
    }
    await _focus(tester, 'پشتیبانی');
    await _press(tester, _ok);
    expect(
      tester.widget<QrTile>(find.byType(QrTile)).data,
      ShikooLinks.support,
    );
  });

  testWidgets('once the services are removed, the remote leaves support '
      'for settings', (tester) async {
    _tvScreen(tester);
    final holder = await _pumpTvHome(tester, _tv(ShikooConnection.off));
    await _focus(tester, 'تنظیمات');
    holder.value = const ShikooState(
      connection: ShikooConnection.off,
      connectedFor: Duration.zero,
      isTV: true,
      servers: [],
    );
    await tester.pumpAndSettle();
    expect(await _press(tester, _down), 'پشتیبانی');
    expect(await _press(tester, _towardPower), 'تنظیمات');
  });

  testWidgets('the phone with no service has a plain support button', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      const ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: false,
        servers: [],
      ),
    );
    final support = tester.widget<ShikooButton>(
      find.widgetWithText(ShikooButton, 'پشتیبانی'),
    );
    expect(support.icon, isNull);
  });

  testWidgets('a server with no known country keeps the flag space, empty', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.off,
        servers: const [
          ShikooServer(name: 'آلمان ۲', type: 'Vless', ping: 84),
          ShikooServer(name: 'WireGuard 3', type: 'WireGuard', ping: 90),
        ],
        selected: 'آلمان ۲',
      ),
    );
    Finder flagOf(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(ServerRow)),
      matching: find.byType(Flag),
    );
    final blank = flagOf('WireGuard 3');
    expect(tester.getSize(blank), tester.getSize(flagOf('آلمان ۲')));
    expect(
      find.descendant(of: blank, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
  });

  testWidgets('on the TV the finished row is one stop: OK opens it on its '
      'first service, OK there shows renew, Back folds it again', (
    tester,
  ) async {
    _tvScreen(tester);
    final now = DateTime.now();
    await _pumpTvHome(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: true,
        servers: _servers,
        selected: 'فنلاند ۲',
        service: ShikooService(
          name: 'user123 · الماس',
          usedBytes: 1 << 30,
          totalBytes: 100 << 30,
          expire: now.add(const Duration(days: 30)),
        ),
        others: [
          ShikooService(
            id: 2,
            name: 'user555 · طلایی',
            usedBytes: 0,
            totalBytes: 0,
            expire: now.subtract(const Duration(days: 3)),
          ),
          const ShikooService(
            id: 3,
            name: 'user666 · طلایی',
            usedBytes: 100,
            totalBytes: 100,
          ),
        ],
      ),
    );
    final head = find.text('سرویس‌های تمام‌شده (۲)');
    Focus.of(tester.element(head)).requestFocus();
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.ancestor(of: head, matching: find.byType(Pressable)))
          .width,
      tester.getRect(find.byType(ServiceCard)).width,
      reason: 'the ring goes round the whole row, outside it as on a card',
    );
    expect(find.textContaining('user555'), findsNothing);

    await tester.sendKeyEvent(_ok);
    await tester.pumpAndSettle();
    final first = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.descendant(
        of: find.byElementPredicate((element) => element == first),
        matching: find.textContaining('user555'),
      ),
      findsOneWidget,
      reason: 'the latest end first, and the remote on it',
    );

    await tester.sendKeyEvent(_ok);
    await tester.pumpAndSettle();
    expect(tester.widget<QrTile>(find.byType(QrTile)).data, ShikooLinks.renew);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(QrTile), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('user555'), findsNothing, reason: 'folded');
    expect(
      Focus.of(tester.element(head)).hasPrimaryFocus,
      isTrue,
      reason: 'back on the row',
    );
  });

  testWidgets('on the TV the remote reaches the last finished service with its '
      'ring inside the safe area, and Up from the first goes to the head', (
    tester,
  ) async {
    _tvScreen(tester);
    final now = DateTime.now();
    await _pumpTvHome(
      tester,
      ShikooState(
        connection: ShikooConnection.off,
        connectedFor: Duration.zero,
        isTV: true,
        servers: _longList,
        selected: 'سرور 1',
        service: ShikooService(
          name: 'user123 · الماس',
          usedBytes: 1 << 30,
          totalBytes: 100 << 30,
          expire: now.add(const Duration(days: 30)),
        ),
        others: [
          for (var i = 1; i <= 4; i++)
            ShikooService(
              id: 10 + i,
              name: 'user55$i · طلایی',
              usedBytes: 0,
              totalBytes: 0,
              expire: now.subtract(Duration(days: i)),
            ),
        ],
      ),
    );
    await _focus(tester, 'سرور 12');
    await tester.sendKeyEvent(_down);
    await tester.pumpAndSettle();
    final head = find.text('سرویس‌های تمام‌شده (۴)');
    expect(Focus.of(tester.element(head)).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(_ok);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(_up);
    await tester.pumpAndSettle();
    expect(
      Focus.of(tester.element(head)).hasPrimaryFocus,
      isTrue,
      reason: 'Up from the first service is the head, not the server above',
    );

    // The verifier's path: up into the servers, then down a row at a time to the end.
    for (final key in [...List.filled(6, _up), ...List.filled(14, _down)]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    final ring = tester
        .getRect(
          find.ancestor(
            of: find.textContaining('user554'),
            matching: find.byType(Pressable),
          ),
        )
        .inflate(ShikooSizes.ring);
    expect(ring.bottom, lessThanOrEqualTo(540 - ShikooSizes.tv.safeY));

    final column = find.byType(SingleChildScrollView).first;
    final scroll = tester.widget<SingleChildScrollView>(column).controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final card = tester.getRect(
      find.ancestor(of: head, matching: find.byType(Container)).last,
    );
    expect(
      tester.getRect(column).bottom - card.bottom,
      Space.s2 + ShikooSizes.ring,
      reason: 'the column keeps room for the last ring',
    );
  });

  // Last, as the font stays for every test after: the two lines are Vazirmatn's.
  group('in Vazirmatn', () {
    setUpAll(loadShikooFonts);
    _switchOnTv();
    _topBarOnTv();
  });
}

void _topBarOnTv() {
  testWidgets('tv-c: the remote starts on the power button, up is «پشتیبانی» '
      'right above it, along the bar renew and Settings, and up from the card '
      'renew', (tester) async {
    _tvScreen(tester);
    await _pumpTvHome(tester, _tv(ShikooConnection.on));
    await tester.pumpAndSettle();
    expect(_focused(), 'power');
    final wrong = <String>[];
    for (final (from, key, to) in [
      ('power', _up, 'پشتیبانی'),
      ('پشتیبانی', _towardCard, 'تمدید'),
      ('پشتیبانی', _towardPower, 'تنظیمات'),
      ('به‌روزرسانی', _up, 'تمدید'),
      ('پینگ', _up, 'تمدید'),
    ]) {
      await _focus(tester, from);
      final got = await _press(tester, key);
      if (got != to) wrong.add('$from ${key.debugName} -> $got, not $to');
    }
    expect(wrong, isEmpty);
  });
}

void _switchOnTv() {
  testWidgets('on the TV a switch speaks in the fixed slot under the pill, red '
      'once it failed, in two lines even with long names; the remote, the '
      'button and the order stay put', (tester) async {
    _tvScreen(tester);
    const old = 'ضریب مصرف NE 4 x';
    const to = 'Italy (Gemini+YouTube بدون تبلیغ)';
    final servers = [
      const ShikooServer(name: old, type: 'WireGuard', ping: 84),
      const ShikooServer(name: to, type: 'Vless', ping: 112),
      ..._servers.skip(2),
    ];
    ShikooState state(ShikooSwitchStage? stage) {
      final base = _tv(
        ShikooConnection.on,
        servers: servers,
        selected: stage == ShikooSwitchStage.done ? to : old,
      );
      return ShikooState(
        connection: base.connection,
        connectedFor: base.connectedFor,
        isTV: true,
        service: base.service,
        servers: base.servers,
        selected: base.selected,
        switching: stage == null ? null : (to: to, from: old, stage: stage),
      );
    }

    final a = bidiName(to);
    for (final (locale, texts) in [
      (
        'fa',
        [
          'در حال رفتن به «$a»…',
          'حالا از «$a» وصلی.',
          '«$a» جواب نداد.\nسرور دیگری را امتحان کن.',
        ],
      ),
      (
        'en',
        [
          'Moving to “$a”…',
          'Now connected through “$a”.',
          '“$a” didn\'t answer.\nTry another server.',
        ],
      ),
    ]) {
      final holder = await _pumpTvHome(tester, state(null), locale: locale);
      await _focus(tester, to);
      final power = tester.getRect(find.byType(PowerButton));
      final order = _rowOrder(tester);
      for (final stage in ShikooSwitchStage.values) {
        holder.value = state(stage);
        await tester.pumpAndSettle();
        final why = '$locale ${stage.name}';
        final text = find.text(texts[stage.index]);
        expect(
          tester.widget<Text>(text).style?.color,
          stage == ShikooSwitchStage.failed
              ? ShikooColors.dark.danger
              : ShikooColors.dark.textMuted,
          reason: why,
        );
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
          reason: why,
        );
        expect(_focused(), to, reason: why);
        expect(tester.getRect(find.byType(PowerButton)), power, reason: why);
        expect(_rowOrder(tester), order, reason: why);
        expect(find.byType(SnackBar), findsNothing, reason: why);
      }
    }
  });
}
