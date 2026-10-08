import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every launcher, round, TV, Play and adaptive icon, the banner, the '
      'notification and tile icon and the in-app mark come from '
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
      '66dp circle that no launcher mask cuts, at every density', () async {
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
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      final image = await _decode(
        '$_res/drawable-$density/ic_launcher_foreground.png',
      );
      final alpha = await _alpha(image);
      final w = image.width;
      var farthest = 0.0;
      for (var i = 0; i < alpha.length; i++) {
        if (alpha[i] > 0) {
          final dx = i % w + 0.5 - w / 2;
          final dy = i ~/ w + 0.5 - w / 2;
          farthest = max(farthest, sqrt(dx * dx + dy * dy) * 108 / w);
        }
      }
      expect(farthest, inInclusiveRange(28, 33), reason: density);
    }
  });

  test('the TV banner is the 320x180 Android TV asks for at xhdpi', () async {
    final image = await _decode('$_res/mipmap-xhdpi/ic_banner.png');
    expect((image.width, image.height), (320, 180));
  });

  test('the notification and tile icons draw the fox, not a filled box: '
      'clear corners and under 60% of the square filled', () async {
    const size = 96;
    const arity = {'M': 2, 'L': 2, 'C': 6};
    for (final name in ['ic', 'ic_service']) {
      final xml = File(
        'android/service/src/main/res/drawable/$name.xml',
      ).readAsStringSync();
      String attr(String a) =>
          RegExp('android:$a="([^"]+)"').firstMatch(xml)!.group(1)!;
      final path = ui.Path()
        ..fillType = attr('fillType') == 'evenOdd'
            ? ui.PathFillType.evenOdd
            : ui.PathFillType.nonZero;
      var command = '';
      final n = <double>[];
      for (final t in RegExp(r'[MLCZ]|-?[\d.]+').allMatches(attr('pathData'))) {
        final token = t[0]!;
        if (token == 'Z') {
          path.close();
        } else if (arity.containsKey(token)) {
          command = token;
        } else if ((n..add(double.parse(token))).length == arity[command]) {
          switch (command) {
            case 'M':
              path.moveTo(n[0], n[1]);
            case 'L':
              path.lineTo(n[0], n[1]);
            default:
              path.cubicTo(n[0], n[1], n[2], n[3], n[4], n[5]);
          }
          n.clear();
        }
      }
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..scale(size / double.parse(attr('viewportWidth')))
        ..drawPath(path, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      final alpha = await _alpha(
        await recorder.endRecording().toImage(size, size),
      );
      final filled = alpha.where((a) => a > 127).length / alpha.length;
      expect(filled, inInclusiveRange(0.15, 0.6), reason: name);
      for (final corner in [0, size - 1, size * (size - 1), size * size - 1]) {
        expect(alpha[corner], 0, reason: '$name, corner pixel $corner');
      }
    }
  });
}

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<List<int>> _alpha(ui.Image image) async {
  final rgba = (await image.toByteData())!;
  return [for (var i = 3; i < rgba.lengthInBytes; i += 4) rgba.getUint8(i)];
}
