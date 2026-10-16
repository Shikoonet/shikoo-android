import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the core stops asking which app owns a connection once Shikoo '
      'writes its config', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(updateParamsProvider).findProcessMode,
      FindProcessMode.always,
    );

    container.read(patchClashConfigProvider.notifier).update(shikooClashConfig);

    final params = container.read(updateParamsProvider);
    expect(params.findProcessMode, FindProcessMode.off);
    expect(params.logLevel, LogLevel.warning);
  });
}
