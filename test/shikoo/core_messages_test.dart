import 'dart:io';

import 'package:fl_clash/common/dialog.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/core_manager.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/state.dart' show serviceTexts;
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'package:fl_clash/shikoo/ui/theme.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class _Core extends Mock implements CoreHandlerInterface {}

const _wg =
    '[WG](germany) peer(AbCd…WxYz) - Failed to send data packets: write udp '
    '198.51.100.7:42484->203.0.113.5:51820: write: network is unreachable';
const _warning = 'VPN config change detected';

void main() {
  testWidgets("the core's errors and FlClash's warnings reach the log, not the "
      'screen', (tester) async {
    fillFlClashHooks();
    addTearDown(() {
      StatusManager.showMessages = true;
      serviceTexts = null;
    });
    final printed = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    final home = Directory.systemTemp.createTempSync('core_messages');
    addTearDown(() => home.deleteSync(recursive: true));
    final diag = ShikooDiag();
    await diag.start(home.path);
    diag.release();
    coreEventManager.addListener(diag);
    addTearDown(() => coreEventManager.removeListener(diag));
    final core = _Core();
    when(core.startLog).thenAnswer((_) {});
    when(core.stopLog).thenAnswer((_) {});
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          locale: const Locale('fa'),
          supportedLocales: ShikooL10n.supportedLocales,
          localizationsDelegates: const [
            ShikooL10n.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: shikooThemeData(Brightness.light, tv: false),
          builder: (context, child) => shikooFrame(
            context,
            child!,
            managers: (page) => StatusManager(child: CoreManager(child: page)),
          ),
          home: const Scaffold(),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    container.read(coreStatusProvider.notifier).value = CoreStatus.connected;

    coreEventManager
      ..sendEvent(
        const CoreEvent(
          type: CoreEventType.log,
          data: {'LogLevel': 'error', 'Payload': _wg},
        ),
      )
      ..sendEvent(const CoreEvent(type: CoreEventType.crash, data: 'boom'));
    dialogs.showNotifier(_warning, level: MessageLevel.warning);
    await tester.pumpAndSettle();
    debugPrint = print;

    expect(find.textContaining('Failed to send'), findsNothing);
    expect(find.text('boom'), findsNothing);
    expect(find.text(_warning), findsNothing);
    expect(
      printed,
      containsAll([
        '[APP] message: $_wg',
        '[APP] message: boom',
        '[APP] message: $_warning',
      ]),
    );
    expect(
      File('${home.path}/shikoo/diag.log').readAsStringSync(),
      contains('Failed to send data packets'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
