import 'dart:typed_data';

import 'package:fl_clash/shikoo/engine/diag.dart';

/// A press on «پشتیبانی» or a report entry first takes the screen's two pictures; in a test the
/// platform's half would answer outside fake time and the page would wait for it.
class NoShots extends ShikooDiag {
  @override
  Future<Uint8List?> captureApp() async => null;

  @override
  Future<Uint8List?> captureScreen() async => null;
}

final noShots = shikooDiagProvider.overrideWithValue(NoShots());
