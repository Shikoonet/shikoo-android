import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart, Rust, CMake, build_config.yaml and the installer name one '
      "helper service, core, pipe and port, none of them FlClash's", () {
    const core = 'ShikooNetCore';
    String read(String path) => File(path).readAsStringSync();

    expect(appHelperService, 'ShikooNetHelperService');
    expect(helperPort, isNot(47890));
    expect(windowsPipeName, startsWith('\\\\.\\pipe\\${core}_'));
    expect(
      read('build_config.yaml'),
      allOf(
        contains('core_name: $core\n'),
        contains('helper_name: $appHelperService\n'),
      ),
    );
    expect(read('lib/common/path.dart'), contains("'$core\$executable"));
    expect(
      read('services/helper/src/service/windows.rs'),
      contains('SERVICE_NAME: &str = "$appHelperService";'),
    );
    expect(
      read('services/helper/src/service/hub.rs'),
      allOf(
        contains('LISTEN_PORT: u16 = $helperPort;'),
        contains('CORE_PIPE_PREFIX: &str = r"\\\\.\\pipe\\${core}_";'),
      ),
    );
    for (final file in [
      'services/helper/build.rs',
      'windows/CMakeLists.txt',
      'windows/packaging/exe/inno_setup.iss',
    ]) {
      final text = read(file);
      expect(text, contains('$core.exe'), reason: file);
      expect(text, isNot(contains('FlClash')), reason: file);
    }
    expect(
      read('windows/packaging/exe/inno_setup.iss'),
      contains("'$appName.exe', '$core.exe', '$appHelperService.exe'"),
    );
  });
}
