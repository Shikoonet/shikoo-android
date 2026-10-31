import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
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
Future<void> _pump(WidgetTester tester, ShikooMode mode) async {
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
        shikooDesktopProvider.overrideWithValue(true),
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
                  outsourced: true,
                ),
              ],
            ),
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('fa'),
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
    const Group(
      type: GroupType.Selector,
      name: 'PROXY',
      hidden: false,
      all: [
        Proxy(name: 'آلمان ۱', type: 'OpenVPN'),
        Proxy(name: 'آلمان ۲', type: 'OpenVPN'),
      ],
    ),
  ];
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
          matching: find.text(l.outsourcedNotHere),
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
      expect(find.text(l.outsourcedNotHere), findsNothing);
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
}
