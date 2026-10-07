import 'dart:math' as math;

import 'package:fl_clash/enum/enum.dart' show MessageLevel;
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/settings.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignIn extends Mock implements ShikooSignIn {}

class _Controller extends Mock implements ShikooController {}

class _Update extends Mock implements ShikooUpdate {}

typedef _Device = ({Size size, double scale, bool tv});

/// 16:9 TVs as Android reports them in dp: 1080p at 320, 240 and 160 dpi, 720p at 240, and the
/// smaller ones seen on the bench. The design's canvas first.
const _tv169 = [
  Size(960, 540),
  Size(1280, 720),
  Size(1920, 1080),
  Size(1280 / 1.5, 480),
  Size(768, 432),
  Size(640, 360),
  Size(480, 270),
];

/// WP7 of docs/app-diagnostics.md: each layout report from a device adds its screen here. A
/// release build draws past an overflow without a word, so only geometry catches it.
final _devices = <_Device>[
  for (final size in _tv169.take(3))
    for (final scale in const [1.0, 1.15, 1.3])
      (size: size, scale: scale, tv: true),
  // Taller and wider than 16:9: the canvas grows in height, then in width.
  for (final size in [
    ..._tv169.skip(3),
    const Size(1024, 600),
    const Size(2560, 1080),
  ])
    for (final scale in const [1.0, 1.3]) (size: size, scale: scale, tv: true),
  for (final size in const [Size(360, 800), Size(412, 915)])
    for (final scale in const [1.0, 1.45])
      (size: size, scale: scale, tv: false),
];

/// How much larger than the canvas a TV draws it.
double _k(_Device device) => device.tv
    ? math.min(
        device.size.width / ShikooSizes.tvCanvas.width,
        device.size.height / ShikooSizes.tvCanvas.height,
      )
    : 1;

Rect _onCanvas(Rect rect, double k) => (rect.topLeft / k) & (rect.size / k);

final _l = lookupShikooL10n(const Locale('fa'));
final _now = DateTime.now();

const _maryam = TelegramAccount(name: 'مریم', username: 'maryam_k');
const _names = [
  'user5551234_a1f0 · پاسارگاد',
  'user5551234_e7f9 · پاسارگاد',
  'user5551234_f38a · پاسارگاد',
  'user5551234_5551234_2 · اولین خرید',
];

const _release = AppRelease(
  versionName: '1.0.58',
  versionCode: 2058,
  minVersionCode: 2058,
  size: 52080629,
  sha256: '',
  url: '',
);

ShikooState _signedOut(bool tv) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: tv,
  servers: const [],
);

ShikooState _home(bool tv) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: tv,
  service: ShikooService(
    name: _names.first,
    usedBytes: 33 << 30,
    totalBytes: 100 << 30,
    expire: _now.add(const Duration(days: 30)),
    updatedAt: _now,
  ),
  servers: [
    for (var i = 1; i <= 12; i++)
      ShikooServer(name: 'سرور $i', type: 'Vless', ping: 80 + i),
  ],
  selected: 'سرور 1',
  others: [
    for (var i = 1; i <= 4; i++)
      ShikooService(
        id: 10 + i,
        name: 'user55$i · طلایی',
        usedBytes: 0,
        totalBytes: 0,
        expire: _now.subtract(Duration(days: i)),
      ),
  ],
);

String _name(_Device d) =>
    '${d.tv ? 'TV' : 'phone'} ${d.size.width.round()}x${d.size.height.round()} '
    'font ${d.scale}';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Device device,
  Widget home, {
  ShikooState? state,
  ShikooLogin? login,
  ShikooAccount account = const ShikooAccount(),
  UpdateOffer? offer,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = device.size * 2
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = device.scale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  FocusManager.instance.highlightStrategy = device.tv
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  final signIn = _SignIn();
  when(signIn.start).thenAnswer((_) async => null);
  final update = _Update();
  when(update.checkNow).thenAnswer((_) async => null);
  final container = ProviderContainer(
    overrides: [
      shikooStateProvider.overrideWithValue(state ?? _signedOut(device.tv)),
      shikooSignInProvider.overrideWithValue(signIn),
      shikooControllerProvider.overrideWithValue(_Controller()),
      shikooUpdateProvider.overrideWithValue(update),
      shikooUpdateOfferProvider.overrideWith(() => ShikooCell(offer)),
      shikooVersionProvider.overrideWithValue('1.0.57'),
    ],
  );
  addTearDown(container.dispose);
  container.read(shikooLoginProvider.notifier).set(login);
  container.read(shikooAccountProvider.notifier).set(account);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      key: UniqueKey(),
      container: container,
      child: MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: device.tv),
        // Only FlClash's StatusManager of its managers: it holds the app in a loose Stack and
        // shows FlClash's messages.
        builder: (context, child) => shikooFrame(
          context,
          child!,
          managers: (page) => StatusManager(child: page),
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// On screen, so a page shrunk to fit is measured as drawn.
Rect _rectOf(Element element) {
  final box = element.renderObject! as RenderBox;
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

bool _under(Element element, Element ancestor) {
  var found = false;
  element.visitAncestorElements((above) => !(found = above == ancestor));
  return found;
}

bool _onTop(Element element) => ModalRoute.of(element)?.isCurrent ?? true;

/// [rect] as far as the scroll views around [element] let it show.
Rect _clip(Element element, Rect rect) {
  var room = rect;
  element.visitAncestorElements((above) {
    if (above.widget is Scrollable) room = room.intersect(_rectOf(above));
    return true;
  });
  return room;
}

/// Null when [element], with [ring] around it, is whole inside [view] and every scroll view
/// around it.
String? _cut(Element element, Rect view, double ring) {
  final rect = _rectOf(element).inflate(ring);
  final room = _clip(element, view);
  const slack = 0.5;
  final inside =
      rect.left >= room.left - slack &&
      rect.top >= room.top - slack &&
      rect.right <= room.right + slack &&
      rect.bottom <= room.bottom + slack;
  return inside ? null : '$rect is outside $room';
}

String _say(Element element) => switch (element.widget) {
  final RichText text => text.text.toPlainText(),
  final widget =>
    element.findAncestorWidgetOfExactType<ShikooButton>()?.label ??
        widget.runtimeType.toString(),
};

/// The focus node a press on [target] lands on: its own, or the surface it sits in.
FocusNode? _nodeOf(Finder target) {
  final pressable = find.ancestor(of: target, matching: find.byType(Pressable));
  final owner = pressable.evaluate().isEmpty ? target : pressable.first;
  final inside = find.descendant(
    of: owner,
    matching: find.byType(GestureDetector),
  );
  if (inside.evaluate().isEmpty) return null;
  return Focus.of(inside.evaluate().first);
}

/// What is wrong now. Each of [reach] must show whole: on a TV the remote is put on it first,
/// with its ring; on a phone it is scrolled to.
Future<List<String>> _faults(
  WidgetTester tester,
  _Device device,
  List<Finder> reach,
) async {
  final faults = <String>[];
  final error = tester.takeException();
  if (error != null) faults.add('$error'.split('\n').first);
  const tv = ShikooSizes.tv;
  final k = _k(device);
  final view = device.tv
      ? Rect.fromLTRB(
          tv.safeX * k,
          tv.safeY * k,
          device.size.width - tv.safeX * k,
          device.size.height - tv.safeY * k,
        )
      : Offset.zero & device.size;
  void checkFocus() {
    final context = FocusManager.instance.primaryFocus?.context as Element?;
    if (context == null) {
      faults.add('nothing has the remote');
    } else if (_cut(context, view, ShikooSizes.ring * k) case final cut?) {
      faults.add('the remote is on ${_say(context)}: $cut');
    }
  }

  if (device.tv) checkFocus();
  for (final target in reach) {
    if (target.evaluate().isEmpty) {
      faults.add('no ${target.describeMatch(Plurality.zero)}');
      continue;
    }
    final node = device.tv ? _nodeOf(target) : null;
    if (node != null) {
      FocusTraversalGroup.of(
        node.context!,
      ).invalidateScopeData(node.nearestScope!);
      node.requestFocus();
      await tester.pumpAndSettle();
      checkFocus();
      continue;
    }
    if (!device.tv) await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
    final element = target.evaluate().first;
    if (_cut(element, view, 0) case final cut?) {
      faults.add('${_say(element)}: $cut');
    }
  }
  if (device.tv) {
    // A scroll view the remote never enters hides its end for good.
    for (final element in find.byType(Scrollable).evaluate()) {
      if (!_onTop(element)) continue;
      final position =
          ((element as StatefulElement).state as ScrollableState).position;
      if (position.maxScrollExtent < 0.5) continue;
      final holdsFocus = FocusManager.instance.rootScope.descendants.any(
        (node) =>
            node is! FocusScopeNode &&
            node.canRequestFocus &&
            !node.skipTraversal &&
            node.context != null &&
            _under(node.context! as Element, element),
      );
      if (!holdsFocus) {
        faults.add(
          'a scroll view with nothing for the remote hides '
          '${position.maxScrollExtent.toStringAsFixed(1)}dp',
        );
      }
    }
  }
  final texts = [
    for (final element in find.byType(RichText).evaluate())
      if (_onTop(element)) (element, _clip(element, _rectOf(element))),
  ];
  for (final (i, (a, shownA)) in texts.indexed) {
    for (final (b, shownB) in texts.skip(i + 1)) {
      final both = shownA.intersect(shownB);
      if (both.width > 1 && both.height > 1 && !_under(a, b) && !_under(b, a)) {
        faults.add('«${_say(a)}» is over «${_say(b)}»');
      }
    }
  }
  return faults;
}

typedef _Check = Future<void> Function(List<Finder> reach);

/// One test per screen, every device in turn, so a run names every device it breaks on.
void _everywhere(
  String screen,
  Future<void> Function(WidgetTester tester, _Device device, _Check check) show,
) {
  testWidgets('$screen stays in view and apart on every screen', (
    tester,
  ) async {
    final faults = <String>[];
    for (final device in _devices) {
      await show(tester, device, (reach) async {
        for (final fault in await _faults(tester, device, reach)) {
          faults.add('${_name(device)}: $fault');
        }
      });
    }
    expect(faults, isEmpty);
  });
}

Finder _button(String label) => find.widgetWithText(ShikooButton, label);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadShikooFonts();
  });

  const waiting = ShikooLogin(
    LoginPhase.waiting,
    code: '482915',
    botUrl: 'https://t.me/Test_Shikoo_bot?start=app_482915',
  );
  final code = find.text('۴۸۲ ۹۱۵');

  testWidgets('every 16:9 TV shows the 960x540 layout, only larger or '
      'smaller; another shape gets more height or width', (tester) async {
    final faults = <String>[];
    for (final scale in const [1.0, 1.3]) {
      Map<String, Rect>? design;
      for (final size in _tv169) {
        final device = (size: size, scale: scale, tv: true);
        final k = _k(device);
        final shown = <String, Rect>{};
        void measure(Map<String, Finder> targets) {
          for (final MapEntry(key: name, value: target) in targets.entries) {
            shown[name] = _onCanvas(tester.getRect(target), k);
          }
        }

        await _pump(
          tester,
          device,
          const ShikooHome(),
          state: _home(true),
          offer: const UpdateOffer(_release),
        );
        measure({
          'power': find.byType(PowerButton),
          'update': _button(_l.updateGet),
          'settings': _button(_l.settings),
        });
        await _pump(
          tester,
          device,
          const ShikooSettings(),
          state: _home(true),
          account: const ShikooAccount(who: _maryam),
        );
        measure({
          'about': find.text(_l.about),
          'log out': find.text(_l.logout),
        });
        await _pump(tester, device, const ShikooRoot(), login: waiting);
        measure({'code': code, 'support': _button(_l.support)});
        await _pump(
          tester,
          device,
          const ShikooRoot(),
          login: const ShikooLogin(
            LoginPhase.approved,
            account: _maryam,
            services: _names,
          ),
        );
        measure({'continue': _button(_l.continueButton)});
        design ??= shown;
        for (final MapEntry(key: name, value: rect) in shown.entries) {
          final want = design[name]!;
          if ((rect.topLeft - want.topLeft).distance > 0.5 ||
              (rect.bottomRight - want.bottomRight).distance > 0.5) {
            faults.add('${_name(device)}: $name at $rect, not $want');
          }
        }
      }
    }
    for (final (size, canvas) in const [
      (Size(1024, 600), Size(960, 562.5)),
      (Size(2560, 1080), Size(1280, 540)),
    ]) {
      await _pump(
        tester,
        (size: size, scale: 1.0, tv: true),
        const ShikooHome(),
        state: _home(true),
      );
      final drawn = MediaQuery.sizeOf(tester.element(find.byType(ShikooHome)));
      if (drawn != canvas) faults.add('$size draws $drawn, not $canvas');
    }
    expect(faults, isEmpty);
  });

  testWidgets("the app's frame sets the bars' icons for Shikoo's light theme", (
    tester,
  ) async {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    await _pump(tester, _devices.last, const ShikooHome(), state: _home(false));
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets("on a TV FlClash's messages grow and shrink with the canvas, "
      'inside its safe area', (tester) async {
    const text = 'config is not applied';
    final faults = <String>[];
    Rect? design;
    for (final size in const [
      Size(960, 540),
      Size(1920, 1080),
      Size(480, 270),
    ]) {
      final device = (size: size, scale: 1.0, tv: true);
      await _pump(tester, device, const ShikooHome(), state: _home(true));
      tester
          .state<StatusManagerState>(find.byType(StatusManager))
          .message(text, level: MessageLevel.error);
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: find.text(text),
        matching: find.byType(Card),
      );
      final k = _k(device);
      const tv = ShikooSizes.tv;
      final safe = Rect.fromLTRB(
        tv.safeX * k,
        tv.safeY * k,
        size.width - tv.safeX * k,
        size.height - tv.safeY * k,
      );
      if (_cut(card.evaluate().first, safe, 0) case final cut?) {
        faults.add('${_name(device)}: $cut');
      }
      final shown = _onCanvas(tester.getRect(card), k);
      design ??= shown;
      if ((shown.topLeft - design.topLeft).distance > 0.5 ||
          (shown.bottomRight - design.bottomRight).distance > 0.5) {
        faults.add('${_name(device)}: at $shown, not $design');
      }
    }
    expect(faults, isEmpty);
  });

  _everywhere('the sign-in code', (tester, device, check) async {
    await _pump(tester, device, const ShikooRoot(), login: waiting);
    if (!device.tv) {
      await check([_button(_l.reopenTelegram)]);
      await tester.tap(find.text(_l.approveElsewhere));
      await tester.pumpAndSettle();
    }
    await check([code]);
  });

  _everywhere('the sign-in result', (tester, device, check) async {
    final container = await _pump(
      tester,
      device,
      const ShikooRoot(),
      login: const ShikooLogin(LoginPhase.syncing, account: _maryam),
    );
    // As on the device: the services come after the page, under a remote already on it.
    container
        .read(shikooLoginProvider.notifier)
        .set(
          const ShikooLogin(
            LoginPhase.approved,
            account: _maryam,
            services: _names,
          ),
        );
    await tester.pumpAndSettle();
    await check([_button(_l.continueButton), _button(_l.notMyAccount)]);
  });

  _everywhere('home with the update, the servers and finished services', (
    tester,
    device,
    check,
  ) async {
    await _pump(
      tester,
      device,
      const ShikooHome(),
      state: _home(device.tv),
      offer: const UpdateOffer(_release),
    );
    await check([
      find.byType(PowerButton),
      _button(_l.updateGet),
      find.text('سرور 12'),
      find.text(_l.finishedServices(4)),
    ]);
  });

  _everywhere('settings and its log-out dialog', (tester, device, check) async {
    await _pump(
      tester,
      device,
      const ShikooSettings(),
      state: _home(device.tv),
      account: const ShikooAccount(who: _maryam),
    );
    await check([
      find.text(_l.settingsCheckUpdate),
      find.text(_l.about),
      find.text(_l.logout),
    ]);
    await tester.tap(find.text(_l.logout));
    await tester.pumpAndSettle();
    await check([_button(_l.cancelButton), _button(_l.logout)]);
  });

  _everywhere('the forced update', (tester, device, check) async {
    for (final offer in const [
      UpdateOffer(_release, forced: true, phase: UpdatePhase.ready),
      UpdateOffer(_release, forced: true, error: UpdateError.network),
    ]) {
      await _pump(tester, device, const ShikooRoot(), offer: offer);
      await check([find.byType(ShikooButton).first, _button(_l.support)]);
    }
  });
}
