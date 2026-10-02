import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// lib/shikoo/ui/ talks to the engine only through lib/shikoo/engine/ (docs/extensibility.md
/// section 1): no FlClash import, no shell import, whether written as a package or a relative path.
const _uiRoot = 'lib/shikoo/ui';
const _allowed = ['lib/shikoo/engine/', 'lib/shikoo/l10n/', 'lib/shikoo/ui/'];
final _directive = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''');

/// The repo-relative file an import points at, or null for an SDK or other package.
String? resolveImport(String file, String uri) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    const own = 'package:fl_clash/';
    return uri.startsWith(own) ? 'lib/${uri.substring(own.length)}' : null;
  }
  return p.posix.normalize(p.posix.join(p.posix.dirname(file), uri));
}

List<String> violations(String file, List<String> lines) => [
  for (var i = 0; i < lines.length; i++)
    if (_directive.firstMatch(lines[i]) case final match?)
      if (resolveImport(file, match[1]!) case final target?)
        if (!_allowed.any(target.startsWith)) '$file:${i + 1} imports $target',
];

void main() {
  test('the guard catches package and relative escapes', () {
    const file = 'lib/shikoo/ui/home.dart';
    expect(
      violations(file, [
        "import 'package:fl_clash/providers/providers.dart';",
        "import '../../providers/app.dart';",
        "import '../app/app.dart';",
        "import 'package:fl_clash/shikoo/main.dart';",
        "export 'package:fl_clash/widgets/focus.dart';",
      ]),
      hasLength(5),
    );
    expect(
      violations(file, [
        "import 'dart:async';",
        "import 'package:material_ui/material_ui.dart';",
        "import 'package:fl_clash/shikoo/engine/controller.dart';",
        "import '../engine/controller.dart';",
        "import 'theme.dart';",
      ]),
      isEmpty,
    );
  });

  test('lib/shikoo/ui imports neither FlClash nor the shell', () {
    final files = Directory(_uiRoot)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    final offenders = [
      for (final f in files)
        ...violations(
          p.posix.joinAll(p.split(p.relative(f.path))),
          f.readAsLinesSync(),
        ),
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
