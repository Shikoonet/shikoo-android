import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
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

class _SignIn extends Mock implements ShikooSignIn {}

final _fa = lookupShikooL10n(const Locale('fa'));
final _en = lookupShikooL10n(const Locale('en'));

const _faNames = ['هلند ۱', 'آلمان ۲', 'آمریکا ۲', 'فنلاند ۲', 'انگلیس ۱'];
const _enNames = ['Netherlands 1', 'Germany 2', 'USA 2', 'Finland 2', 'UK 1'];

/// The mockup's list: «فنلاند ۲», in use, and «انگلیس ۱» answer only through WARP.
ShikooState _home({
  bool tv = false,
  bool en = false,
  ShikooConnection connection = ShikooConnection.on,
  bool on = true,
  bool trying = false,
  bool failed = false,
  bool none = false,
  bool bridgeLeg = false,
  ShikooRefresh refresh = ShikooRefresh.idle,
  ShikooNotice? notice,
}) {
  final names = en ? _enNames : _faNames;
  final via = on && !none ? {names[3], names[4]} : <String>{};
  const pings = [78, 84, 188, 210, 240];
  return ShikooState(
    connection: none ? ShikooConnection.error : connection,
    connectedFor: const Duration(minutes: 2, seconds: 47),
    isTV: tv,
    service: ShikooService(
      name: en ? '5550123 · Diamond' : '5550123 · الماس',
      usedBytes: 33 << 30,
      totalBytes: 100 << 30,
      expire: DateTime.now().add(const Duration(days: 23)),
      updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      bridgeLeg: bridgeLeg,
    ),
    servers: [
      for (final (i, name) in names.indexed)
        ShikooServer(
          name: name,
          type: 'Vless',
          ping: none || (trying && via.contains(name)) ? -1 : pings[i],
          viaBridge: via.contains(name),
        ),
    ],
    selected: names[3],
    pick: none ? ShikooPick.none : ShikooPick.server,
    lastError: none ? ShikooError.noServer : null,
    refresh: refresh,
    notice: notice,
    bridge: (on: on, via: via, trying: trying, failed: failed),
  );
}

ShikooState _settings({bool tv = false, bool on = false}) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: tv,
  servers: const [],
  bridge: (on: on, via: const {}, trying: false, failed: false),
);

typedef _Rig = ({_Controller controller, ValueNotifier<ShikooState> holder});

final _screen = GlobalKey();

Size _view({required bool tv}) => tv
    ? ShikooSizes.tvCanvas
    : (shikooDesktop ? ShikooSizes.windowStart : const Size(412, 915));

void _frame(WidgetTester tester, {required bool tv}) {
  tester.view
    ..physicalSize = _view(tv: tv) * 2
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
}

Widget _app(
  Widget home, {
  required bool tv,
  String locale = 'fa',
  Brightness brightness = Brightness.light,
}) => MaterialApp(
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
);

Future<_Rig> _pump(
  WidgetTester tester,
  ShikooState state, {
  Widget home = const ShikooHome(),
  String locale = 'fa',
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  _frame(tester, tv: state.isTV);
  final controller = _Controller();
  when(() => controller.setBridge(any())).thenAnswer((_) async {});
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
        shikooStateProvider.overrideWith((ref) {
          void changed() => ref.invalidateSelf();
          holder.addListener(changed);
          ref.onDispose(() => holder.removeListener(changed));
          return holder.value;
        }),
      ],
      child: _app(home, tv: state.isTV, locale: locale, brightness: brightness),
    ),
  );
  final screen = tester.element(find.byKey(_screen));
  await ProviderScope.containerOf(
    screen,
  ).read(shikooLookProvider.notifier).setLanguage(locale);
  await tester.runAsync(
    () => precacheImage(const AssetImage(shikooMarkAsset), screen),
  );
  await tester.pumpAndSettle();
  return (controller: controller, holder: holder);
}

typedef _LoginRig = ({_Controller controller, _SignIn signIn});

/// The sign-in page, its code refused: [on] is WARP's switch.
Future<_LoginRig> _pumpLogin(
  WidgetTester tester, {
  required bool tv,
  bool on = false,
  String locale = 'fa',
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  _frame(tester, tv: tv);
  final controller = _Controller();
  when(() => controller.setBridge(any())).thenAnswer((_) async {});
  final signIn = _SignIn();
  when(signIn.start).thenAnswer((_) async => null);
  final container = ProviderContainer(
    overrides: [
      noShots,
      shikooStateProvider.overrideWithValue(_settings(tv: tv, on: on)),
      shikooSignInProvider.overrideWithValue(signIn),
      shikooControllerProvider.overrideWithValue(controller),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(shikooLoginProvider.notifier)
      .set(const ShikooLogin(LoginPhase.startFailed));
  await container.read(shikooLookProvider.notifier).setLanguage(locale);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _app(
        const ShikooRoot(),
        tv: tv,
        locale: locale,
        brightness: brightness,
      ),
    ),
  );
  await tester.runAsync(
    () => precacheImage(
      const AssetImage(shikooMarkAsset),
      tester.element(find.byKey(_screen)),
    ),
  );
  await tester.pumpAndSettle();
  return (controller: controller, signIn: signIn);
}

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

String? _focused() => (FocusManager.instance.primaryFocus?.context as Element?)
    ?.findAncestorWidgetOfExactType<ShikooButton>()
    ?.label;

/// What draws a focus ring now: a button's label, or `power`.
List<String> _rings(WidgetTester tester) {
  final ring = ShikooTheme.of(tester.element(find.byType(Scaffold).first)).c;
  return [
    for (final e in find.byType(DecoratedBox).evaluate())
      if ((e.widget as DecoratedBox).decoration
          case ShapeDecoration(shape: OutlinedBorder(:final side))
          when side.color == ring.focusRing &&
              side.width == ShikooSizes.focusRingWidth)
        e.findAncestorWidgetOfExactType<ShikooButton>()?.label ??
            (e.findAncestorWidgetOfExactType<PowerButton>() != null
                ? 'power'
                : '?'),
  ];
}

Finder _chip(String server, String label) => find.descendant(
  of: find.ancestor(of: find.text(server), matching: find.byType(Row)).first,
  matching: find.text(label),
);

void main() {
  setUpAll(() async {
    registerFallbackValue(false);
    await loadShikooFonts();
  });

  testWidgets('Settings › Connection: the WARP switch under Iranian sites, off '
      'by default, says what Cloudflare sees and turns the bridge on', (
    tester,
  ) async {
    final rig = await _pump(tester, _settings(), home: const ShikooSettings());
    final iran = tester.getTopLeft(find.text(_fa.iranDirect));
    final warp = tester.getTopLeft(find.text(_fa.warpSwitch));
    expect(warp.dy, greaterThan(iran.dy));
    expect(find.text(_fa.warpSwitchHelp), findsOneWidget);
    final row = tester.widget<SwitchRow>(
      find.ancestor(
        of: find.text(_fa.warpSwitch),
        matching: find.byType(SwitchRow),
      ),
    );
    expect(row.on, isFalse);
    await tester.tap(find.text(_fa.warpSwitch));
    await tester.pumpAndSettle();
    verify(() => rig.controller.setBridge(true)).called(1);
  });

  testWidgets('«از راه WARP» only beside the servers that leave through it, '
      'and beside the one in use under the button', (tester) async {
    await _pump(tester, _home());
    for (final name in [_faNames[3], _faNames[4]]) {
      await tester.ensureVisible(find.text(name).last);
      expect(_chip(name, _fa.warpVia), findsWidgets, reason: name);
    }
    for (final name in _faNames.take(3)) {
      await tester.ensureVisible(find.text(name).last);
      expect(_chip(name, _fa.warpVia), findsNothing, reason: name);
    }
    expect(
      find.descendant(
        of: find.byType(NowPill),
        matching: find.text(_fa.warpVia),
      ),
      findsOneWidget,
    );
  });

  testWidgets('connecting: the first try names the server and says it takes '
      'longer; later ones say only «از راه WARP وصل می‌شوی…»', (tester) async {
    final rig = await _pump(
      tester,
      _home(connection: ShikooConnection.connecting, trying: true),
    );
    expect(find.text(_fa.warpFirst(bidiName(_faNames[3]))), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NowPill), matching: find.byType(Ping)),
      findsNothing,
      reason: 'its direct «بی‌پاسخ» is no news while WARP is tried',
    );
    rig.holder.value = _home(connection: ShikooConnection.connecting);
    await tester.pumpAndSettle();
    expect(find.text(_fa.warpAgain), findsOneWidget);
    rig.holder.value = _home();
    await tester.pumpAndSettle();
    expect(find.text(_fa.warpAgain), findsNothing);
  });

  testWidgets('no server answered with the switch off: «روشن کردن WARP» and '
      'what Cloudflare sees; with it on, neither way answered', (tester) async {
    final rig = await _pump(tester, _home(on: false, none: true));
    expect(find.text(_fa.warpOffTouch), findsOneWidget);
    expect(find.text(_fa.warpNote), findsOneWidget);
    await tester.tap(find.widgetWithText(ShikooButton, _fa.warpTurnOn));
    await tester.pumpAndSettle();
    verify(() => rig.controller.setBridge(true)).called(1);
    rig.holder.value = _home(none: true, failed: true);
    await tester.pumpAndSettle();
    expect(find.text(_fa.warpFailBothTouch), findsOneWidget);
    expect(find.widgetWithText(ShikooButton, _fa.warpTurnOn), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the TV: as «روشن کردن WARP» comes the remote moves to it, from '
      'the power button too, with its ring, and turns WARP on', (tester) async {
    final rig = await _pump(
      tester,
      _home(tv: true, on: false, connection: ShikooConnection.connecting),
    );
    expect(_rings(tester), ['power'], reason: 'connecting, on the button');
    rig.holder.value = _home(tv: true, on: false, none: true);
    await tester.pumpAndSettle();
    expect(find.text(_fa.warpOffTv), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(_focused(), _fa.warpTurnOn, reason: 'c-tv-off: the remote on it');
    expect(_rings(tester), [_fa.warpTurnOn]);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    verify(() => rig.controller.setBridge(true)).called(1);
  });

  testWidgets('a focused button built again under another parent keeps its '
      'ring: no focus change comes to draw it again', (tester) async {
    _frame(tester, tv: true);
    final node = FocusNode();
    addTearDown(node.dispose);
    final wrap = ValueNotifier(false);
    addTearDown(wrap.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: shikooThemeData(Brightness.light, tv: true),
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: wrap,
            builder: (_, wrapped, _) {
              final button = Center(
                child: ShikooButton(
                  label: 'x',
                  focusNode: node,
                  onPressed: () {},
                ),
              );
              return wrapped ? FittedBox(child: button) : button;
            },
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(_rings(tester), ['x']);
    wrap.value = true;
    await tester.pumpAndSettle();
    expect(node.hasPrimaryFocus, isTrue);
    expect(_rings(tester), [
      'x',
    ], reason: 'tv-b02: the remote kept, its ring lost');
  });

  testWidgets('the TV keeps all of the first try\'s lines and of the failure '
      'through WARP, whose first line wraps there', (tester) async {
    await _pump(
      tester,
      _home(tv: true, connection: ShikooConnection.connecting, trying: true),
    );
    final first = _fa.warpFirst(bidiName(_faNames[3]));
    final paragraph = tester.renderObject<RenderParagraph>(find.text(first));
    expect(paragraph.didExceedMaxLines, isFalse, reason: first);
    // Fresh: a failure that follows a try starts the internet check, whose card takes the hint's place.
    await _pump(tester, _home(tv: true, none: true, failed: true));
    expect(
      tester
          .renderObject<RenderParagraph>(find.text(_fa.warpFailBothTv))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an update on WARP says so, and one that failed through it too '
      'says neither way answered', (tester) async {
    final rig = await _pump(
      tester,
      _home(
        connection: ShikooConnection.off,
        refresh: ShikooRefresh.running,
        bridgeLeg: true,
      ),
    );
    expect(find.text(_fa.updatingWarp), findsOneWidget);
    rig.holder.value = _home(
      connection: ShikooConnection.off,
      refresh: ShikooRefresh.failed,
      notice: const RefreshFailed(bridge: true),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining(_fa.updateFailedWarp, findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('About: WARP\'s paragraph comes before the source code one', (
    tester,
  ) async {
    await _pump(tester, _settings(), home: const ShikooAbout());
    expect(
      tester.getTopLeft(find.text(_fa.aboutWarp)).dy,
      lessThan(tester.getTopLeft(find.text(_fa.aboutSource)).dy),
    );
    expect(
      tester.getTopLeft(find.text(_fa.aboutWarp)).dy,
      greaterThan(tester.getTopLeft(find.text(_fa.aboutBasedOn)).dy),
    );
  });

  for (final tv in [false, true]) {
    testWidgets('sign-in, the code refused with WARP off (tv: $tv): «امتحان از '
        'راه WARP» turns it on and asks for the code again', (tester) async {
      final rig = await _pumpLogin(tester, tv: tv);
      final button = find.widgetWithText(ShikooButton, _fa.warpTry);
      expect(button, findsOneWidget);
      expect(find.text(_fa.warpNote), findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      verifyInOrder([
        () => rig.controller.setBridge(true),
        () => rig.signIn.start(),
      ]);
    });
  }

  for (final on in [false, true]) {
    testWidgets('the TV sign-in that failed, WARP on: $on, starts the remote '
        'on ${on ? '«دوباره»' : '«امتحان از راه WARP»'}', (tester) async {
      await _pumpLogin(tester, tv: true, on: on);
      final first = on ? _fa.retry : _fa.warpTry;
      expect(_focused(), first);
      expect(_rings(tester), [first]);
    });
  }

  testWidgets('sign-in with WARP already on offers no WARP button', (
    tester,
  ) async {
    await _pumpLogin(tester, tv: false, on: true);
    expect(find.widgetWithText(ShikooButton, _fa.warpTry), findsNothing);
    expect(
      find.textContaining(_fa.codeFailedHelpTouch, findRichText: true),
      findsOneWidget,
    );
  });

  group('shots', () {
    for (final device in ['phone', 'tv', 'win']) {
      for (final locale in ['fa', 'en']) {
        for (final b in Brightness.values) {
          testWidgets(
            '$device $locale ${b.name}',
            (tester) async {
              final tv = device == 'tv';
              final en = locale == 'en';
              final tag = '$device-$locale-${b.name}';
              Future<void> home(String name, ShikooState state) async {
                await _pump(tester, state, locale: locale, brightness: b);
                expect(tester.takeException(), isNull, reason: name);
                await _shot(tester, '$name-$tag');
              }

              await _pump(
                tester,
                _settings(tv: tv),
                home: const ShikooSettings(),
                locale: locale,
                brightness: b,
              );
              final l = en ? _en : _fa;
              await tester.ensureVisible(find.text(l.warpSwitch));
              await tester.pumpAndSettle();
              await _shot(tester, 'c-set-$tag');
              await home(
                'c-first',
                _home(
                  tv: tv,
                  en: en,
                  connection: ShikooConnection.connecting,
                  trying: true,
                ),
              );
              await home('c-on', _home(tv: tv, en: en));
              await home(
                'c-again',
                _home(tv: tv, en: en, connection: ShikooConnection.connecting),
              );
              await home('c-off', _home(tv: tv, en: en, on: false, none: true));
              await home(
                'c-fail',
                _home(tv: tv, en: en, none: true, failed: true),
              );
              await home(
                'l-update',
                _home(
                  tv: tv,
                  en: en,
                  connection: ShikooConnection.off,
                  refresh: ShikooRefresh.running,
                  bridgeLeg: true,
                ),
              );
              await home(
                'w-update-failed',
                _home(
                  tv: tv,
                  en: en,
                  connection: ShikooConnection.off,
                  refresh: ShikooRefresh.failed,
                  notice: const RefreshFailed(bridge: true),
                ),
              );
              await _pump(
                tester,
                _settings(tv: tv),
                home: const ShikooAbout(),
                locale: locale,
                brightness: b,
              );
              await _shot(tester, 'w-about-$tag');
              await _pumpLogin(tester, tv: tv, locale: locale, brightness: b);
              expect(tester.takeException(), isNull);
              await _shot(tester, 'l-login-fail-$tag');
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
