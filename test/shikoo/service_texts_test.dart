import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    await AppLocalizations.load(const Locale('en'));
    serviceTexts = shikooServiceTexts;
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    container.listen(sharedStateProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    serviceTexts = null;
  });

  (String, String, String) texts() {
    final state = container.read(sharedStateProvider);
    return (state.stopText, state.startTip, state.stopTip);
  }

  test('the VPN notification and its toasts follow the loaded locale', () {
    expect(texts(), ('قطع اتصال', 'در حال اتصال…', 'در حال قطع اتصال…'));

    container.read(loadedLocaleProvider.notifier).value = const Locale('en');
    expect(texts(), ('Disconnect', 'Connecting…', 'Disconnecting…'));

    container.read(loadedLocaleProvider.notifier).value = const Locale('fa');
    expect(texts().$1, 'قطع اتصال');
  });

  test('the launcher shortcut reaches Android in the app language', () async {
    const channel = MethodChannel('$packageName/app');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final labels = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initShortcuts') labels.add(call.arguments);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (final language in ['fa', 'en', 'xx']) {
      await registerShortcut(App(), language);
    }
    expect(labels, ['وصل / قطع', 'Connect / Disconnect', 'وصل / قطع']);
  });
}
