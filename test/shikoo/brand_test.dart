import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
