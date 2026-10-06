import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FlClash looks up no IP once Shikoo writes its settings', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(checkIpProvider, (_, _) {});
    expect(container.read(checkIpProvider).containsDetection, isTrue);

    container.read(appSettingProvider.notifier).update(shikooAppSettings);

    expect(container.read(checkIpProvider).containsDetection, isFalse);
  });
}
