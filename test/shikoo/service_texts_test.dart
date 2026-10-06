import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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

  test('the VPN notification and its toasts follow the app language', () async {
    expect(texts(), ('قطع اتصال', 'در حال اتصال…', 'در حال قطع اتصال…'));

    await container.read(shikooLookProvider.notifier).setLanguage('en');
    expect(texts(), ('Disconnect', 'Connecting…', 'Disconnecting…'));

    await container.read(shikooLookProvider.notifier).setLanguage('xx');
    expect(texts().$1, 'قطع اتصال');
  });
}
