import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

const _mpl = 'Mozilla Public License Version 2.0';

/// Long enough to scroll on the TV.
final _mplText = [
  _mpl,
  '==================================',
  for (var i = 1; i <= 40; i++) ...[
    '1.$i. "Term $i"',
    '    means a part of the licence that a reader scrolls past on the way down.',
  ],
].join('\n\n');

/// What the Go list and Flutter register, in small: one entry may name two packages.
List<LicenseEntry> _entries({bool openvpn = false}) => [
  const LicenseEntryWithLineBreaks([
    'github.com/metacubex/mihomo',
  ], 'GNU GENERAL PUBLIC LICENSE\n\nVersion 3, 29 June 2007'),
  LicenseEntryWithLineBreaks(['github.com/xtls/xray-core'], _mplText),
  const LicenseEntryWithLineBreaks([
    'github.com/sagernet/sing-box',
  ], 'GNU GENERAL PUBLIC LICENSE\n\nVersion 3, 29 June 2007'),
  const LicenseEntryWithLineBreaks([
    'golang.zx2c4.com/wireguard',
    'github.com/ajg/form',
  ], 'Permission is hereby granted, free of charge'),
  const LicenseEntryWithLineBreaks(['zlib'], 'zlib License'),
  const LicenseEntryWithLineBreaks(['abseil-cpp'], 'Apache License'),
  const LicenseEntryWithLineBreaks(['abseil-cpp'], 'BSD License'),
  const LicenseEntryWithLineBreaks(['github.com/Microsoft/go-winio'], 'MIT'),
  const LicenseEntryWithLineBreaks(['accessibility'], 'BSD License'),
  if (openvpn) LicenseEntryWithLineBreaks(['OpenVPN 3'], _mplText),
];

final _screen = GlobalKey();

Future<void> _pump(
  WidgetTester tester, {
  bool tv = false,
  String locale = 'fa',
  Brightness brightness = Brightness.light,
  bool openvpn = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  LicenseRegistry.reset();
  addTearDown(LicenseRegistry.reset);
  LicenseRegistry.addLicense(
    () => Stream.fromIterable(_entries(openvpn: openvpn)),
  );
  final view = tv
      ? ShikooSizes.tvCanvas
      : (shikooDesktop ? ShikooSizes.windowStart : const Size(412, 915));
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
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooVersionProvider.overrideWithValue('1.0.38'),
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
        home: const ShikooAbout(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _fa = lookupShikooL10n(const Locale('fa'));
final _en = lookupShikooL10n(const Locale('en'));

/// With `SHIKOO_SHOTS=<folder>`, the screen as a PNG there, beside the mockup's frames.
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

/// The remote's place: the first text inside the focused item.
String? _focused() {
  final element = FocusManager.instance.primaryFocus?.context as Element?;
  if (element == null) return null;
  String? first;
  void visit(Element child) {
    if (first != null) return;
    if (child.widget case final Text text) first = text.data;
    if (first == null) child.visitChildren(visit);
  }

  visit(element);
  return first;
}

Future<String?> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
  return _focused();
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

Future<void> _openList(WidgetTester tester, ShikooL10n l) async {
  await tester.tap(find.text(l.aboutLicenses));
  await tester.pumpAndSettle();
}

ScrollPosition _textScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(RawScrollbar),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadShikooFonts();
  });

  testWidgets('About has the row under its card; the list puts the cores this '
      'build registered first, then every other package A to Z', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      _top(tester, _fa.aboutLicenses),
      greaterThan(_top(tester, _fa.aboutSource)),
    );
    expect(find.text(_fa.aboutLicensesHelp), findsOneWidget);
    await _openList(tester, _fa);
    expect(find.text(_fa.licensesTitle), findsOneWidget);
    final cores = ['mihomo', 'Xray', 'sing-box', 'WireGuard'];
    final tops = [for (final core in cores) _top(tester, core)];
    expect(tops, [...tops]..sort(), reason: 'the cores in their order');
    expect(find.text('OpenVPN 3'), findsNothing, reason: 'not in this build');
    expect(
      find.text(
        '${bidiName('github.com/metacubex/mihomo')} · ${_fa.licenseCount(1)}',
      ),
      findsOneWidget,
    );
    expect(
      _top(tester, cores.last),
      lessThan(_top(tester, _fa.licensesOthers)),
    );
    final others = [
      'abseil-cpp',
      'accessibility',
      'github.com/ajg/form',
      'github.com/Microsoft/go-winio',
      'zlib',
    ];
    final otherTops = [for (final p in others) _top(tester, p)];
    expect(otherTops, [...otherTops]..sort(), reason: 'A to Z, any case');
    expect(
      _top(tester, others.first),
      greaterThan(_top(tester, _fa.licensesOthers)),
    );
    expect(
      find.text(_fa.licenseCount(2)),
      findsOneWidget,
      reason: 'abseil-cpp has two',
    );
    expect(
      find.text('golang.zx2c4.com/wireguard'),
      findsNothing,
      reason: 'listed once, as a core',
    );
  });

  testWidgets('a licence opens in its own page, left to right in a card', (
    tester,
  ) async {
    await _pump(tester);
    await _openList(tester, _fa);
    await tester.tap(find.text('Xray'));
    await tester.pumpAndSettle();
    expect(find.text('Xray'), findsOneWidget, reason: 'the page title');
    final text = find.text(_mpl);
    expect(text, findsOneWidget);
    expect(Directionality.of(tester.element(text)), TextDirection.ltr);
  });

  testWidgets('OpenVPN 3 joins the cores once its licence is registered', (
    tester,
  ) async {
    await _pump(tester, openvpn: true);
    await _openList(tester, _fa);
    expect(_top(tester, 'OpenVPN 3'), greaterThan(_top(tester, 'WireGuard')));
    expect(
      find.textContaining('OpenVPN 3'),
      findsOneWidget,
      reason: 'its package name is its title, so no second line repeats it',
    );
    expect(
      _top(tester, 'OpenVPN 3'),
      lessThan(_top(tester, _fa.licensesOthers)),
    );
  });

  testWidgets('the TV: the remote starts on the new row, then on the first '
      'core; the text card takes the remote and Up and Down scroll it', (
    tester,
  ) async {
    await _pump(tester, tv: true);
    expect(_focused(), _fa.aboutLicenses);
    expect(await _press(tester, LogicalKeyboardKey.select), 'mihomo');
    expect(await _press(tester, LogicalKeyboardKey.arrowDown), 'Xray');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text(_fa.licenseScrollTv), findsOneWidget);
    expect(_focused(), _mpl, reason: 'the card holds the remote');
    expect(_textScroll(tester).pixels, 0);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final down = _textScroll(tester).pixels;
    expect(down, greaterThan(0));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_textScroll(tester).pixels, greaterThan(down));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_textScroll(tester).pixels, closeTo(down, 1));
    expect(_focused(), _mpl, reason: 'the remote stays on the card');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_focused(), 'Xray', reason: 'Back: the remote on its row again');
  });

  testWidgets('Windows: the list is as wide as the Settings column', (
    tester,
  ) async {
    await _pump(tester);
    await _openList(tester, _fa);
    final row = find
        .ancestor(of: find.text('mihomo'), matching: find.byType(Pressable))
        .first;
    expect(tester.getSize(row).width, ShikooSizes.desktop.pane);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  group('shots', () {
    for (final device in ['phone', 'tv', 'win']) {
      for (final locale in ['fa', 'en']) {
        for (final b in Brightness.values) {
          testWidgets(
            '$device $locale ${b.name}',
            (tester) async {
              final tv = device == 'tv';
              final l = locale == 'fa' ? _fa : _en;
              final tag = '$device-$locale-${b.name}';
              await _pump(tester, tv: tv, locale: locale, brightness: b);
              expect(tester.takeException(), isNull);
              await _shot(tester, 'about-$tag');
              if (tv) {
                await _press(tester, LogicalKeyboardKey.select);
                await _press(tester, LogicalKeyboardKey.arrowDown);
              } else {
                await _openList(tester, l);
              }
              expect(tester.takeException(), isNull);
              await _shot(tester, 'list-$tag');
              if (tv) {
                await _press(tester, LogicalKeyboardKey.select);
                await _press(tester, LogicalKeyboardKey.arrowDown);
              } else {
                await tester.tap(find.text('Xray'));
                await tester.pumpAndSettle();
              }
              expect(tester.takeException(), isNull);
              await _shot(tester, 'text-$tag');
            },
            variant: device == 'win'
                ? TargetPlatformVariant.only(TargetPlatform.windows)
                : const DefaultTestVariant(),
          );
        }
      }
    }
  });
}
