import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Go core's modules and their licences, in the NOTICES form; written by `tools/shikoo-go-licenses.py`.
const goLicensesAsset = 'assets/data/shikoo-go-licenses.txt';

/// Beside the Dart packages' licences, which Flutter registers by itself.
void registerGoLicenses() => LicenseRegistry.addLicense(goLicenses);

Stream<LicenseEntry> goLicenses() async* {
  final notices = await rootBundle.loadString(goLicensesAsset);
  for (final entry in notices.trimRight().split('\n${'-' * 80}\n')) {
    final head = entry.indexOf('\n\n');
    yield LicenseEntryWithLineBreaks(
      entry.substring(0, head).split('\n'),
      entry.substring(head + 2),
    );
  }
}
