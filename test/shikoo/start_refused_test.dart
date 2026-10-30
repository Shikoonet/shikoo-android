import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('$packageName/service');

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test("the native side's -2 is a start the OpenVPN server refused the login "
      'of; -1 any other failed start', () async {
    for (final (ms, failed, refused) in [
      (-2, true, true),
      (-1, true, false),
      (0, false, false),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => ms);
      expect(await Service().getRunTime(), isNull);
      expect(
        (Service().startFailed, Service().loginRefused),
        (failed, refused),
        reason: '$ms',
      );
    }
  });

  test('ServicePlugin answers -2 for a start that failed on OpenVPN 3\'s '
      'AUTH_FAILED, which ServiceController reads off the error', () {
    String read(String path) => File(path).readAsStringSync();
    expect(
      read(
        'android/app/src/main/kotlin/com/follow/clash/plugins/ServicePlugin.kt',
      ),
      contains('ServiceController.startRefusedLogin -> -2L'),
    );
    expect(
      read('android/app/src/main/kotlin/com/follow/clash/ServiceController.kt'),
      contains('.contains(OPENVPN_AUTH_FAILED)'),
    );
    expect(
      read('android/service/src/main/java/com/follow/clash/service/OpenVpn.kt'),
      contains('const val OPENVPN_AUTH_FAILED = "AUTH_FAILED"'),
    );
  });
}
