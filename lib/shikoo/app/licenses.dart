import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Go core's modules and their licences, in the NOTICES form; written by `tools/shikoo-go-licenses.py`.
const _notices = 'assets/data/shikoo-go-licenses.txt';

void registerGoLicenses() => LicenseRegistry.addLicense(goLicenses);

Stream<LicenseEntry> goLicenses() async* {
  final notices = await rootBundle.loadString(_notices);
  for (final entry in notices.trimRight().split('\n${'-' * 80}\n')) {
    final head = entry.indexOf('\n\n');
    yield LicenseEntryWithLineBreaks(
      entry.substring(0, head).split('\n'),
      entry.substring(head + 2),
    );
  }
}

const _nativeLicenses = <(String, String)>[
  ('OpenVPN 3', 'assets/data/LICENSE-openvpn3.txt'),
  ('Mbed TLS', 'assets/data/LICENSE-mbedtls.txt'),
  ('LZ4', 'assets/data/LICENSE-lz4.txt'),
];

void addNativeLicenses() => LicenseRegistry.addLicense(() async* {
  for (final (package, asset) in _nativeLicenses) {
    yield LicenseEntryWithLineBreaks([
      package,
    ], await rootBundle.loadString(asset));
  }
});
