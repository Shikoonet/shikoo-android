import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/shikoo/app/roots.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the bundled root is ISRG Root X1', () {
    final body = isrgRootX1
        .split('\n')
        .where((line) => !line.startsWith('-----'))
        .join();
    expect(
      sha256.convert(base64.decode(body)).toString(),
      '96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6',
    );
  });

  test('a context with the system roots takes it, twice too', () {
    expect(
      () => SecurityContext().setTrustedCertificatesBytes('no pem'.codeUnits),
      throwsA(isA<TlsException>()),
    );
    final context = SecurityContext(withTrustedRoots: true);
    expect(() => trustIsrgRootX1(context), returnsNormally);
    expect(() => trustIsrgRootX1(context), returnsNormally);
    expect(trustIsrgRootX1, returnsNormally);
  });

  test('the shell adds it on Android before the first request', () {
    final shell = File('lib/shikoo/app/main.dart').readAsStringSync();
    expect(shell, contains('if (Platform.isAndroid) trustIsrgRootX1();'));
    expect(
      shell.indexOf('trustIsrgRootX1();'),
      lessThan(shell.indexOf('bootstrap.init(')),
    );
  });
}
