import 'dart:io';

import 'package:fl_clash/application.dart';
import 'package:fl_clash/manager/window_manager.dart'
    show WindowHeaderContainer;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart'
    show appSettingProvider, windowSettingProvider;
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/app/desktop.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);
final _l = lookupShikooL10n(const Locale('fa'));

const _off = ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: false,
  servers: [],
);

/// The first widget down [root]'s `child` chain that [match] accepts, without building anything.
Widget? _down(Widget root, bool Function(Widget) match) {
  Widget? widget = root;
  while (widget != null && !match(widget)) {
    try {
      widget = (widget as dynamic).child as Widget?;
    } on NoSuchMethodError {
      return null;
    }
  }
  return widget;
}

Future<List<String>> _windowCalls(WidgetTester tester) async {
  final calls = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  for (final channel in const ['window_manager', 'tray']) {
    messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'getId' => 0,
        _ => false,
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(MethodChannel(channel), null),
    );
  }
  return calls;
}

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooStateProvider.overrideWithValue(_off),
        shikooVersionProvider.overrideWithValue('1.0.57'),
        ...overrides,
      ],
      child: MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: false),
        builder: (context, child) =>
            ShikooWindow(notify: (_, _) async {}, child: child!),
        home: home,
      ),
    );

void _size(WidgetTester tester, Size window) {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = window
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test("FlClash's manager stack wears the frame it is given, its own header "
      'only without one', () {
    Future<void> changed(List<Object?> _) async {}
    const frame = ValueKey('frame');
    final framed = buildManagerStack(
      isDesktop: true,
      onConnectivityChanged: changed,
      desktopFrame: (child) => KeyedSubtree(key: frame, child: child),
      child: const SizedBox(),
    );
    expect(_down(framed, (w) => w.key == frame), isNotNull);
    expect(_down(framed, (w) => w is WindowHeaderContainer), isNull);
    final bare = buildManagerStack(
      isDesktop: true,
      onConnectivityChanged: changed,
      child: const SizedBox(),
    );
    expect(_down(bare, (w) => w is WindowHeaderContainer), isNotNull);
  });

  test('the entry points wire the window: the frame, --autostart in and out, '
      "the ring, and the tray menu's mode", () {
    String flat(String path) =>
        File(path).readAsStringSync().replaceAll(RegExp(r'\s'), '');
    final app = flat('lib/shikoo/app/app.dart');
    // ponytail: text, as main() and ShikooApp need the whole engine; a widget test once they split.
    expect(
      app,
      contains(
        'desktopFrame:system.isWindows?(page)=>ShikooWindow(child:page):null',
      ),
    );
    expect(app, contains('isDesktop:system.isDesktop,'));
    expect(
      app,
      contains(
        'if(system.isTV){FocusManager.instance.highlightStrategy='
        'FocusHighlightStrategy.alwaysTraditional;}'
        'elseif(system.isDesktop){ringOnKeys();}',
      ),
    );
    final main = flat('lib/shikoo/app/main.dart');
    expect(
      main,
      contains('shikooAutostarted=args.contains(shikooAutostartArg);'),
    );
    expect(
      main,
      contains('if(system.isWindows)awaitshikooWindowStart(container);'),
    );
    final desktop = flat('lib/shikoo/app/desktop.dart');
    expect(desktop, contains('if(autoLaunch!=null){'));
    expect(desktop, contains('args:const[shikooAutostartArg],'));
    expect(
      desktop,
      contains('mode:(mode)=>unawaited(controller.setMode(mode)),'),
    );
  });

  test('sign-in keeps asking while Telegram or a browser has the focus '
      '(inactive), and stops once the window is hidden or paused', () {
    final app = File(
      'lib/shikoo/app/app.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s'), '');
    expect(app, contains('finalresumed=state==AppLifecycleState.resumed;'));
    expect(
      app,
      contains(
        'ref.read(shikooControllerProvider)..foreground=resumed;'
        'finalsignIn=ref.read(shikooSignInProvider)'
        '..foreground=resumed||state==AppLifecycleState.inactive;',
      ),
    );
  });

  test('started by Windows the app opens beside the clock, by hand in its '
      'window', () {
    addTearDown(() => shikooAutostarted = false);
    shikooAutostarted = true;
    expect(shikooAppSettings(const AppSettingProps()).silentLaunch, isTrue);
    shikooAutostarted = false;
    expect(shikooAppSettings(const AppSettingProps()).silentLaunch, isFalse);
  });

  testWidgets('the window shrinks no further than 400 × 480', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        windowSettingProvider.overrideWithBuild(
          (_, _) => const WindowProps(width: 880, height: 540),
        ),
      ],
    );
    addTearDown(container.dispose);
    await shikooWindowStart(container);
    final min = calls.singleWhere((c) => c.method == 'setMinimumSize');
    expect(
      ((min.arguments as Map)['width'], (min.arguments as Map)['height']),
      (ShikooSizes.windowMin.width, ShikooSizes.windowMin.height),
    );
  });

  testWidgets('the title bar reads left to right in Persian too, and its '
      'buttons and empty part drive the window', (tester) async {
    _size(tester, const Size(880, 540));
    final calls = await _windowCalls(tester);
    await tester.pumpWidget(_app(const Scaffold()));
    await tester.pumpAndSettle();
    final close = tester.getRect(find.byTooltip(_l.windowClose));
    final mark = tester.getRect(find.byType(BrandMark).first);
    expect((close.right, close.top), (880.0, 0.0));
    expect(mark.left, lessThan(Space.s6));

    final title = find.text(_l.appName).first;
    await tester.tap(title);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(calls, contains('maximize'));
    await tester.drag(title, const Offset(60, 20));
    await tester.pumpAndSettle();
    expect(calls, contains('startDragging'));
    await tester.tap(find.byTooltip(_l.windowMinimize));
    await tester.pumpAndSettle();
    expect(calls, contains('minimize'));
  }, variant: _windows);

  testWidgets('«با ویندوز باز شود» shows on Windows and writes what it shows '
      "to FlClash's autoLaunch", (tester) async {
    _size(tester, const Size(880, 540));
    await _windowCalls(tester);
    await tester.pumpWidget(_app(const ShikooSettings()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShikooSettings)),
    );
    final row = find.text(_l.autoStart);
    expect(row, findsOne);
    expect(container.read(appSettingProvider).autoLaunch, isFalse);
    await tester.tap(row);
    await tester.pump();
    expect(container.read(appSettingProvider).autoLaunch, isTrue);
    await tester.tap(row);
    await tester.pump();
    expect(container.read(appSettingProvider).autoLaunch, isFalse);
  }, variant: _windows);

  testWidgets(
    '«خبر نسخهٔ تازه با پیام ویندوز» sits under «با ویندوز باز شود» '
    'on Windows only, on until turned off, and the window starts with what '
    'was saved',
    (tester) async {
      expect(ProviderContainer().read(shikooUpdateNoticeProvider), isTrue);
      _size(tester, const Size(880, 900));
      SharedPreferences.setMockInitialValues({'shikoo.updateNotice': false});
      await _windowCalls(tester);
      await tester.pumpWidget(_app(const ShikooSettings()));
      await tester.pumpAndSettle();
      final row = find.text(_l.updateNotice);
      if (defaultTargetPlatform != TargetPlatform.windows) {
        expect(row, findsNothing);
        expect(find.text(_l.autoStart), findsNothing);
        return;
      }
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShikooSettings)),
      );
      expect(find.text(_l.updateNoticeHelp), findsOne);
      for (final label in [_l.autoStart, _l.updateNotice]) {
        final row = tester.widget<Pressable>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Pressable))
              .first,
        );
        expect(
          (row.shape as RoundedSuperellipseBorder).borderRadius,
          BorderRadius.circular(Radii.md),
          reason: '$label: a row in a card, as `.row`',
        );
      }
      expect(
        tester.getRect(row).top,
        greaterThan(tester.getRect(find.text(_l.autoStart)).bottom),
      );
      expect(container.read(shikooUpdateNoticeProvider), isFalse);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(container.read(shikooUpdateNoticeProvider), isTrue);
      expect(container.read(appSettingProvider).autoLaunch, isFalse);
      final next = ProviderContainer();
      addTearDown(next.dispose);
      await next.read(shikooUpdateNoticeProvider.notifier).load();
      expect(next.read(shikooUpdateNoticeProvider), isTrue);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(container.read(shikooUpdateNoticeProvider), isFalse);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );

  test("Windows' update message goes once per version and again for a newer "
      'one, never while the window shows or with the switch off', () async {
    SharedPreferences.setMockInitialValues({});
    var hidden = true;
    final sent = <int>[];
    Future<bool> notice(int code, {bool on = true}) => noticeUpdate(
      code,
      on: on,
      hidden: () async => hidden,
      notify: () async => sent.add(code),
    );
    expect(await notice(56), isTrue);
    expect(await notice(56), isFalse);
    expect(await notice(55), isFalse, reason: 'an older one');
    expect(await notice(57, on: false), isFalse);
    hidden = false;
    expect(await notice(57), isFalse);
    hidden = true;
    expect(await notice(57), isTrue, reason: 'not told while it showed');
    expect(sent, [56, 57]);
  });

  test("the update message fits Windows' balloon, 63 characters of title "
      'and 255 of body at most, in both languages and both builds', () {
    addTearDown(() => shikooStaging = false);
    for (final staging in [false, true]) {
      shikooStaging = staging;
      for (final code in ['fa', 'en']) {
        final l = lookupShikooL10n(Locale(code));
        expect(l.updateNoticeTitle(l.appName).length, lessThanOrEqualTo(63));
        expect(l.updateNoticeBody.length, lessThanOrEqualTo(255));
      }
    }
    shikooStaging = false;
    final en = lookupShikooL10n(const Locale('en'));
    expect(en.updateNoticeTitle(en.appName), 'A new ShikooNet version is out');
  });

  test('a click on the message beside the clock opens the window as one on '
      'the icon does', () {
    final cpp = File(
      'plugins/tray/windows/tray_plugin.cpp',
    ).readAsStringSync().replaceAll(RegExp(r'\s'), '');
    expect(
      cpp,
      contains(
        'if(lparam==WM_LBUTTONUP||lparam==NIN_BALLOONUSERCLICK){'
        'SendEvent("onIconActivated"',
      ),
    );
  });

  testWidgets('a greyed-out press takes the tap, so nothing under it acts, '
      'and leaves the focus where it was', (tester) async {
    _size(tester, const Size(400, 480));
    var under = 0;
    final other = FocusNode();
    addTearDown(other.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Theme(
          data: shikooThemeData(Brightness.light, tv: false),
          child: GestureDetector(
            onTap: () => under++,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Focus(
                  focusNode: other,
                  child: const SizedBox.square(dimension: 8),
                ),
                Pressable(
                  onPressed: null,
                  shape: const CircleBorder(),
                  builder: (_, _) => const SizedBox.square(dimension: 48),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    other.requestFocus();
    await tester.pump();
    await tester.tap(find.byType(Pressable));
    await tester.pump();
    expect(under, 0);
    expect(other.hasPrimaryFocus, isTrue);
  }, variant: _windows);

  testWidgets('«تلگرام روی این کامپیوتر نیست؟» keeps to the 960 page too', (
    tester,
  ) async {
    _size(tester, const Size(1920, 1032));
    await _windowCalls(tester);
    await tester.pumpWidget(
      _app(
        const LoginPage(
          login: ShikooLogin(
            LoginPhase.waiting,
            code: '12345678',
            botUrl: 'https://t.me/shikoonet_bot?start=x',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text(_l.approveElsewhere));
    await tester.pump();
    final back = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is ShikooIconButton && widget.label == _l.back,
      ),
    );
    expect(back.left, greaterThanOrEqualTo((1920 - ShikooSizes.pageMax) / 2));
    expect(back.right, lessThanOrEqualTo((1920 + ShikooSizes.pageMax) / 2));
  }, variant: _windows);

  // Last: once loaded, Vazirmatn's widths would stay for every test after it.
  group('in Vazirmatn', () {
    setUpAll(loadShikooFonts);

    testWidgets('the core row, version and commit, keeps one line inside its '
        'row in the smallest window, at text size 1 and 1.45', (tester) async {
      final core = '\u2066${coreName('cd1023a')}\u2069';
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final scale in [1.0, 1.45]) {
        _size(tester, ShikooSizes.windowMin);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await _windowCalls(tester);
        await tester.pumpWidget(
          _app(
            const ShikooSettings(),
            overrides: [
              shikooCoreProvider.overrideWithValue(coreName('cd1023a')),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$scale');
        await tester.ensureVisible(find.text(core));
        final paragraph = tester.renderObject<RenderParagraph>(find.text(core));
        final whole = TextSelection(baseOffset: 0, extentOffset: core.length);
        final tops = paragraph.getBoxesForSelection(whole).map((b) => b.top);
        expect(tops.toSet(), hasLength(1), reason: '$scale');
        final drawn = tester.getRect(find.text(core));
        final row = tester.getRect(
          find.ancestor(of: find.text(core), matching: find.byType(Wrap)).first,
        );
        expect(drawn.left, greaterThanOrEqualTo(row.left - 0.01));
        expect(drawn.right, lessThanOrEqualTo(row.right + 0.01));
        expect(
          drawn.width / paragraph.size.width,
          moreOrLessEquals(1),
          reason: '$scale',
        );
      }
    }, variant: _windows);
  });
}
