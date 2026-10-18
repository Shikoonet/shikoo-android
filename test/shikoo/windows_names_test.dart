import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('Dart, Rust, CMake, build_config.yaml and the installer name one '
      'helper service, pipe and port per flavor, and close only their own '
      "processes, none of them FlClash's", () {
    const core = 'ShikooNetCore';
    final iss = read('windows/packaging/exe/inno_setup.iss');

    expect(appHelperService, 'ShikooNetHelperService');
    expect(
      read('build_config.yaml'),
      allOf(
        contains('core_name: $core\n'),
        contains('helper_name: $appHelperService\n'),
        contains('flavor: production\n'),
      ),
    );
    expect(read('lib/common/path.dart'), contains("'$core\$executable"));
    expect(
      read('lib/common/constant.dart'),
      allOf(
        contains(
          "const appName = shikooStagingBuild ? 'ShikooNet Test' : 'ShikooNet';",
        ),
        contains("\${shikooStagingBuild ? 'ShikooNetTestCore' : '$core'}_"),
        contains('const helperPort = shikooStagingBuild ? 47892 : 47891;'),
      ),
    );
    expect(read('lib/shikoo/app/main.dart'), contains('shikooStagingBuild ||'));
    expect(
      read('services/helper/src/service/hub.rs'),
      allOf(
        contains(
          'LISTEN_PORT: u16 = if cfg!(shikoo_staging) { 47892 } else { 47891 };',
        ),
        contains(
          '    r"\\\\.\\pipe\\ShikooNetTestCore_"\n'
          '} else {\n'
          '    r"\\\\.\\pipe\\${core}_"\n',
        ),
      ),
    );
    expect(
      read('services/helper/src/service/windows.rs'),
      contains(
        'SERVICE_NAME: &str = if cfg!(shikoo_staging) {\n'
        '    "ShikooNetTestHelperService"\n'
        '} else {\n'
        '    "$appHelperService"\n',
      ),
    );
    expect(
      read('services/helper/build.rs'),
      contains('std::env::var("SHIKOO_FLAVOR").as_deref() == Ok("staging")'),
    );
    expect(
      read('plugins/setup/setup_hooks/lib/src/rust_builder.dart'),
      allOf(
        contains("'SHIKOO_FLAVOR': config.flavor,"),
        contains(
          "..addAll([...harnessInputs, p.join(rootDir, 'build_config.yaml')]);",
        ),
      ),
    );
    expect(
      iss,
      allOf(
        contains('#define Service "ShikooNetTestHelperService"\n'),
        contains('#define Service "$appHelperService"\n'),
        contains("'delete {#Service}'"),
        contains(
          'Get-Process ShikooNet,$core,$appHelperService -ErrorAction '
          r"SilentlyContinue | Where-Object { $_.Path -like ''' +",
        ),
        contains("ExpandConstant('{app}') + '\\*''"),
        isNot(contains('taskkill')),
      ),
    );
    for (final file in ['services/helper/build.rs', 'windows/CMakeLists.txt']) {
      expect(read(file), contains('$core.exe'), reason: file);
    }
    for (final file in [
      'services/helper/build.rs',
      'windows/CMakeLists.txt',
      'windows/packaging/exe/inno_setup.iss',
    ]) {
      expect(read(file), isNot(contains('FlClash')), reason: file);
    }
  });

  test('the names this test was compiled with follow SHIKOO_FLAVOR', () {
    expect(helperPort, shikooStagingBuild ? 47892 : 47891);
    expect(appName, shikooStagingBuild ? 'ShikooNet Test' : 'ShikooNet');
    expect(
      windowsPipeName,
      startsWith(
        shikooStagingBuild
            ? r'\\.\pipe\ShikooNetTestCore_'
            : r'\\.\pipe\ShikooNetCore_',
      ),
    );
  });

  test('the data folder is ShikooNet\\ShikooNet and its uninstall deletes '
      'it; the installer has its own id, starts the app unelevated, and the '
      'app leaves the clash:// links alone', () {
    expect(
      read('windows/runner/Runner.rc'),
      allOf(
        contains('VALUE "CompanyName", "ShikooNet"'),
        contains('VALUE "ProductName", SHIKOO_TITLE "\\0"'),
      ),
    );
    expect(
      read('windows/CMakeLists.txt'),
      contains('else()\n  set(SHIKOO_TITLE "ShikooNet")\nendif()\n'),
    );
    expect(
      read('windows/packaging/exe/make_config.yaml'),
      allOf(
        contains('app_id: F4E58B87-08F9-43F1-8B65-640490A48F0E\n'),
        contains('executable_name: ShikooNet.exe\n'),
        contains('publisher_url: https://t.me/shikoonet\n'),
      ),
    );
    final iss = read('windows/packaging/exe/inno_setup.iss');
    for (final root in ['userappdata', 'localappdata']) {
      expect(
        iss,
        allOf(
          contains(
            'Type: filesandordirs; Name: "{$root}\\ShikooNet\\{#Title}"\n',
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
      'installs the helper service on every install, and removes it even '
      'without its file', () {
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
      contains("Exec(ExpandConstant('{sys}\\sc.exe'), 'delete {#Service}'"),
    );
  });

  test('SHIKOO_FLAVOR=staging builds "ShikooNet Test": its own installer id, '
      'name, program and data folders and Start menu entry; and a silent '
      'install opens the app again', () {
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
        '#define Service "ShikooNetTestHelperService"\n'
        '#else\n'
        '#define Title "{{DISPLAY_NAME}}"\n'
        '#define Id "{{APP_ID}}"\n'
        '#define Service "ShikooNetHelperService"\n'
        '#endif\n'
        '[Setup]\n'
        'AppId={#Id}\n',
      ),
    );
    for (final line in [
      'AppName={#Title}\n',
      'DefaultDirName={autopf64}\\{#Title}\n',
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

  test('an upgrade, and an uninstall only once confirmed, remove the helper '
      "service and close the app, then put Windows' proxy back before the data "
      'goes, the upgrade as the user who started it', () {
    final iss = read('windows/packaging/exe/inno_setup.iss');
    const uninstall =
        r'Filename: "{app}\ShikooNet.exe"; Parameters: "--restore-proxy"; '
        r'Flags: runhidden waituntilterminated; RunOnceId: "ShikooRestoreProxy"'
        '\n';
    final at = iss.indexOf(uninstall);
    expect(at, isNot(-1));
    final sections = RegExp(
      r'^\[\w+\]$',
      multiLine: true,
    ).allMatches(iss.substring(0, at));
    expect(sections.last[0], '[UninstallRun]');
    expect(
      RegExp(r'function PrepareToInstall[\s\S]*?\nend;').firstMatch(iss)![0],
      contains(
        'begin\n'
        '  UnregisterHelperService;\n'
        '  KillProcesses;\n'
        r"  ExecAsOriginalUser(ExpandConstant('{app}\ShikooNet.exe'), "
        "'--restore-proxy', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);\n",
      ),
    );
    expect(iss, isNot(contains('function InitializeUninstall')));
    expect(
      iss,
      contains(
        'procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);\n'
        'begin\n'
        '  if CurUninstallStep = usUninstall then\n'
        '  begin\n'
        '    UnregisterHelperService;\n'
        '    KillProcesses;\n'
        '  end;\n'
        'end;\n',
      ),
    );
  });
}
