import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:fl_clash/shikoo/engine/update.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/login.dart';
import 'package:fl_clash/shikoo/ui/settings.dart' show Segmented;
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

class _SignIn extends Mock implements ShikooSignIn {}

class _Controller extends Mock implements ShikooController {}

class _Update extends Mock implements ShikooUpdate {}

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);
final _l = lookupShikooL10n(const Locale('fa'));
const _who = TelegramAccount(name: 'مریم', username: 'maryam_k');

List<LinkedService> _services(int n) => [
  for (var i = 1; i <= n; i++)
    LinkedService(
      id: i,
      title: '5550123_7000000${i}_$i · الماس',
      status: i == 1 ? 'active' : 'expired',
    ),
];

ShikooLogin _choosing(int n) =>
    ShikooLogin(LoginPhase.choosing, account: _who, choices: _services(n));

Future<void> _pump(
  WidgetTester tester,
  Size page, {
  bool tv = false,
  ShikooLogin? login,
  UpdateOffer? offer,
  String language = 'fa',
  double text = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = page
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final signIn = _SignIn();
  when(signIn.start).thenAnswer((_) async => null);
  final container = ProviderContainer(
    overrides: [
      noShots,
      shikooStateProvider.overrideWithValue(
        ShikooState(
          connection: ShikooConnection.off,
          connectedFor: Duration.zero,
          isTV: tv,
          servers: const [],
        ),
      ),
      shikooSignInProvider.overrideWithValue(signIn),
      shikooControllerProvider.overrideWithValue(_Controller()),
      shikooVersionProvider.overrideWithValue('1.0.40'),
      shikooUpdateProvider.overrideWithValue(_Update()),
      if (offer != null)
        shikooUpdateOfferProvider.overrideWith(() => ShikooCell(offer)),
    ],
  );
  addTearDown(container.dispose);
  container.read(shikooLoginProvider.notifier).set(login);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      key: UniqueKey(),
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(Brightness.light, tv: tv),
        home: const ShikooRoot(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every button or link whose bottom is under the page's edge.
List<String> _hidden(WidgetTester tester, double height) => [
  for (final e in [
    ...find.byType(ShikooButton).evaluate(),
    ...find.byType(LinkButton).evaluate(),
  ])
    if ((e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy +
            (e.renderObject! as RenderBox).size.height >
        height + 0.5)
      switch (e.widget) {
        final ShikooButton b => b.label,
        final LinkButton b => b.label,
        _ => '?',
      },
];

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is ShikooButton && w.label == label);

final _pinnedBar = find.byWidgetPredicate(
  (w) => w is RawScrollbar && (w.thumbVisibility ?? false),
);

/// [found]'s rect as far as every scrolling region round it lets it show.
Rect _seen(Element found) {
  final box = found.renderObject! as RenderBox;
  var seen = box.localToGlobal(Offset.zero) & box.size;
  for (
    var scroll = Scrollable.maybeOf(found);
    scroll != null;
    scroll = Scrollable.maybeOf(scroll.context)
  ) {
    final port = scroll.context.findRenderObject()! as RenderBox;
    seen = seen.intersect(port.localToGlobal(Offset.zero) & port.size);
  }
  return seen;
}

/// Each pair of drawn parts that are seen on top of each other.
List<String> _overlaps(WidgetTester tester) {
  final parts = [
    for (final type in [
      ShikooButton,
      LinkButton,
      MessageBox,
      BrandMark,
      Segmented<String>,
    ])
      ...find.byType(type).evaluate(),
  ];
  return [
    for (final (i, a) in parts.indexed)
      for (final b in parts.skip(i + 1))
        if (_seen(a) case final r when !r.isEmpty && r.overlaps(_seen(b)))
          '${a.widget.runtimeType} on ${b.widget.runtimeType}',
  ];
}

void main() {
  setUpAll(loadShikooFonts);

  testWidgets('with large text in the smallest window the top scrolls under '
      'the buttons and nothing is drawn over anything; buttons taller than '
      'the window scroll with the page', (tester) async {
    final wrong = <String>[];
    Future<void> check(
      Size page,
      ShikooLogin login,
      String language,
      double text,
    ) async {
      await _pump(tester, page, login: login, language: language, text: text);
      final name =
          '${login.clock ? 'clock' : 'startFailed'} $language $text '
          '$page';
      for (final over in _overlaps(tester)) {
        wrong.add('$name: $over');
      }
      for (final label in _hidden(tester, page.height)) {
        final button = tester.element(
          find.byWidgetPredicate(
            (w) =>
                (w is ShikooButton && w.label == label) ||
                (w is LinkButton && w.label == label),
          ),
        );
        await tester.ensureVisible(find.byWidget(button.widget));
        await tester.pumpAndSettle();
        if (_hidden(tester, page.height).contains(label)) {
          wrong.add('$name: $label never reached');
        }
      }
    }

    const clock = ShikooLogin(LoginPhase.startFailed, clock: true);
    for (final language in ['fa', 'en']) {
      for (final text in [1.25, 1.5]) {
        await check(const Size(400, 448), clock, language, text);
      }
    }
    for (final width in [400.0, 600.0, 787.0, 788.0]) {
      await check(
        Size(width, 448),
        const ShikooLogin(LoginPhase.startFailed),
        'en',
        1.5,
      );
    }
    expect(wrong, isEmpty);
  }, variant: _windows);

  testWidgets('from 440 to 600 high at 100 to 150% text, a start error lays '
      'out without an error, and its language switch can be scrolled wholly '
      'into view', (tester) async {
    final wrong = <String>[];
    for (final language in ['fa', 'en']) {
      final l = lookupShikooL10n(Locale(language));
      for (final text in [1.0, 1.25, 1.5]) {
        for (final (name, clock, other) in [
          ('clock', true, false),
          ('startFailed', false, false),
          ('other device clock', true, true),
        ]) {
          await _pump(
            tester,
            const Size(400, 600),
            login: ShikooLogin(LoginPhase.startFailed, clock: clock),
            language: language,
            text: text,
          );
          if (other) {
            final link = find.text(l.noTelegramHereDesktop);
            await tester.ensureVisible(link);
            await tester.pumpAndSettle();
            await tester.tap(link);
            await tester.pumpAndSettle();
          }
          for (final height in [
            452.0,
            for (var h = 440.0; h <= 600; h += 4) h,
          ]) {
            final at = '$name $language $text $height';
            tester.view.physicalSize = Size(400, height);
            await tester.pumpAndSettle();
            if (tester.takeException() case final error?) {
              wrong.add('$at: $error');
            }
            final languages = find.byType(Segmented<String>);
            if (languages.evaluate().isEmpty) continue;
            await tester.ensureVisible(languages);
            await tester.pumpAndSettle();
            final seen = _seen(
              tester.element(languages),
            ).intersect(Offset.zero & Size(400, height));
            if (seen.height < tester.getSize(languages).height - 0.5) {
              wrong.add('$at: language switch ${seen.height} seen');
            }
          }
        }
      }
    }
    expect(wrong, isEmpty);
  }, variant: _windows);

  testWidgets("a narrow window's checklist keeps its buttons right under "
      'it while they fit', (tester) async {
    await _pump(tester, const Size(600, 448), login: _choosing(1));
    final row = find.ancestor(
      of: find.text(bidiName(_services(1).first.title)),
      matching: find.byType(Pressable),
    );
    expect(
      tester.getRect(_button(_l.continueButton)).top -
          tester.getRect(row).bottom,
      Space.s4,
    );
  }, variant: _windows);

  testWidgets('in the smallest window and in both of Sam\'s, no button or link '
      'of a sign-in, forced-update or other-device page is under the edge', (
    tester,
  ) async {
    const release = UpdateOffer(
      AppRelease(
        versionName: '1.0.57',
        versionCode: 2057,
        minVersionCode: 2050,
        size: 52080629,
        sha256: '',
        url: 'https://door.test/dl/ShikooNet-1.0.57-windows-x64.exe',
      ),
      forced: true,
      phase: UpdatePhase.offered,
      error: UpdateError.clock,
    );
    final logins = <String, ShikooLogin?>{
      'first': null,
      'startFailed': const ShikooLogin(LoginPhase.startFailed),
      'clock': const ShikooLogin(LoginPhase.startFailed, clock: true),
      'waiting': const ShikooLogin(LoginPhase.waiting, code: '48291537'),
      'expired': const ShikooLogin(LoginPhase.expired, code: '48291537'),
      'rejected': const ShikooLogin(LoginPhase.rejected),
      'servicesFailed': const ShikooLogin(
        LoginPhase.servicesFailed,
        account: _who,
        clock: true,
      ),
      'noService': const ShikooLogin(LoginPhase.noService, account: _who),
      for (final n in [2, 4, 6, 8]) ...{
        'approved $n': ShikooLogin(
          LoginPhase.approved,
          account: _who,
          services: [for (final s in _services(n)) s.title],
        ),
        'choosing $n': _choosing(n),
      },
    };
    final hidden = <String>[];
    for (final page in const [Size(400, 448), Size(864, 492), Size(860, 675)]) {
      void check(String name) {
        for (final label in _hidden(tester, page.height)) {
          hidden.add('$name at $page: $label');
        }
      }

      for (final MapEntry(:key, :value) in logins.entries) {
        await _pump(tester, page, login: value);
        check(key);
      }
      await _pump(tester, page, offer: release);
      check('forced update');
      await _pump(tester, page, login: logins['expired']);
      await tester.tap(find.text(_l.noTelegramHereDesktop));
      await tester.pumpAndSettle();
      check('other device');
    }
    expect(hidden, isEmpty);
  }, variant: _windows);

  testWidgets('the checklist sits beside its buttons in a wide window; in a '
      'narrow one it is over them, they keep to the bottom and a bar shows '
      'the rest', (tester) async {
    await _pump(tester, const Size(864, 492), login: _choosing(4));
    final list = tester.getRect(find.text(_l.chooseServicesDesktop));
    final go = tester.getRect(_button(_l.continueButton));
    expect(list.right, lessThan(go.left));
    await _pump(tester, const Size(864, 492), login: _choosing(8));
    final rows = Scrollable.of(
      tester.element(find.text(_l.chooseServicesDesktop)),
    );
    expect(rows.position.maxScrollExtent, greaterThan(0));
    final row = find.ancestor(
      of: find.text(bidiName(_services(8).first.title)),
      matching: find.byType(Pressable),
    );
    expect(tester.getRect(row).left, ShikooSizes.desktop.safeX);
    expect(
      tester.getRect(find.byWidget(rows.widget)).left,
      0,
      reason: "the bar in the window's margin, clear of the rows",
    );

    await _pump(tester, const Size(400, 448), login: _choosing(4));
    expect(tester.getRect(_button(_l.notMyAccount)).bottom, 448 - Space.s8);
    final question = find.text(_l.chooseServicesDesktop);
    expect(
      Scrollable.of(tester.element(question)).position.maxScrollExtent,
      greaterThan(0),
    );
    final bar = tester.widget<RawScrollbar>(
      find.ancestor(of: question, matching: _pinnedBar).first,
    );
    expect(
      (bar.thickness, bar.thumbColor),
      (ShikooSizes.scrollThumb, ShikooColors.light.outline),
    );
    Finder fade() => find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient != null,
    );
    expect(fade(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(fade(), findsNothing, reason: "a focused row's ring stays whole");
  }, variant: _windows);

  testWidgets('a phone and a TV keep the sign-in as it was: the buttons '
      'scroll with the list, and no bar is pinned on', (tester) async {
    await _pump(tester, const Size(360, 640), login: _choosing(8));
    final go = tester.element(_button(_l.continueButton));
    final row = tester.element(find.text(bidiName(_services(8).last.title)));
    expect(Scrollable.of(go), same(Scrollable.of(row)));
    expect(_pinnedBar, findsNothing);

    await _pump(tester, const Size(960, 540), tv: true, login: _choosing(8));
    expect(_pinnedBar, findsNothing);
  });
}
