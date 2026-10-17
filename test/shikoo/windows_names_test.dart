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

  test('the data folder is ShikooNet\\ShikooNet and its uninstall deletes '
      'it; the installer has its own id, starts the app unelevated, and the '
      'app leaves the clash:// links alone', () {
    String read(String path) => File(path).readAsStringSync();

    expect(
      read('windows/runner/Runner.rc'),
      allOf(
        contains('VALUE "CompanyName", "$appName"'),
        contains('VALUE "ProductName", SHIKOO_TITLE "\\0"'),
      ),
    );
    expect(
      read('windows/CMakeLists.txt'),
      contains('else()\n  set(SHIKOO_TITLE "$appName")\nendif()\n'),
    );
    expect(
      read('windows/packaging/exe/make_config.yaml'),
      allOf(
        contains('app_id: F4E58B87-08F9-43F1-8B65-640490A48F0E\n'),
        contains('executable_name: $appName.exe\n'),
        contains('publisher_url: https://t.me/shikoonet\n'),
      ),
    );
    final iss = read('windows/packaging/exe/inno_setup.iss');
    for (final root in ['userappdata', 'localappdata']) {
      expect(
        iss,
        allOf(
          contains(
            'Type: filesandordirs; Name: "{$root}\\$appName\\{#Title}"\n',
          ),
          isNot(contains('Name: "{$root}"')),
        ),
      );
    }
    expect(iss, contains('runasoriginaluser'));
    expect(iss, isNot(contains('runascurrentuser')));
    expect(
      read('lib/common/window.dart'),
      isNot(contains('protocol.register(')),
    );
  });

  test('the installer is English only, in three pages ending in Install, '
      'installs the helper service on every install, over an old one too, '
      'and the uninstall removes it', () {
    String read(String path) => File(path).readAsStringSync();
    final iss = read('windows/packaging/exe/inno_setup.iss');

    expect(
      read('windows/packaging/exe/make_config.yaml'),
      contains('locales:\n  - lang: en\nprivileges_required'),
    );
    expect(iss, isNot(contains(RegExp('[؀-ۿ]'))));
    expect(
      iss,
      allOf(contains('DisableDirPage=yes'), contains('DisableReadyPage=yes')),
    );
    expect(
      iss,
      contains(
        'procedure CurPageChanged(CurPageID: Integer);\n'
        'begin\n'
        '  if CurPageID = wpSelectTasks then\n'
        '    WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);\n'
        'end;\n',
      ),
    );
    final service = iss
        .split('\n')
        .where((line) => line.contains('"{app}\\$appHelperService.exe"'))
        .toList();
    expect(service, hasLength(1));
    expect(service.single, contains('Parameters: "install"'));
    expect(service.single, isNot(matches(RegExp('postinstall|skipifsilent'))));
    final sections = RegExp(
      r'^\[\w+\]$',
      multiLine: true,
    ).allMatches(iss.substring(0, iss.indexOf(service.single)));
    expect(sections.last[0], '[Run]');
    final unregister = RegExp(
      r'procedure UnregisterHelperService;[\s\S]*?\nend;',
    ).firstMatch(iss)![0]!;
    final orElse = unregister.indexOf('  end\n  else\n');
    expect(orElse, isNot(-1));
    expect(
      unregister.substring(orElse),
      contains(
        "Exec(ExpandConstant('{sys}\\sc.exe'), 'delete $appHelperService'",
      ),
    );
    for (final hook in ['PrepareToInstall', 'InitializeUninstall']) {
      expect(
        iss,
        matches(
          RegExp(
            'function $hook\\([^)]*\\):[^;]*;\\s*begin\\s*UnregisterHelperService;',
          ),
        ),
        reason: hook,
      );
    }
  });

  test('SHIKOO_FLAVOR=staging builds "ShikooNet Test": its own installer id, '
      'name, program and data folders and Start menu entry; and a silent '
      'install opens the app again', () {
    String read(String path) => File(path).readAsStringSync();
    const title = 'ShikooNet Test';
    final iss = read('windows/packaging/exe/inno_setup.iss');

    expect(
      read('windows/CMakeLists.txt'),
      allOf(
        contains(
          'if("\$ENV{SHIKOO_FLAVOR}" STREQUAL "staging")\n'
          '  set(SHIKOO_TITLE "$title")\n',
        ),
        contains(
          r'target_compile_definitions(${BINARY_NAME} PRIVATE '
          r'"SHIKOO_TITLE=\"${SHIKOO_TITLE}\"")',
        ),
      ),
    );
    expect(
      read('windows/runner/main.cpp'),
      contains('window.Create(L"" SHIKOO_TITLE, origin, size)'),
    );
    expect(
      iss,
      contains(
        '#if GetEnv("SHIKOO_FLAVOR") == "staging"\n'
        '#define Title "$title"\n'
        '#define Id "D6F866A6-CE01-4C34-A9C5-C49D6D030A27"\n'
        '#else\n'
        '#define Title "{{DISPLAY_NAME}}"\n'
        '#define Id "{{APP_ID}}"\n'
        '#endif\n'
        '[Setup]\n'
        'AppId={#Id}\n',
      ),
    );
    for (final line in [
      'AppName={#Title}\n',
      r'DefaultDirName={autopf64}\{#Title}'
          '\n',
      'UninstallDisplayName={#Title}\n',
      r'Name: "{autoprograms}\{#Title}";',
    ]) {
      expect(iss, contains(line));
    }
    expect('{{DISPLAY_NAME}}'.allMatches(iss), hasLength(1));
    expect('{{APP_ID}}'.allMatches(iss), hasLength(1));
    expect(
      iss,
      contains(
        'postinstall skipifsilent\n'
        r'Filename: "{app}\\{{EXECUTABLE_NAME}}"; '
        'Flags: runasoriginaluser nowait skipifnotsilent\n',
      ),
    );
  });
}
