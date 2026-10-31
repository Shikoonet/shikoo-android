import 'dart:io';

import 'package:fl_clash/common/boot_guard.dart';
import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/shikoo/app/main.dart' show forgetUnfinishedLaunch;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test(
    'an unfinished launch brings no FlClash dialog and keeps the service',
    () async {
      await preferences.saveBootRecord(
        const BootRecord(
          stage: BootStage.starting,
          profileId: 1,
          failureCount: 5,
        ),
      );

      await forgetUnfinishedLaunch();
      final decision = await BootGuard(
        supported: true,
        readExitInfo: () async => null,
        readCrashReport: () async => false,
      ).evaluate(profileId: 1, crashlyticsEnabled: false);

      expect(decision.recovery, BootRecovery.none);
    },
  );

  test('main forgets the unfinished launch before bootstrap reads it', () {
    final source = File('lib/shikoo/app/main.dart').readAsStringSync();
    final forget = source.indexOf('await forgetUnfinishedLaunch();');

    expect(forget, isNonNegative);
    expect(forget, lessThan(source.indexOf('bootstrap.init(')));
  });

  test('main takes back a crashed core once the picks are loaded, before the '
      'app that applies them runs', () {
    final source = File('lib/shikoo/app/main.dart').readAsStringSync();
    final load = source.indexOf('read(shikooCoresProvider.notifier).load()');
    final forget = source.indexOf('.forgetCrashed(await appPath.homeDirPath)');

    expect(load, isNonNegative);
    expect(forget, greaterThan(load));
    expect(forget, lessThan(source.indexOf('child: const ShikooApp()')));
  });
}
