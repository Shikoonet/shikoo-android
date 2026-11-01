import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter/rendering.dart'
    show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';

/// wg-card-onhold-ping.html: a file-only (WireGuard) card shows days and never data (change 1, الف), and a
/// service the panel has not started has no ping button but a line over its servers (change 2, پ).
const _bot = 'Test_Shikoo_bot';
const _name = 'وایرگارد نامحدود · یک‌ماهه';

const _servers = [
  ShikooServer(name: 'ترکیه ۱', type: 'WireGuard'),
  ShikooServer(name: 'آلمان ۳', type: 'WireGuard'),
  ShikooServer(name: 'آمریکا ۲', type: 'WireGuard'),
];

ShikooService _file({bool onHold = false, int? days = 30, DateTime? expire}) =>
    ShikooService(
      id: 1,
      name: _name,
      usedBytes: 0,
      totalBytes: 0,
      expire: expire,
      fileOnly: true,
      onHold: onHold,
      durationDays: days,
      updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );

ShikooService _usual({bool onHold = false, int? days}) => ShikooService(
  id: 1,
  name: 'user123 · الماس',
  usedBytes: 34 << 30,
  totalBytes: 100 << 30,
  expire: onHold ? null : DateTime.now().add(const Duration(days: 20)),
  onHold: onHold,
  durationDays: days,
  updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
);

ShikooState _state(
  ShikooService service, {
  bool isTV = false,
  List<ShikooService> others = const [],
}) => ShikooState(
  connection: ShikooConnection.off,
  connectedFor: Duration.zero,
  isTV: isTV,
  service: service,
  others: others,
  servers: _servers,
  pick: ShikooPick.auto,
);

ShikooAccount _account(ShikooService service, String status) => ShikooAccount(
  bot: _bot,
  services: [
    LinkedService(
      id: 50,
      title: service.name,
      status: status,
      profileId: service.id,
      fileOnly: service.fileOnly,
      durationDays: service.durationDays,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  ShikooState state,
  ShikooAccount account, {
  String locale = 'fa',
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = state.isTV ? const Size(1920, 1080) : const Size(824, 1830)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooAccountProvider.overrideWith(() => ShikooCell(account)),
        shikooStateProvider.overrideWithValue(state),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: ShikooL10n.supportedLocales,
        localizationsDelegates: const [
          ShikooL10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: shikooThemeData(brightness, tv: state.isTV),
        builder: (_, child) => RepaintBoundary(key: _screen, child: child),
        home: const ShikooHome(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _screen = GlobalKey();

/// With `SHIKOO_SHOTS=<folder>`, the screen as a PNG there.
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

ShikooL10n _l(String locale) => lookupShikooL10n(Locale(locale));

/// The ping button of the phone's head or the TV's.
Finder get _pingButton => find.byWidgetPredicate(
  (widget) =>
      (widget is ShikooIconButton &&
          (widget.label == _l('fa').pingServers ||
              widget.label == _l('en').pingServers)) ||
      (widget is ShikooButton &&
          (widget.label == _l('fa').ping || widget.label == _l('en').ping)),
);

Finder get _usage => find.byWidgetPredicate(
  (widget) =>
      widget is MeterBar ||
      (widget is Text &&
          [
            for (final language in ['fa', 'en']) ...[
              _l(language).usedLabel,
              _l(language).remainingLabel,
            ],
          ].any(
            (label) => (widget.textSpan?.toPlainText() ?? widget.data ?? '')
                .contains(label),
          )),
);

Finder _text(String text) => find.textContaining(text);

String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final row = context.findAncestorWidgetOfExactType<ServerRow>();
  return row?.server.name ??
      context.findAncestorWidgetOfExactType<ShikooButton>()?.label;
}

/// The remote on «به‌روزرسانی», then down: the head has no ping stop, so the first server is next.
Future<void> _focusFirstServer(WidgetTester tester) async {
  final refresh = find.ancestor(
    of: find.text('به‌روزرسانی'),
    matching: find.byType(Pressable),
  );
  Focus.of(
    tester.element(
      find.descendant(of: refresh, matching: find.byType(GestureDetector)),
    ),
  ).requestFocus();
  await tester.pumpAndSettle();
  expect(_focused(), 'به‌روزرسانی');
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pumpAndSettle();
}

void main() {
  group('a file-only service the panel has not started', () {
    for (final locale in ['fa', 'en']) {
      testWidgets('reads «not activated», one validity line, no data and no '
          'ping button, and a line over its servers ($locale)', (tester) async {
        final l = _l(locale);
        final service = _file(onHold: true);
        await _pump(
          tester,
          _state(service),
          _account(service, 'on_hold'),
          locale: locale,
        );
        expect(find.text(l.statusOnHold), findsOneWidget);
        expect(
          _text(
            locale == 'fa'
                ? 'اعتبار: ۳۰ روز از اولین اتصال'
                : 'Valid: 30 days from your first connection',
          ),
          findsOneWidget,
        );
        expect(find.text(l.statusActive), findsNothing);
        expect(_usage, findsNothing);
        expect(find.text(l.unlimited), findsNothing);
        expect(_text(l.validUntil('')), findsNothing);
        expect(_pingButton, findsNothing);
        expect(_text(l.pingHeldDays(30)), findsOneWidget);
        expect(_text(l.pingHeld), findsNothing);
        expect(find.byType(ServerRow), findsNWidgets(3));
        expect(
          find.widgetWithText(ShikooButton, l.renew),
          findsOneWidget,
          reason: 'the top bar renews it like any other service',
        );
      });
    }

    testWidgets('with no length known it says only that the days come from '
        'the first connection', (tester) async {
      final service = _file(onHold: true, days: null);
      await _pump(tester, _state(service), _account(service, 'on_hold'));
      expect(_text('اعتبار از اولین اتصال'), findsOneWidget);
      expect(_text('۳۰ روز از'), findsNothing);
    });

    testWidgets('the days are bold, and only they', (tester) async {
      final service = _file(onHold: true);
      await _pump(tester, _state(service), _account(service, 'on_hold'));
      final line = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(ServiceCard),
          matching: find.textContaining('اعتبار: ۳۰ روز از اولین اتصال'),
        ),
      );
      final bold = <String>[];
      line.text.visitChildren((span) {
        if (span is TextSpan && span.style?.fontWeight == FontWeight.w700) {
          bold.add(span.text!);
        }
        return true;
      });
      expect(bold, ['۳۰ روز']);
    });
  });

  group('a file-only service once it runs', () {
    for (final locale in ['fa', 'en']) {
      testWidgets('shows the date and the days left like any card, no data, '
          'the active chip and the ping button ($locale)', (tester) async {
        final l = _l(locale);
        final service = _file(
          expire: DateTime.now().add(const Duration(days: 18)),
        );
        await _pump(
          tester,
          _state(service),
          _account(service, 'active'),
          locale: locale,
        );
        expect(find.text(l.statusActive), findsOneWidget);
        expect(find.text(l.statusOnHold), findsNothing);
        expect(_text(l.daysLeft(18)), findsOneWidget);
        expect(_text(l.validUntil('').trim()), findsOneWidget);
        expect(_usage, findsNothing);
        expect(find.text(l.unlimited), findsNothing);
        expect(_pingButton, findsOneWidget);
        expect(_text(l.pingHeld), findsNothing);
        expect(_text(l.pingHeldDays(30)), findsNothing);
      });
    }

    testWidgets('for the minutes before the panel sends its date it says '
        '30 days from today', (tester) async {
      final service = _file();
      await _pump(tester, _state(service), _account(service, 'on_hold'));
      expect(_text('اعتبار: ۳۰ روز از امروز'), findsOneWidget);
      expect(_text('در انتظار'), findsNothing);
      expect(_pingButton, findsOneWidget);
      expect(_usage, findsNothing);
    });

    testWidgets('past its date it is ended: the red chip, no data, no ping '
        'button, and its own renew button', (tester) async {
      final service = _file(
        expire: DateTime.now().subtract(const Duration(days: 2)),
      );
      await _pump(tester, _state(service), _account(service, 'expired'));
      expect(find.text(_l('fa').chipExpired), findsOneWidget);
      expect(_usage, findsNothing);
      expect(_pingButton, findsNothing);
      expect(_text(_l('fa').pingHeld), findsNothing);
      expect(find.widgetWithText(ShikooButton, _l('fa').renew), findsWidgets);
    });
  });

  group('a usual service', () {
    for (final locale in ['fa', 'en']) {
      testWidgets('held reads «not activated» and has no ping button, but '
          'keeps its data and the line over its servers ($locale)', (
        tester,
      ) async {
        final l = _l(locale);
        final service = _usual(onHold: true);
        await _pump(
          tester,
          _state(service),
          _account(service, 'on_hold'),
          locale: locale,
        );
        expect(find.text(l.statusOnHold), findsOneWidget);
        expect(find.text(l.statusActive), findsNothing);
        expect(_usage, findsWidgets, reason: 'the volume is the usual one');
        expect(_pingButton, findsNothing);
        expect(_text(l.pingHeld), findsOneWidget);
        expect(_text(l.pingHeldDays(30)), findsNothing);
      });

      testWidgets('active is as before: the active chip, the ping button, '
          'no line over its servers ($locale)', (tester) async {
        final l = _l(locale);
        final service = _usual();
        await _pump(
          tester,
          _state(service),
          _account(service, 'active'),
          locale: locale,
        );
        expect(find.text(l.statusActive), findsOneWidget);
        expect(find.text(l.statusOnHold), findsNothing);
        expect(_usage, findsWidgets);
        expect(_pingButton, findsOneWidget);
        expect(_text(l.pingHeld), findsNothing);
      });
    }

    testWidgets('the grey chip is the on-hold one and the green one is the '
        'active one', (tester) async {
      final service = _usual(onHold: true);
      await _pump(tester, _state(service), _account(service, 'on_hold'));
      final context = tester.element(find.byType(ServiceCard));
      final t = ShikooTheme.of(context);
      Color? chip(String label) {
        final box = tester.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        return (box.decoration! as ShapeDecoration).color;
      }

      final l = _l('fa');
      expect(chip(l.statusOnHold), t.c.surfaceSunken);
      final active = _usual();
      await _pump(tester, _state(active), _account(active, 'active'));
      expect(chip(l.statusActive), t.c.positiveSoft);
    });

    testWidgets('folded beside the one in use, the held and the file-only '
        'cards say it in their summary line', (tester) async {
      final held = _file(onHold: true).copy(id: 2);
      final today = _file().copy(id: 3);
      final dated = _file(
        expire: DateTime.now().add(const Duration(days: 18)),
      ).copy(id: 4);
      final service = _usual();
      await _pump(
        tester,
        _state(service, others: [held, today, dated]),
        ShikooAccount(
          bot: _bot,
          services: [
            for (final other in [held, today, dated])
              LinkedService(
                id: 60 + other.id,
                title: other.name,
                status: other.onHold ? 'on_hold' : 'active',
                profileId: other.id,
                fileOnly: true,
              ),
          ],
        ),
      );
      final l = _l('fa');
      expect(find.text(l.statusOnHold), findsOneWidget);
      expect(_text('اعتبار از اولین اتصال'), findsOneWidget);
      expect(_text('اعتبار: ۳۰ روز از امروز'), findsOneWidget);
      expect(_text(l.validUntil('').trim()), findsOneWidget);
    });
  });

  testWidgets('in English a held file-only card says «your» first connection, '
      'folded and open without a length, while the shelf card keeps its own', (
    tester,
  ) async {
    final held = _file(onHold: true).copy(id: 2);
    final today = _file().copy(id: 3);
    final open = _file(onHold: true, days: null);
    await _pump(
      tester,
      _state(open, others: [held, today]),
      ShikooAccount(
        bot: _bot,
        services: [
          for (final other in [open, held, today])
            LinkedService(
              id: 60 + other.id,
              title: other.name,
              status: other.onHold ? 'on_hold' : 'active',
              profileId: other.id,
              fileOnly: true,
            ),
        ],
      ),
      locale: 'en',
    );
    expect(
      _text('Valid from your first connection'),
      findsNWidgets(2),
      reason: 'two folded cards: the held one and the one with no length',
    );
    expect(_text('Valid: 30 days from today'), findsOneWidget);
    expect(_text('Valid from the first connection'), findsNothing);
    expect(
      _l('en').outsourcedSummary,
      'Valid from the first connection',
      reason: 'the shelf card\x27s own key is not touched',
    );
  });

  testWidgets('in English an open held file-only card without a length says '
      '«your» first connection', (tester) async {
    final service = _file(onHold: true, days: null);
    await _pump(
      tester,
      _state(service),
      _account(service, 'on_hold'),
      locale: 'en',
    );
    expect(
      find.descendant(
        of: find.byType(ServiceCard),
        matching: _text('Valid from your first connection'),
      ),
      findsOneWidget,
    );
    expect(_text('Valid from the first connection'), findsNothing);
  });

  testWidgets('the renew list names a held service as not activated, '
      'beside the active one', (tester) async {
    final held = _usual(onHold: true).copy(id: 2);
    final active = _usual();
    await _pump(
      tester,
      _state(active, others: [held]),
      ShikooAccount(
        bot: _bot,
        services: [
          for (final (service, status) in [
            (active, 'active'),
            (held, 'on_hold'),
          ])
            LinkedService(
              id: 50 + service.id,
              title: service.name,
              status: status,
              profileId: service.id,
            ),
        ],
      ),
    );
    final l = _l('fa');
    expect(
      find.text(l.statusOnHold),
      findsOneWidget,
      reason: 'its folded card',
    );
    await tester.tap(find.widgetWithText(ShikooButton, l.renew).first);
    await tester.pumpAndSettle();
    expect(find.text(l.statusOnHold), findsNWidgets(2), reason: 'and its row');
    final grey = ShikooTheme.of(tester.element(find.byType(ShikooHome))).c;
    for (final label in find.text(l.statusOnHold).evaluate()) {
      final chip = tester.widget<Container>(
        find
            .ancestor(
              of: find.byWidget(label.widget),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (chip.decoration! as ShapeDecoration).color,
        grey.surfaceSunken,
        reason: 'not the green of an active one',
      );
    }
  });

  group('the note over the servers of a held service', () {
    for (final locale in ['fa', 'en']) {
      testWidgets('has no number for a service of unknown length, and its '
          'own length for one that has it ($locale)', (tester) async {
        final l = _l(locale);
        for (final (service, note) in [
          (_file(onHold: true, days: null), l.pingHeld),
          (_usual(onHold: true), l.pingHeld),
          (_usual(onHold: true, days: 60), l.pingHeldDays(60)),
          (_file(onHold: true, days: 90), l.pingHeldDays(90)),
        ]) {
          await _pump(
            tester,
            _state(service),
            _account(service, 'on_hold'),
            locale: locale,
          );
          expect(
            _text(note),
            findsOneWidget,
            reason: '${service.durationDays}',
          );
          expect(
            _text(l.pingHeldDays(30)),
            findsNothing,
            reason: 'no fixed 30 for ${service.durationDays}',
          );
        }
      });
    }

    testWidgets('says «اعتبارت» in Persian when the length is unknown', (
      tester,
    ) async {
      final service = _usual(onHold: true);
      await _pump(tester, _state(service), _account(service, 'on_hold'));
      expect(
        _text('پینگ بعد از اولین اتصال، تا اعتبارت زودتر شروع نشود.'),
        findsOneWidget,
      );
      expect(_text('۳۰'), findsNothing);
    });
  });

  group('on the TV', () {
    testWidgets('a held service has no «پینگ» button, its note takes the '
        "list caption's place, and down from update reaches the first "
        'server', (tester) async {
      final service = _file(onHold: true);
      await _pump(
        tester,
        _state(service, isTV: true),
        _account(service, 'on_hold'),
      );
      expect(_pingButton, findsNothing);
      expect(_text(_l('fa').pingHeldDays(30)), findsOneWidget);
      expect(_text(_l('fa').fastestFirst), findsNothing);
      expect(_text(_l('fa').sortsOnPing), findsNothing);
      await _focusFirstServer(tester);
      expect(_focused(), 'ترکیه ۱');
    });

    testWidgets('an active service keeps its «پینگ» button', (tester) async {
      final service = _usual();
      await _pump(
        tester,
        _state(service, isTV: true),
        _account(service, 'active'),
      );
      expect(_pingButton, findsOneWidget);
      expect(_text(_l('fa').pingHeld), findsNothing);
    });
  });

  // Last, as the font stays for every test after: the widths are Vazirmatn's, as on a phone.
  group('in Vazirmatn', () {
    setUpAll(loadShikooFonts);

    testWidgets('the four states in the frames the designer compares: the '
        'phone in both languages and themes, and the TV', (tester) async {
      final states = <String, (ShikooService, String)>{
        'file-hold': (_file(onHold: true), 'on_hold'),
        'file-active': (
          _file(expire: DateTime.now().add(const Duration(days: 18))),
          'active',
        ),
        'usual-hold': (_usual(onHold: true), 'on_hold'),
        'usual-active': (_usual(), 'active'),
      };
      for (final dark in [false, true]) {
        final theme = dark ? 'dark' : 'light';
        for (final locale in ['fa', 'en']) {
          for (final MapEntry(:key, :value) in states.entries) {
            final (service, status) = value;
            await _pump(
              tester,
              _state(service),
              _account(service, status),
              locale: locale,
              brightness: dark ? Brightness.dark : Brightness.light,
            );
            expect(tester.takeException(), isNull, reason: '$key $locale');
            await _shot(tester, 'phone-$locale-$key-$theme');
          }
        }
        final (service, status) = states['file-hold']!;
        await _pump(
          tester,
          _state(service, isTV: true),
          _account(service, status),
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await _shot(tester, 'tv-fa-file-hold-$theme');
        await _focusFirstServer(tester);
        await _shot(tester, 'tv-fa-file-hold-focus-$theme');
        final folded = [
          _file(onHold: true).copy(id: 2),
          _file().copy(id: 3),
          _file(
            expire: DateTime.now().add(const Duration(days: 18)),
          ).copy(id: 4),
        ];
        await _pump(
          tester,
          _state(_usual(), others: folded),
          ShikooAccount(
            bot: _bot,
            services: [
              for (final other in folded)
                LinkedService(
                  id: 60 + other.id,
                  title: other.name,
                  status: other.onHold ? 'on_hold' : 'active',
                  profileId: other.id,
                  fileOnly: true,
                ),
            ],
          ),
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await _shot(tester, 'folded-fa-$theme');
        await _pump(
          tester,
          _state(_usual(), others: folded),
          ShikooAccount(
            bot: _bot,
            services: [
              for (final other in folded)
                LinkedService(
                  id: 60 + other.id,
                  title: other.name,
                  status: other.onHold ? 'on_hold' : 'active',
                  profileId: other.id,
                  fileOnly: true,
                ),
            ],
          ),
          locale: 'en',
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await _shot(tester, 'folded-en-$theme');
        final ended = _file(
          expire: DateTime.now().subtract(const Duration(days: 2)),
        );
        await _pump(
          tester,
          _state(ended),
          _account(ended, 'expired'),
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await _shot(tester, 'phone-fa-file-ended-$theme');
      }
    });
  });
}

extension on ShikooService {
  ShikooService copy({required int id}) => ShikooService(
    id: id,
    name: name,
    usedBytes: usedBytes,
    totalBytes: totalBytes,
    expire: expire,
    fileOnly: fileOnly,
    onHold: onHold,
    durationDays: durationDays,
    updatedAt: updatedAt,
  );
}
