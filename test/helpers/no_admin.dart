import 'package:fl_clash/shikoo/engine/mode.dart';

/// On a Windows host the real one runs the helper with `runas`: a connect in a test would put
/// Windows' admin prompt on the desk of whoever runs the suite.
final noAdminPrompt = tunAuthorizeProvider.overrideWithValue(
  () async => ShikooAdmin.refused,
);
