import 'dart:io';

import 'package:fl_clash/shikoo/app/licenses.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the Go core ships its licences: Xray under the MPL, sing-box, wireguard-go, gvisor and mihomo',
    () async {
      final entries = await goLicenses().toList();
      String textOf(String module) => entries
          .firstWhere(
            (entry) => entry.packages.contains(module),
            orElse: () => throw TestFailure('no licence for $module'),
          )
          .paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');

      expect(
        textOf('github.com/xtls/xray-core'),
        contains('Mozilla Public License Version 2.0'),
      );
      expect(
        textOf('github.com/sagernet/sing-box'),
        contains('GNU General Public License'),
      );
      expect(
        textOf('github.com/metacubex/chacha'),
        allOf(contains('MIT License'), isNot(contains('ships no licence'))),
      );
      for (final module in [
        'golang.zx2c4.com/wireguard',
        'github.com/sagernet/wireguard-go',
        'github.com/metacubex/gvisor',
        'github.com/sagernet/gvisor',
        'github.com/metacubex/mihomo',
      ]) {
        expect(textOf(module), isNotEmpty, reason: module);
      }
    },
  );

  test('the shell registers them before the first frame', () {
    final shell = File('lib/shikoo/app/main.dart').readAsStringSync();
    expect(shell, contains('registerGoLicenses();'));
  });
}
