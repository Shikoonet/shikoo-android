import 'package:fl_clash/shikoo/app/licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the libraries in libovpn3.so ship with their licenses', () async {
    addNativeLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) => entries
        .where((entry) => entry.packages.contains(package))
        .expand((entry) => entry.paragraphs)
        .map((paragraph) => paragraph.text)
        .join('\n');

    expect(textOf('OpenVPN 3'), contains('Mozilla Public License Version 2.0'));
    expect(textOf('OpenVPN 3'), contains('github.com/OpenVPN/openvpn3'));
    expect(textOf('Mbed TLS'), contains('Apache License'));
    expect(textOf('LZ4'), contains('Redistributions in binary form'));
  });
}
