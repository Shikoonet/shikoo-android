import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/dialogs.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}) async {
  final holder = ValueNotifier(state);
  addTearDown(holder.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
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
  return context.findAncestorWidgetOfExactType<ShikooButton>()?.label;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

Future<void> _focus(WidgetTester tester, String what) async {
  final owner = what == 'power'
      ? find.byType(PowerButton)
      : find.ancestor(of: find.text(what), matching: find.byType(Pressable));
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
  testWidgets('the TV power button sits at 269dp, with or without a server', (
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
      centres[key] = tester.getCenter(find.byType(PowerButton));
    }
    expect(centres.values.toSet(), hasLength(1), reason: '$centres');
    expect(centres.values.first.dy, closeTo(269, 0.5));
  });

  testWidgets('the remote follows the order the TV mockup sets', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(tester, _tv(ShikooConnection.off));
    expect(_focused(), 'power');
    final moves = [
      ('power', _up, 'تنظیمات'),
      ('power', _down, 'power'),
      ('power', _towardPower, 'power'),
      ('power', _towardCard, 'فنلاند ۲'),
      ('تنظیمات', _down, 'power'),
      ('به‌روزرسانی', _up, 'تنظیمات'),
      ('به‌روزرسانی', _down, 'پشتیبانی'),
      ('به‌روزرسانی', _towardPower, 'power'),
      ('تمدید', _up, 'به‌روزرسانی'),
      ('پشتیبانی', _up, 'به‌روزرسانی'),
      ('تمدید', _down, 'پینگ همه'),
      ('پشتیبانی', _down, 'پینگ همه'),
      ('تمدید', _towardPower, 'پشتیبانی'),
      ('پشتیبانی', _towardPower, 'power'),
      ('پشتیبانی', _towardCard, 'تمدید'),
      ('تمدید', _towardCard, 'تمدید'),
      ('پینگ همه', _up, 'پشتیبانی'),
      ('پینگ همه', _down, 'آلمان ۲'),
      ('پینگ همه', _towardPower, 'power'),
      ('آلمان ۲', _up, 'پینگ همه'),
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

  testWidgets('with no server chosen, the remote goes to the first row', (
    tester,
  ) async {
    _tvScreen(tester);
    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.off, selected: null, pick: ShikooPick.finding),
    );
    expect(await _press(tester, _towardCard), 'آلمان ۲');
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
    expect(find.text('به‌روز نشد، فهرستِ ۲ روز پیش'), findsOneWidget);

    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.off,
        refresh: ShikooRefresh.failed,
        notice: const RefreshFailed(),
      ),
    );
    expect(find.textContaining('دکمهٔ وسط را دوباره بزن'), findsOneWidget);
  });

  testWidgets(
    "a short card starts where a long one does, at the design's 79dp",
    (tester) async {
      _tvScreen(tester);
      for (final servers in [_longList, _longList.take(2).toList()]) {
        await _pumpTvHome(
          tester,
          _tv(ShikooConnection.off, servers: servers, selected: 'سرور 1'),
        );
        expect(
          tester.getTopLeft(find.byType(ServiceCard)).dy,
          79,
          reason: '${servers.length} servers',
        );
      }
    },
  );

  testWidgets('on ping-all or a row, the list head goes to the top', (
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
    double headTop() =>
        tester.getTopLeft(find.textContaining('سریع‌ترین بالا')).dy -
        tester.getTopLeft(column).dy;

    await _focus(tester, 'پینگ همه');
    expect(headTop(), lessThan(Space.s4 * 2 + Space.s2));
    expect(await _press(tester, _down), 'سرور 1');
    expect(headTop(), lessThan(Space.s4 * 2 + Space.s2));

    await _focus(tester, 'سرور 12');
    await _focus(tester, 'به‌روزرسانی');
    expect(
      tester.getTopLeft(find.byType(ServiceCard)).dy -
          tester.getTopLeft(column).dy,
      Space.s2,
      reason: 'back on the update button, the column is at its very top',
    );
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
      find.textContaining('«آمریکا ۲» دیگر در اشتراکت نیست.'),
      findsOneWidget,
    );
    expect(find.textContaining('همان لحظه'), findsOneWidget);

    await _pumpTvHome(
      tester,
      _tv(
        ShikooConnection.off,
        notice: const ServersChanged(added: 2, removed: ['انگلیس']),
      ),
    );
    expect(find.textContaining('۲ سرور تازه آمد.'), findsOneWidget);
    expect(find.textContaining('«انگلیس» حذف شد.'), findsOneWidget);
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
    expect(find.text('اعتبار تا ۴ آبان ۱۴۰۵'), findsOneWidget);
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
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(qr(), isNull);
    expect(_focused(), 'تمدید');

    await _focus(tester, 'پشتیبانی');
    await _press(tester, _ok);
    expect(qr(), ShikooLinks.support, reason: 'the panel sends a bare t.me');
    expect(await _press(tester, _ok), 'پشتیبانی', reason: 'Close');

    await _pumpTvHome(
      tester,
      _tv(ShikooConnection.on, supportUrl: 'https://t.me/shikoo_help'),
    );
    await _focus(tester, 'پشتیبانی');
    await _press(tester, _ok);
    expect(qr(), 'https://t.me/shikoo_help');
  });

  testWidgets("the panel's announcement shows every line", (tester) async {
    _tvScreen(tester);
    const announce =
        'آخرین نسخه کانفیگ: V3.7.9\nاگر نسخه شما پایین‌تر است، به‌روزرسانی کنید.';
    await _pumpTvHome(tester, _tv(ShikooConnection.off, announce: announce));
    final text = tester.renderObject<RenderParagraph>(find.text(announce));
    expect(text.didExceedMaxLines, isFalse);
    expect(text.size.height, greaterThan(text.preferredLineHeight * 1.5));
  });

  testWidgets('a silent pick of the app says what took its place', (
    tester,
  ) async {
    _tvScreen(tester);
    for (final (moved, second) in [
      (false, 'سریع‌ترین سرور، «آلمان ۲»، جایش انتخاب شد.'),
      (true, 'اتصال همان لحظه به سریع‌ترین سرور، «آلمان ۲»، رفت.'),
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
      expect(find.text('«فنلاند ۲» جواب نداد. $second'), findsOneWidget);
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
    expect(find.text('وصل'), findsOneWidget);
    final warning = find.textContaining('«shikoonetturkey» جواب نمی‌دهد.');
    expect(warning, findsOneWidget);
    expect(tester.widget<Text>(warning).style?.color, ShikooColors.dark.danger);

    await _pumpTvHome(tester, _tv(ShikooConnection.off, selected: 'آلمان ۲'));
    expect(find.textContaining('جواب نمی‌دهد'), findsNothing);
  });
}
