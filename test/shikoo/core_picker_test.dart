import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/cores.dart' show viaLabel;
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart' show SvgIcon;
import 'package:fl_clash/shikoo/ui/report.dart' show SwitchRow;
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

class _Controller extends Mock implements ShikooController {}

const _mihomo = ShikooCore.mihomo;
const _xray = ShikooCore.xray;
const _singBox = ShikooCore.singBox;
const _wireguard = ShikooCore.wireguard;
const _openvpn = ShikooCore.openvpn;

/// The mockup's four kinds, in the engine's order: sing-box for WireGuard is not ready, and
/// OpenVPN is on its official engine alone (Sam, 2026-10-30).
List<ShikooCoreRow> _rows({
  ShikooCore vless = _mihomo,
  ShikooCore wireguard = _mihomo,
  bool tunnel = true,
}) => [
  (
    protocol: ShikooProtocol.vless,
    chosen: vless,
    defaultCore: _mihomo,
    carrier: vless,
    options: const [
      (core: _mihomo, ready: true),
      (core: _xray, ready: true),
      (core: _singBox, ready: true),
    ],
  ),
  (
    protocol: ShikooProtocol.wireguard,
    chosen: wireguard,
    defaultCore: _mihomo,
    carrier: !tunnel && wireguard == _wireguard ? _mihomo : wireguard,
    options: const [
      (core: _mihomo, ready: true),
      (core: _xray, ready: true),
      (core: _singBox, ready: false),
      (core: _wireguard, ready: true),
    ],
  ),
  (
    protocol: ShikooProtocol.openvpn,
    chosen: _openvpn,
    defaultCore: _openvpn,
    carrier: _openvpn,
    options: const [(core: _openvpn, ready: true)],
  ),
  (
    protocol: ShikooProtocol.ssh,
    chosen: _mihomo,
    defaultCore: _mihomo,
    carrier: _mihomo,
    options: const [
      (core: _mihomo, ready: true),
      (core: _singBox, ready: true),
    ],
  ),
];

ShikooState _settings({
  bool tv = false,
  List<ShikooCoreRow>? cores,
  bool iranDirect = true,
  ShikooCoreSwitch? coreSwitch,
}) => ShikooState(
  connection: coreSwitch == null ? ShikooConnection.off : ShikooConnection.on,
  connectedFor: Duration.zero,
  isTV: tv,
  servers: const [],
  cores: cores ?? _rows(),
  iranDirect: iranDirect,
  coreSwitch: coreSwitch,
);

/// x-via: «فنلاند ۲», in use, is VLESS over XHTTP, which only sing-box does not know.
ShikooState _home({
  bool tv = false,
  bool en = false,
  ShikooCore vless = _singBox,
  ShikooCoreSwitch? coreSwitch,
  ShikooSwitch? switching,
}) {
  final names = en
      ? ['Netherlands 1', 'Germany 2', 'Finland 2', 'UK 1', 'USA 2']
      : ['هلند ۱', 'آلمان ۲', 'فنلاند ۲', 'انگلیس ۱', 'آمریکا ۲'];
  return ShikooState(
    connection: ShikooConnection.on,
    connectedFor: const Duration(minutes: 12, seconds: 47),
    isTV: tv,
    service: ShikooService(
      name: en ? '5550123 · Diamond' : '5550123 · الماس',
      usedBytes: 33 << 30,
      totalBytes: 100 << 30,
      expire: DateTime.now().add(const Duration(days: 23)),
      updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
    servers: [
      ShikooServer(
        name: names[0],
        type: 'WireGuard',
        ping: 78,
        protocol: ShikooProtocol.wireguard,
      ),
      ShikooServer(
        name: names[1],
        type: vless == _mihomo ? 'Vless' : 'Socks5',
        ping: 84,
        protocol: ShikooProtocol.vless,
        core: vless,
      ),
      ShikooServer(
        name: names[2],
        type: vless == _xray ? 'Socks5' : 'Vless',
        ping: 112,
        protocol: ShikooProtocol.vless,
        core: vless == _singBox ? _mihomo : vless,
      ),
      ShikooServer(
        name: names[3],
        type: 'Ssh',
        ping: 140,
        protocol: ShikooProtocol.ssh,
      ),
      ShikooServer(
        name: names[4],
        type: 'OpenVPN',
        ping: 188,
        protocol: ShikooProtocol.openvpn,
        core: _openvpn,
      ),
    ],
    selected: names[2],
    cores: _rows(vless: vless),
    coreSwitch: coreSwitch,
    switching: switching,
  );
}

typedef _Rig = ({_Controller controller, ValueNotifier<ShikooState> holder});

final _screen = GlobalKey();

Future<_Rig> _pump(
  WidgetTester tester,
  ShikooState state, {
  Widget home = const ShikooSettings(),
  String locale = 'fa',
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool proxy = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final tv = state.isTV;
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
  final controller = _Controller();
  when(() => controller.setCore(any(), any())).thenAnswer((_) async {});
  when(() => controller.setIranDirect(any())).thenAnswer((_) async {});
  final holder = ValueNotifier(state);
  addTearDown(holder.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooControllerProvider.overrideWithValue(controller),
        shikooVersionProvider.overrideWithValue('1.0.38'),
        if (proxy) shikooTunnelProvider.overrideWithValue(false),
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
        home: home,
      ),
    ),
  );
  final screen = tester.element(find.byKey(_screen));
  // Settings' language switch shows the saved look, not the app's locale.
  await ProviderScope.containerOf(
    screen,
  ).read(shikooLookProvider.notifier).setLanguage(locale);
  await tester.runAsync(
    () => precacheImage(const AssetImage(shikooMarkAsset), screen),
  );
  await tester.pumpAndSettle();
  return (controller: controller, holder: holder);
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

/// The line under [core]'s name in the open list, or null.
String? _lineUnder(String core) {
  final column = find
      .ancestor(of: find.text(core).last, matching: find.byType(Column))
      .first;
  final texts = find
      .descendant(of: column, matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .toList();
  return texts.length > 1 ? texts[1] : null;
}

/// Puts the remote on the row that holds [text].
Future<void> _focusOn(WidgetTester tester, String text) async {
  final pressable = find
      .ancestor(of: find.text(text).first, matching: find.byType(Pressable))
      .first;
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

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

/// Persian text starts at its right edge.
double _start(WidgetTester tester, String text) =>
    tester.getTopRight(find.text(text).first).dx;

void main() {
  setUpAll(() async {
    registerFallbackValue(ShikooProtocol.vless);
    registerFallbackValue(ShikooCore.mihomo);
    await loadShikooFonts();
  });

  // Sam, 2026-10-22: with the official WireGuard picked, Proxy mode carries it on mihomo and says so.
  for (final tunnel in [true, false]) {
    test(
      'the official WireGuard picked, «با mihomo» shows only where it does not '
      'carry: in Proxy mode (tunnel $tunnel)',
      () {
        final wg = shikooCoreSpecs[_wireguard]!;
        final specs = {
          ...shikooCoreSpecs,
          _wireguard: (ready: true, shape: wg.shape, serves: wg.serves),
        };
        const picks = {ShikooProtocol.wireguard: _wireguard};
        final rows = coreRows(
          {ShikooProtocol.wireguard},
          picks,
          specs: specs,
          tunnel: tunnel,
        );
        final server = ShikooServer(
          name: 'W',
          type: 'WireGuard',
          protocol: ShikooProtocol.wireguard,
          core: coreFor(
            const {'type': 'WireGuard'},
            picks,
            specs: specs,
            tunnel: tunnel,
          ),
        );
        expect(rows.single.chosen, _wireguard);
        expect(rows.single.carrier, tunnel ? _wireguard : _mihomo);
        expect(
          viaLabel(_fa, server, rows),
          tunnel ? isNull : _fa.viaCore(bidiName(_fa.coreMihomo)),
        );
      },
    );
  }

  group('phone', () {
    testWidgets('«اتصال» sits under «زبان» with its switch on, and «هسته‌ها» '
        'under it: a row per kind, each core named in Persian', (tester) async {
      final rig = await _pump(tester, _settings());
      expect(
        _top(tester, _fa.language),
        lessThan(_top(tester, _fa.connectionGroup)),
      );
      expect(
        _top(tester, _fa.connectionGroup),
        lessThan(_top(tester, _fa.coresGroup)),
      );
      expect(_top(tester, _fa.coresGroup), lessThan(_top(tester, _fa.account)));
      final toggle = tester.widget<SwitchRow>(find.byType(SwitchRow).first);
      expect(toggle.on, isTrue);
      expect(toggle.help, _fa.iranDirectHelp);
      for (final kind in [
        _fa.protocolVless,
        _fa.protocolWireguard,
        _fa.protocolOpenvpn,
        _fa.protocolSsh,
      ]) {
        expect(find.text(kind), findsOneWidget);
      }
      expect(find.text(_fa.coreMihomo), findsNWidgets(3));
      expect(find.text(_fa.coreOpenvpn), findsOneWidget);
      expect(find.text(_fa.coresNote), findsOneWidget);
      await _shot(tester, 'a-set-light');

      await tester.tap(find.text(_fa.iranDirect));
      await tester.pumpAndSettle();
      verify(() => rig.controller.setIranDirect(false)).called(1);
      rig.holder.value = _settings(iranDirect: false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchRow>(find.byType(SwitchRow).first).on,
        isFalse,
      );
    });

    testWidgets('only the kinds the services have get a row; none, no group', (
      tester,
    ) async {
      final rig = await _pump(tester, _settings(cores: [_rows()[1]]));
      expect(find.text(_fa.protocolWireguard), findsOneWidget);
      expect(find.text(_fa.protocolVless), findsNothing);
      rig.holder.value = _settings(cores: const []);
      await tester.pumpAndSettle();
      expect(find.text(_fa.coresGroup), findsNothing);
      expect(find.text(_fa.connectionGroup), findsOneWidget);
    });

    testWidgets('«WireGuard» opens the sheet: mihomo is the default, sing-box '
        'is greyed with «به‌زودی», and a tap picks and closes', (tester) async {
      final rig = await _pump(tester, _settings());
      await tester.ensureVisible(find.text(_fa.protocolWireguard).first);
      await tester.tap(find.text(_fa.protocolWireguard).first);
      await tester.pumpAndSettle();
      final title = _fa.corePickTitle(bidiName(_fa.protocolWireguard));
      expect(find.text(title), findsOneWidget);
      expect(
        find.text(
          '${_fa.corePickForAll(bidiName(_fa.protocolWireguard))} ${_fa.corePickAgain}',
        ),
        findsOneWidget,
      );
      expect(find.text(_fa.coreDefault), findsOneWidget);
      expect(find.text(_fa.coreWireguardHelp), findsOneWidget);
      expect(find.text(_fa.coreSoon), findsOneWidget);
      // The mockup's order: the official engine before sing-box.
      final order = [
        _fa.coreXray,
        _fa.coreWireguard,
        _fa.coreSingBox,
      ].map((name) => tester.getTopLeft(find.text(name).last).dy).toList();
      expect(order, [...order]..sort());
      await _shot(tester, 'a-sheet-light');

      await tester.tap(find.text(_fa.coreSingBox).last);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget, reason: 'still open');
      verifyNever(() => rig.controller.setCore(any(), any()));

      await tester.tap(find.text(_fa.coreXray).last);
      await tester.pumpAndSettle();
      expect(find.text(title), findsNothing);
      verify(
        () => rig.controller.setCore(ShikooProtocol.wireguard, _xray),
      ).called(1);
    });

    for (final b in Brightness.values) {
      testWidgets('OpenVPN is locked on its official engine: the row names it '
          'with no ⌄, and a tap opens nothing (${b.name})', (tester) async {
        final rig = await _pump(tester, _settings(), brightness: b);
        final label = find.text(_fa.protocolOpenvpn).first;
        final row = find.ancestor(of: label, matching: find.byType(Row)).first;
        expect(
          find.descendant(of: row, matching: find.text(_fa.coreOpenvpn)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.byType(SvgIcon)),
          findsNothing,
        );
        expect(
          find.ancestor(of: label, matching: find.byType(Pressable)),
          findsNothing,
        );
        await tester.ensureVisible(label);
        await tester.tap(label);
        await tester.pumpAndSettle();
        expect(
          find.text(_fa.corePickTitle(bidiName(_fa.protocolOpenvpn))),
          findsNothing,
        );
        verifyNever(() => rig.controller.setCore(any(), any()));
        await _shot(tester, 'o-locked-${b.name}');
      });
    }

    testWidgets('«پیش‌فرض» stands under the core the row names as default', (
      tester,
    ) async {
      await _pump(
        tester,
        _settings(
          cores: const [
            (
              protocol: ShikooProtocol.wireguard,
              chosen: _mihomo,
              defaultCore: _wireguard,
              carrier: _mihomo,
              options: [
                (core: _mihomo, ready: true),
                (core: _wireguard, ready: true),
              ],
            ),
          ],
        ),
      );
      await tester.tap(find.text(_fa.protocolWireguard).first);
      await tester.pumpAndSettle();
      expect(_lineUnder(_fa.coreWireguard), _fa.coreDefault);
      expect(_lineUnder(_fa.coreMihomo), isNull);
    });

    testWidgets('the current core picked again changes nothing', (
      tester,
    ) async {
      final rig = await _pump(tester, _settings());
      await tester.ensureVisible(find.text(_fa.protocolVless).first);
      await tester.tap(find.text(_fa.protocolVless).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_fa.coreDefault));
      await tester.pumpAndSettle();
      expect(
        find.text(_fa.corePickTitle(bidiName(_fa.protocolVless))),
        findsNothing,
      );
      verifyNever(() => rig.controller.setCore(any(), any()));
    });

    for (final b in Brightness.values) {
      testWidgets('English: the official engine picked, the row says so '
          '(${b.name})', (tester) async {
        await _pump(
          tester,
          _settings(cores: _rows(wireguard: _wireguard)),
          locale: 'en',
          brightness: b,
        );
        expect(find.text(_en.coreWireguard), findsOneWidget);
        await tester.ensureVisible(find.text(_en.protocolWireguard).first);
        await tester.tap(find.text(_en.protocolWireguard).first);
        await tester.pumpAndSettle();
        expect(
          find.text(_en.corePickTitle(bidiName(_en.protocolWireguard))),
          findsOneWidget,
        );
        expect(find.text(_en.coreSoon), findsOneWidget);
        await _shot(tester, 'a-sheet-en-${b.name}');
      });
    }

    for (final b in Brightness.values) {
      testWidgets('sing-box picked for VLESS says some servers stay on '
          'mihomo (${b.name})', (tester) async {
        await _pump(
          tester,
          _settings(cores: _rows(vless: _singBox)),
          brightness: b,
        );
        await tester.ensureVisible(find.text(_fa.protocolVless).first);
        await tester.tap(find.text(_fa.protocolVless).first);
        await tester.pumpAndSettle();
        expect(find.text(_fa.coreSingBoxVless), findsOneWidget);
        await _shot(tester, 'x-sheet-${b.name}');
      });
    }

    testWidgets('large text ×1.45: the sheet and the rows fit', (tester) async {
      await _pump(tester, _settings(), textScale: 1.45);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(_fa.protocolWireguard).first);
      await tester.tap(find.text(_fa.protocolWireguard).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _shot(tester, 'a-sheet-145-light');
    });

    for (final b in Brightness.values) {
      testWidgets('«با mihomo» stands only beside a server the chosen core '
          'does not know (${b.name})', (tester) async {
        final rig = await _pump(
          tester,
          _home(),
          home: const ShikooHome(),
          brightness: b,
        );
        final via = _fa.viaCore(bidiName(_fa.coreMihomo));
        expect(find.text(via), findsOneWidget);
        final row = find.ancestor(
          of: find.text(via),
          matching: find.byType(ServerRow),
        );
        expect(
          find.descendant(of: row, matching: find.text('فنلاند ۲')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text(via));
        await _shot(tester, 'x-via-${b.name}');

        for (final known in [_mihomo, _xray]) {
          rig.holder.value = _home(vless: known);
          await tester.pumpAndSettle();
          expect(find.text(via), findsNothing, reason: known.name);
        }
      });

      testWidgets('a core switch ending leaves the bar to a server switch '
          'still on its way (${b.name})', (tester) async {
        final rig = await _pump(
          tester,
          _home(vless: _xray),
          home: const ShikooHome(),
          brightness: b,
        );
        const done = (
          protocol: ShikooProtocol.vless,
          to: _xray,
          stage: ShikooSwitchStage.done,
        );
        const moving = (
          to: 'آلمان ۲',
          from: 'فنلاند ۲',
          stage: ShikooSwitchStage.moving,
        );
        const coreMoving = (
          protocol: ShikooProtocol.vless,
          to: _xray,
          stage: ShikooSwitchStage.moving,
        );
        const arrived = (
          to: 'آلمان ۲',
          from: 'فنلاند ۲',
          stage: ShikooSwitchStage.done,
        );
        final core = _fa.coreSwitched(bidiName(_fa.coreXray));
        final server = _fa.switchingTo(serverName('آلمان ۲'));
        final coreOnWay = _fa.coreSwitching(bidiName(_fa.coreXray));
        final serverDone = _fa.switchedTo(serverName('آلمان ۲'));
        for (final (state, line) in [
          (_home(vless: _xray, coreSwitch: done), core),
          (_home(vless: _xray, coreSwitch: done, switching: moving), server),
          (_home(vless: _xray, switching: moving), server),
          // The other way: a server switch ending leaves the bar to the core's.
          (_home(vless: _xray, coreSwitch: coreMoving), coreOnWay),
          (
            _home(vless: _xray, coreSwitch: coreMoving, switching: arrived),
            serverDone,
          ),
          (_home(vless: _xray, coreSwitch: coreMoving), coreOnWay),
        ]) {
          rig.holder.value = state;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(SnackBar), findsOneWidget, reason: line);
          expect(find.text(line), findsOneWidget);
        }
        await _shot(tester, 'a-switch-then-server-${b.name}');
        rig.holder.value = _home(vless: _xray);
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('a core picked while connected: the server switch\'s bar, '
          'over Settings too, and only «وصل نشد» when it fails (${b.name})', (
        tester,
      ) async {
        final rig = await _pump(
          tester,
          _home(vless: _xray),
          home: const ShikooHome(),
          brightness: b,
        );
        openSettings(tester.element(find.byType(ShikooHome)));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(_fa.coresGroup));
        await tester.pumpAndSettle();
        final xray = _fa.coreXray;
        ShikooState at(ShikooSwitchStage stage) => _home(
          vless: _xray,
          coreSwitch: (protocol: ShikooProtocol.vless, to: _xray, stage: stage),
        );
        for (final (stage, line, shot) in [
          (
            ShikooSwitchStage.moving,
            _fa.coreSwitching(bidiName(xray)),
            'a-switch',
          ),
          (
            ShikooSwitchStage.done,
            _fa.coreSwitched(bidiName(xray)),
            'a-switch-done',
          ),
          (ShikooSwitchStage.failed, _fa.powerFailed, 'a-switch-failed'),
        ]) {
          rig.holder.value = at(stage);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text(line), findsOneWidget, reason: stage.name);
          expect(find.byType(ShikooSettings), findsOneWidget);
          await _shot(tester, '$shot-${b.name}');
        }
        expect(find.text(_fa.coreSwitching(bidiName(xray))), findsNothing);
        expect(find.text(_fa.coreSwitched(bidiName(xray))), findsNothing);

        rig.holder.value = _home(vless: _xray);
        await tester.pumpAndSettle();
        expect(find.text(_fa.powerFailed), findsNothing);
      });
    }
  });

  group('TV', () {
    testWidgets('«اتصال» is in the first column, «هسته‌ها» in the second, '
        'under «زبان»', (tester) async {
      await _pump(tester, _settings(tv: true));
      // Persian: the first column is the right one.
      expect(
        _start(tester, _fa.connectionGroup),
        closeTo(_start(tester, _fa.appearance), 1),
      );
      expect(
        _start(tester, _fa.connectionGroup),
        greaterThan(_start(tester, _fa.coresGroup)),
      );
      expect(
        _start(tester, _fa.coresGroup),
        closeTo(_start(tester, _fa.language), 1),
      );
      expect(
        _top(tester, _fa.language),
        lessThan(_top(tester, _fa.coresGroup)),
      );
      expect(
        _top(tester, _fa.appearance),
        lessThan(_top(tester, _fa.connectionGroup)),
      );
    });

    testWidgets('the remote: OK on a row opens the dialog on the current '
        'core, sing-box is passed by, OK picks, Back closes', (tester) async {
      final rig = await _pump(tester, _settings(tv: true));
      expect(
        await _press(tester, LogicalKeyboardKey.arrowDown),
        _fa.iranDirect,
        reason: 'from «ظاهر» down to «اتصال»',
      );
      await _press(tester, LogicalKeyboardKey.select);
      verify(() => rig.controller.setIranDirect(false)).called(1);

      await _focusOn(tester, _fa.protocolWireguard);
      expect(_focused(), _fa.protocolWireguard);
      await _shot(tester, 'a-tv-light');

      expect(await _press(tester, LogicalKeyboardKey.select), _fa.coreMihomo);
      expect(
        find.text(_fa.corePickTitle(bidiName(_fa.protocolWireguard))),
        findsOneWidget,
      );
      expect(await _press(tester, LogicalKeyboardKey.arrowDown), _fa.coreXray);
      await _shot(tester, 'a-tv-dialog-light');
      expect(
        await _press(tester, LogicalKeyboardKey.arrowDown),
        _fa.coreWireguard,
      );
      expect(
        await _press(tester, LogicalKeyboardKey.arrowDown),
        _fa.coreWireguard,
        reason: 'sing-box, not ready, takes no remote',
      );
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(
        await _press(tester, LogicalKeyboardKey.select),
        _fa.protocolWireguard,
        reason: 'closed, the remote back on its row',
      );
      verify(
        () => rig.controller.setCore(ShikooProtocol.wireguard, _xray),
      ).called(1);

      await _press(tester, LogicalKeyboardKey.select);
      expect(
        find.text(_fa.corePickTitle(bidiName(_fa.protocolWireguard))),
        findsOneWidget,
      );
      expect(
        await _press(tester, LogicalKeyboardKey.escape),
        _fa.protocolWireguard,
      );
      expect(
        find.text(_fa.corePickTitle(bidiName(_fa.protocolWireguard))),
        findsNothing,
      );
      verifyNever(() => rig.controller.setCore(any(), any()));
    });

    for (final b in Brightness.values) {
      testWidgets('the remote passes over the locked OpenVPN row, so no list '
          'opens for it (${b.name})', (tester) async {
        final rig = await _pump(tester, _settings(tv: true), brightness: b);
        await _focusOn(tester, _fa.protocolWireguard);
        expect(
          await _press(tester, LogicalKeyboardKey.arrowDown),
          _fa.protocolSsh,
        );
        await _shot(tester, 'o-tv-locked-${b.name}');
        expect(
          await _press(tester, LogicalKeyboardKey.arrowUp),
          _fa.protocolWireguard,
        );
        verifyNever(() => rig.controller.setCore(any(), any()));
      });
    }

    testWidgets('large text ×1.45: Settings and the dialog fit', (
      tester,
    ) async {
      await _pump(tester, _settings(tv: true), textScale: 1.45);
      expect(tester.takeException(), isNull);
      await _shot(tester, 'a-tv-145-light');
      await _focusOn(tester, _fa.protocolWireguard);
      await _press(tester, LogicalKeyboardKey.select);
      expect(tester.takeException(), isNull);
      expect(find.text(_fa.coreSoon), findsOneWidget);
      await _shot(tester, 'a-tv-dialog-145-light');
    });

    testWidgets('with no kind of server yet, no «هسته‌ها», and «حساب» crosses '
        'to the second column', (tester) async {
      await _pump(tester, _settings(tv: true, cores: const []));
      expect(find.text(_fa.coresGroup), findsNothing);
      expect(
        _start(tester, _fa.account),
        closeTo(_start(tester, _fa.language), 1),
      );
      await _shot(tester, 'i-tv-no-cores-light');
    });

    testWidgets('English, dark: the switch under «Connection»', (tester) async {
      await _pump(
        tester,
        _settings(tv: true),
        locale: 'en',
        brightness: Brightness.dark,
      );
      expect(
        await _press(tester, LogicalKeyboardKey.arrowDown),
        _en.iranDirect,
      );
      await _shot(tester, 'i-tv-en-dark');
    });

    testWidgets('«via mihomo» beside the server, English, dark', (
      tester,
    ) async {
      await _pump(
        tester,
        _home(tv: true, en: true),
        home: const ShikooHome(),
        locale: 'en',
        brightness: Brightness.dark,
      );
      expect(find.text(_en.viaCore(bidiName(_en.coreMihomo))), findsOneWidget);
      await _shot(tester, 'x-tv-en-dark');
    });

    for (final b in Brightness.values) {
      testWidgets('a core switch shows in the slot under the server pill, '
          'a failure in red (${b.name})', (tester) async {
        final rig = await _pump(
          tester,
          _home(
            tv: true,
            vless: _xray,
            coreSwitch: (
              protocol: ShikooProtocol.vless,
              to: _xray,
              stage: ShikooSwitchStage.moving,
            ),
          ),
          home: const ShikooHome(),
          brightness: b,
        );
        final news = find.text(_fa.coreSwitching(bidiName(_fa.coreXray)));
        expect(news, findsOneWidget);
        final t = ShikooTheme.of(tester.element(news));
        expect(tester.widget<Text>(news).style?.color, t.c.textMuted);
        await _shot(tester, 'a-tv-home-switch-${b.name}');

        rig.holder.value = _home(
          tv: true,
          vless: _xray,
          coreSwitch: (
            protocol: ShikooProtocol.vless,
            to: _xray,
            stage: ShikooSwitchStage.failed,
          ),
        );
        await tester.pumpAndSettle();
        final failed = find.text(_fa.powerFailed);
        expect(tester.widget<Text>(failed).style?.color, t.c.danger);
        await _shot(tester, 'a-tv-home-failed-${b.name}');
      });

      testWidgets('on Settings a core switch holds the hint\'s place for its '
          'time, the remote and the rows staying put (${b.name})', (
        tester,
      ) async {
        final cores = _rows(vless: _xray);
        final rig = await _pump(
          tester,
          _settings(tv: true, cores: cores),
          brightness: b,
        );
        final hint = find.text(_fa.backHintTv);
        final slot = tester.getRect(hint);
        final rows = _top(tester, _fa.coresGroup);
        final remote = _focused();
        for (final (stage, line, shot) in [
          (
            ShikooSwitchStage.moving,
            _fa.coreSwitching(bidiName(_fa.coreXray)),
            'a-tv-set-switch',
          ),
          (
            ShikooSwitchStage.done,
            _fa.coreSwitched(bidiName(_fa.coreXray)),
            null,
          ),
          (ShikooSwitchStage.failed, _fa.powerFailed, 'a-tv-set-failed'),
        ]) {
          rig.holder.value = _settings(
            tv: true,
            cores: cores,
            coreSwitch: (
              protocol: ShikooProtocol.vless,
              to: _xray,
              stage: stage,
            ),
          );
          await tester.pumpAndSettle();
          expect(hint, findsNothing, reason: stage.name);
          final news = tester.getRect(find.text(line));
          expect(news.top, closeTo(slot.top, 1), reason: stage.name);
          expect(news.left, greaterThanOrEqualTo(0));
          expect(_top(tester, _fa.coresGroup), rows, reason: 'nothing moves');
          expect(_focused(), remote, reason: 'the remote stays');
          final t = ShikooTheme.of(tester.element(find.text(line)));
          expect(
            tester.widget<Text>(find.text(line)).style?.color,
            stage == ShikooSwitchStage.failed ? t.c.danger : t.c.textMuted,
            reason: stage.name,
          );
          if (shot != null) await _shot(tester, '$shot-${b.name}');
        }
        rig.holder.value = _settings(tv: true, cores: cores);
        await tester.pumpAndSettle();
        expect(hint, findsOneWidget);
      });
    }
  });

  group('Windows', () {
    final windows = TargetPlatformVariant.only(TargetPlatform.windows);

    testWidgets('the list drops under its row and a click picks', (
      tester,
    ) async {
      final rig = await _pump(tester, _settings());
      // Flush with the top edge, as a scrolled page leaves it: the click's ring scrolls it first.
      await tester.ensureVisible(find.text(_fa.protocolWireguard).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_fa.protocolWireguard).first);
      await tester.pumpAndSettle();
      final head = find.text(
        _fa.corePickTitle(bidiName(_fa.protocolWireguard)),
      );
      expect(head, findsOneWidget);
      final row = tester.getRect(
        find
            .ancestor(
              of: find.text(_fa.protocolWireguard),
              matching: find.byType(Pressable),
            )
            .first,
      );
      final menu = tester.getRect(
        find.ancestor(of: head, matching: find.byType(IntrinsicWidth)).first,
      );
      expect(menu.top, greaterThan(row.bottom), reason: 'under its row');
      expect(menu.width, closeTo(ShikooSizes.coreMenu, 1));
      expect(menu.left, closeTo(row.left, 1), reason: 'end edges together');
      expect(
        find.text(
          '${_fa.corePickForAll(bidiName(_fa.protocolWireguard))} ${_fa.corePickAgain}',
        ),
        findsOneWidget,
      );
      await _shot(tester, 'a-win-light');
      await tester.tap(find.text(_fa.coreXray).last);
      await tester.pumpAndSettle();
      expect(head, findsNothing);
      verify(
        () => rig.controller.setCore(ShikooProtocol.wireguard, _xray),
      ).called(1);
    }, variant: windows);

    for (final b in Brightness.values) {
      testWidgets('Proxy mode greys the engine that owns the tunnel, keeps it '
          'picked, and says why (${b.name})', (tester) async {
        final rig = await _pump(
          tester,
          _settings(),
          proxy: true,
          brightness: b,
        );
        await tester.ensureVisible(find.text(_fa.protocolWireguard).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_fa.protocolWireguard).first);
        await tester.pumpAndSettle();
        expect(find.text(_fa.coreTunnelOnly(_fa.modeTunnel)), findsOneWidget);
        expect(
          find.text(
            '${_fa.coreProxyNow(_fa.modeProxy)} '
            '${_fa.corePickForAll(bidiName(_fa.protocolWireguard))}',
          ),
          findsOneWidget,
        );
        await _shot(tester, 'p-set-${b.name}');
        await tester.tap(find.text(_fa.coreWireguard).last);
        await tester.pumpAndSettle();
        verifyNever(() => rig.controller.setCore(any(), any()));
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        rig.holder.value = _settings(
          cores: _rows(wireguard: _wireguard, tunnel: false),
        );
        await tester.pumpAndSettle();
        expect(find.text(_fa.coreWireguard), findsOneWidget, reason: 'kept');
        await tester.ensureVisible(find.text(_fa.protocolVless).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_fa.protocolVless).first);
        await tester.pumpAndSettle();
        expect(
          find.text(
            '${_fa.corePickForAll(bidiName(_fa.protocolVless))} ${_fa.corePickAgain}',
          ),
          findsOneWidget,
          reason: 'no engine of VLESS owns the tunnel',
        );
      }, variant: windows);
    }

    for (final b in Brightness.values) {
      for (final tunnel in [true, false]) {
        testWidgets('the OpenVPN row on Windows is there in tunnel mode only '
            '(${b.name}, tunnel $tunnel)', (tester) async {
          await _pump(
            tester,
            _settings(
              cores: coreRows(
                {...ShikooProtocol.values},
                const {},
                specs: readyHere(ShikooPlatform.windows),
                tunnel: tunnel,
              ),
            ),
            brightness: b,
          );
          expect(
            find.text(_fa.protocolOpenvpn),
            tunnel ? findsOneWidget : findsNothing,
          );
          expect(find.text(_fa.protocolWireguard), findsOneWidget);
          await tester.ensureVisible(find.text(_fa.coresGroup));
          await tester.pumpAndSettle();
          await _shot(tester, 'o-win-${b.name}-${tunnel ? 'tun' : 'proxy'}');
        }, variant: windows);
      }
    }

    for (final b in Brightness.values) {
      testWidgets('«اتصال» under «زبان» and over «ویندوز» (${b.name})', (
        tester,
      ) async {
        await _pump(tester, _settings(), brightness: b);
        expect(
          _top(tester, _fa.language),
          lessThan(_top(tester, _fa.connectionGroup)),
        );
        expect(
          _top(tester, _fa.coresGroup),
          lessThan(_top(tester, _fa.windowsGroup)),
        );
        await tester.ensureVisible(find.text(_fa.connectionGroup));
        await tester.pumpAndSettle();
        await _shot(tester, 'i-win-${b.name}');
      }, variant: windows);
    }

    testWidgets('a row low in the window still gets its whole list, inside '
        'the window', (tester) async {
      await _pump(tester, _settings());
      await Scrollable.ensureVisible(
        tester.element(find.text(_fa.protocolWireguard)),
        alignment: 0.4,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_fa.protocolWireguard).first);
      await tester.pumpAndSettle();
      final menu = tester.getRect(
        find
            .ancestor(
              of: find.text(_fa.corePickTitle(bidiName(_fa.protocolWireguard))),
              matching: find.byType(IntrinsicWidth),
            )
            .first,
      );
      expect(menu.top, greaterThanOrEqualTo(Space.s2));
      expect(
        menu.bottom,
        lessThanOrEqualTo(ShikooSizes.windowStart.height - Space.s2),
      );
      await _shot(tester, 'a-win-low-light');
    }, variant: windows);

    for (final b in Brightness.values) {
      testWidgets(
        'Proxy mode with the official engine picked: the list shows it '
        'picked and greyed, says where its servers go, and neither it nor '
        'closing changes the pick (${b.name})',
        (tester) async {
          final rig = await _pump(
            tester,
            _settings(cores: _rows(wireguard: _wireguard, tunnel: false)),
            proxy: true,
            brightness: b,
          );
          await tester.ensureVisible(find.text(_fa.protocolWireguard).first);
          await tester.pumpAndSettle();
          expect(
            find.text(_fa.coreWireguard),
            findsOneWidget,
            reason: 'the row',
          );
          await tester.tap(find.text(_fa.protocolWireguard).first);
          await tester.pumpAndSettle();
          final option = find
              .ancestor(
                of: find.text(_fa.coreWireguard).last,
                matching: find.byType(Row),
              )
              .first;
          expect(
            find.descendant(
              of: option,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration! as BoxDecoration).shape == BoxShape.circle,
              ),
            ),
            findsOneWidget,
            reason: 'its radio holds the dot',
          );
          expect(find.text(_fa.coreTunnelOnly(_fa.modeTunnel)), findsOneWidget);
          expect(
            find.text(
              _fa.coreProxyFallback(
                _fa.modeProxy,
                bidiName(_fa.protocolWireguard),
                _fa.modeTunnel,
                bidiName(_fa.coreWireguard),
              ),
            ),
            findsOneWidget,
          );
          expect(find.text(_fa.coreProxyNow(_fa.modeProxy)), findsNothing);
          await _shot(tester, 'p-set-kept-${b.name}');
          await tester.tap(find.text(_fa.coreWireguard).last);
          await tester.pumpAndSettle();
          await tester.tapAt(Offset.zero);
          await tester.pumpAndSettle();
          expect(
            find.text(_fa.corePickTitle(bidiName(_fa.protocolWireguard))),
            findsNothing,
          );
          verifyNever(() => rig.controller.setCore(any(), any()));
        },
        variant: windows,
      );
    }

    for (final b in Brightness.values) {
      testWidgets('«با mihomo» on the computer (${b.name})', (tester) async {
        await _pump(tester, _home(), home: const ShikooHome(), brightness: b);
        expect(
          find.text(_fa.viaCore(bidiName(_fa.coreMihomo))),
          findsOneWidget,
        );
        await _shot(tester, 'x-win-${b.name}');
      }, variant: windows);
    }
  });

  // Sam, 2026-10-27: cores and protocols by their trade names, isolated inside Persian sentences.
  group('trade names', () {
    test(
      'every core and protocol is named in Latin letters in Persian too',
      () {
        for (final (name, latin) in [
          (_fa.coreMihomo, 'mihomo'),
          (_fa.coreXray, 'Xray'),
          (_fa.coreSingBox, 'sing-box'),
          (_fa.protocolVless, 'VLESS'),
          (_fa.protocolWireguard, 'WireGuard'),
          (_fa.protocolOpenvpn, 'OpenVPN'),
          (_fa.protocolSsh, 'SSH'),
        ]) {
          expect(name, latin);
        }
      },
    );

    test('«رسمی» follows the official engines\' names, each isolated so '
        'it stays after the name', () {
      expect(_fa.coreWireguard, '\u2068WireGuard\u2069 رسمی');
      expect(_fa.coreOpenvpn, '\u2068OpenVPN\u2069 رسمی');
    });

    for (final device in ['phone', 'tv', 'win']) {
      for (final b in Brightness.values) {
        testWidgets(
          'the WireGuard list, «با mihomo» and the switch news stay '
          'whole ($device, ${b.name})',
          (tester) async {
            final tv = device == 'tv';
            final tag = '$device-${b.name}';
            await _pump(tester, _settings(tv: tv), brightness: b);
            if (tv) {
              await _focusOn(tester, _fa.protocolWireguard);
              await _press(tester, LogicalKeyboardKey.select);
            } else {
              await tester.ensureVisible(
                find.text(_fa.protocolWireguard).first,
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text(_fa.protocolWireguard).first);
              await tester.pumpAndSettle();
            }
            expect(
              find.text(_fa.corePickTitle(bidiName(_fa.protocolWireguard))),
              findsOneWidget,
            );
            expect(find.text(_fa.coreWireguardHelp), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _shot(tester, 't-list-$tag');

            await _pump(
              tester,
              _home(tv: tv),
              home: const ShikooHome(),
              brightness: b,
            );
            expect(
              find.text(_fa.viaCore(bidiName(_fa.coreMihomo))),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await _shot(tester, 't-via-$tag');

            final rig = await _pump(
              tester,
              _home(tv: tv, vless: _xray),
              home: const ShikooHome(),
              brightness: b,
            );
            rig.holder.value = _home(
              tv: tv,
              vless: _xray,
              coreSwitch: (
                protocol: ShikooProtocol.vless,
                to: _xray,
                stage: ShikooSwitchStage.done,
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              find.text(_fa.coreSwitched(bidiName(_fa.coreXray))),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await _shot(tester, 't-news-$tag');
          },
          variant: device == 'win'
              ? TargetPlatformVariant.only(TargetPlatform.windows)
              : const DefaultTestVariant(),
        );
      }
    }
  });
}
