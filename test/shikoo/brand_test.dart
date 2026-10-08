import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("every launcher, round, TV, Play and adaptive icon, the banner, the "
      "notification and tile icon and the in-app mark come from "
      "tools/shikoo-brand.py, none of them FlClash's", () {
    final name = RegExp(
      r'^(ic_launcher.*|ic_banner|ic|ic_service|shikoo_mark)\.(png|webp|xml)$',
    );
    final files = [
      for (final root in [
        'android/app/src/main',
        'android/service/src/main',
        'assets/images',
      ])
        ...Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  name.hasMatch(f.uri.pathSegments.last) &&
                  !f.path.contains(RegExp('anydpi|/values')),
            ),
    ];
    expect(files, hasLength(25));
    for (final file in files) {
      expect(
        latin1.decode(file.readAsBytesSync()),
        contains('shikoo-brand'),
        reason: file.path,
      );
    }
  });

  test('the adaptive foreground of the phone and the TV stays inside the '
      '66dp circle that no launcher mask cuts', () async {
    for (final icon in [
      'mipmap-anydpi-v26/ic_launcher.xml',
      'mipmap-anydpi-v26/ic_launcher_round.xml',
      'mipmap-television-anydpi-v26/ic_launcher.xml',
    ]) {
      expect(
        File('$_res/$icon').readAsStringSync(),
        contains(
          '<foreground android:drawable="@drawable/ic_launcher_foreground"',
        ),
        reason: icon,
      );
    }
    final codec = await ui.instantiateImageCodec(
      File(
        '$_res/drawable-xxxhdpi/ic_launcher_foreground.png',
      ).readAsBytesSync(),
    );
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData())!;
    final dp = image.width / 108;
    var farthest = 0.0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (rgba.getUint8((y * image.width + x) * 4 + 3) > 0) {
          final dx = x + 0.5 - image.width / 2;
          final dy = y + 0.5 - image.height / 2;
          farthest = max(farthest, sqrt(dx * dx + dy * dy) / dp);
        }
      }
    }
    expect(farthest, inInclusiveRange(28, 33));
  });
}
