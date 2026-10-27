import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// What libovpn3.so is built from (android/service/src/main/cpp/CMakeLists.txt); MPL-2.0, Apache-2.0 and
/// BSD-2-Clause each ask for their text beside the binary. Android only: no other build ships the library.
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
