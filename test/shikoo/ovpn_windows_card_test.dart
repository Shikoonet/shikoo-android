import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/mode.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/home.dart';
import 'package:fl_clash/shikoo/ui/icons.dart';
import 'package:fl_clash/shikoo/ui/service_card.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/shikoo/ui/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/no_shots.dart';
import '../helpers/test_profiles.dart';

class _Core extends Mock implements CoreHandlerInterface {}

/// The card as the app derives it on Windows: from the mode and the account, not from a state handed in.
Future<void> _pump(
  WidgetTester tester,
  ShikooMode mode, {
  bool mixed = false,
  String locale = 'fa',
  bool desktop = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = const Size(880, 1200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final core = _Core();
  when(() => core.asyncTestDelay(any(), any())).thenAnswer(
    (call) async =>
        Delay(name: call.positionalArguments[1] as String, url: '', value: 95),
  );
  final profile = Profile.normal(url: 'https://panel.invalid/sub');
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        noShots,
        shikooDesktopProvider.overrideWithValue(desktop),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        nativeRunTimeProvider.overrideWithValue(() async => null),
        shikooAccountProvider.overrideWith(
          () => ShikooCell(
            ShikooAccount(
              bot: 'Test_Shikoo_bot',
              services: [
                LinkedService(
                  id: 42,
                  title: 'user1001',
                  status: 'active',
                  profileId: profile.id,
                  outsourced: !mixed,
                ),
              ],
            ),
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
        theme: shikooThemeData(Brightness.light, tv: false),
        home: const ShikooHome(),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShikooHome)),
  );
  container.read(currentProfileIdProvider.notifier).value = profile.id;
  container.read(groupsProvider.notifier).value = [
    Group(
      type: GroupType.Selector,
      name: 'PROXY',
      hidden: false,
      all: [
        const Proxy(name: 'آلمان ۱', type: 'OpenVPN'),
        if (mixed)
          const Proxy(name: 'هلند ۱', type: 'Vless')
        else
          const Proxy(name: 'آلمان ۲', type: 'OpenVPN'),
      ],
    ),
  ];
  if (mixed) {
    container
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap('PROXY', 'آلمان ۱');
  }
  await container.read(shikooModeProvider.notifier).save(mode);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  final l = lookupShikooL10n(const Locale('fa'));
  final gauge = find.byWidgetPredicate(
    (w) => w is ShikooIconButton && w.icon == ShikooIcon.gauge,
  );

  testWidgets(
    "a shelf account's card on Windows in proxy mode: the line, no server "
    'list, the round button dimmed and the pill hidden',
    (tester) async {
      await _pump(tester, ShikooMode.proxy);
      expect(
        find.descendant(
          of: find.byType(ServiceCard),
          matching: find.text(
            l.outsourcedNotHere(l.modeTunnel, l.powerConnect),
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(ServerRow), findsNothing);
      expect(tester.widget<ShikooIconButton>(gauge).onPressed, isNull);
      expect(
        tester.widget<PowerButton>(find.byType(PowerButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<Visibility>(
              find
                  .ancestor(
                    of: find.byType(NowPill),
                    matching: find.byType(Visibility),
                  )
                  .first,
            )
            .visible,
        isFalse,
      );
    },
    variant: windows,
  );

  testWidgets(
    "a shelf account's card on Windows in tunnel mode: no such line, its "
    'servers, the round button and the pill, as on a phone',
    (tester) async {
      await _pump(tester, ShikooMode.tunnel);
      expect(
        find.text(l.outsourcedNotHere(l.modeTunnel, l.powerConnect)),
        findsNothing,
      );
      expect(tester.widget<ShikooIconButton>(gauge).onPressed, isNotNull);
      expect(
        find.descendant(
          of: find.byType(ServiceCard),
          matching: find.byType(ServerRow),
        ),
        findsNWidgets(2),
      );
      expect(
        tester.widget<PowerButton>(find.byType(PowerButton)).onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<Visibility>(
              find
                  .ancestor(
                    of: find.byType(NowPill),
                    matching: find.byType(Visibility),
                  )
                  .first,
            )
            .visible,
        isTrue,
      );
    },
    variant: windows,
  );

  testWidgets(
    'a usual service on an OpenVPN pick in the proxy mode: its list has only '
    'what runs there, nothing selected or green, and no line about the '
    'account; back in the tunnel mode the pick is in its row again',
    (tester) async {
      await _pump(tester, ShikooMode.proxy, mixed: true);
      expect(
        find.text(l.outsourcedNotHere(l.modeTunnel, l.powerConnect)),
        findsNothing,
      );
      final rows = tester.widgetList<ServerRow>(find.byType(ServerRow));
      expect(rows.map((row) => row.server.name), ['هلند ۱']);
      expect(rows.any((row) => row.selected), isFalse);
      final power = tester.widget<PowerButton>(find.byType(PowerButton));
      expect(power.connection, ShikooConnection.off);
      expect(power.onPressed, isNotNull);
      expect(tester.widget<NowPill>(find.byType(NowPill)).server, isNull);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShikooHome)),
      );
      await container.read(shikooModeProvider.notifier).save(ShikooMode.tunnel);
      await tester.pump(const Duration(seconds: 1));
      final back = tester.widgetList<ServerRow>(find.byType(ServerRow));
      expect(
        {for (final row in back) row.server.name: row.selected},
        {'آلمان ۱': true, 'هلند ۱': false},
      );
    },
    variant: windows,
  );

  for (final code in ['fa', 'en']) {
    testWidgets(
      "$code: a shelf account's line sends to the tunnel mode under the "
      'connect button by their labels, and shows only on Windows in proxy mode',
      (tester) async {
        final l = lookupShikooL10n(Locale(code));
        final (tunnel, under) = code == 'fa'
            ? ('«${l.modeTunnel}»', 'زیر دکمهٔ «${l.powerConnect}»')
            : (l.modeTunnel, 'under the ${l.powerConnect} button');
        expect(
          l.outsourcedNotHere(l.modeTunnel, l.powerConnect),
          allOf(contains(tunnel), contains(under)),
        );
        for (final (desktop, mode, shown) in [
          (true, ShikooMode.proxy, true),
          (true, ShikooMode.tunnel, false),
          (false, ShikooMode.proxy, false),
        ]) {
          await _pump(tester, mode, locale: code, desktop: desktop);
          expect(
            find.text(l.outsourcedNotHere(l.modeTunnel, l.powerConnect)),
            shown ? findsOneWidget : findsNothing,
            reason: 'Windows: $desktop, $mode',
          );
        }
      },
      variant: windows,
    );
  }
}
