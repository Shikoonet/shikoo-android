import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// lib/shikoo/ui/ reaches FlClash only through lib/shikoo/engine/ (docs/extensibility.md section 1).
const _uiRoot = 'lib/shikoo/ui';
const _allowed = ['lib/shikoo/engine/', 'lib/shikoo/l10n/', 'lib/shikoo/ui/'];
final _directive = RegExp(
  r'^[ \t]*(?:import|export|part)\b([^;]*);',
  multiLine: true,
);
final _uri = RegExp(r'''['"]([^'"]+)['"]''');

/// The repo-relative file an import points at, or null for an SDK or other package.
String? resolveImport(String file, String uri) {
  if (uri.startsWith('dart:')) return null;
  const own = 'package:fl_clash/';
  if (uri.startsWith('package:')) {
    return uri.startsWith(own)
        ? p.posix.normalize('lib/${uri.substring(own.length)}')
        : null;
  }
  return p.posix.normalize(p.posix.join(p.posix.dirname(file), uri));
}

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

List<String> violations(String file, String source) => [
  for (final directive in _directive.allMatches(source))
    for (final uri in _uri.allMatches(directive[1]!))
      if (resolveImport(file, uri[1]!) case final target?)
        if (!_allowed.any(target.startsWith))
          '$file:${_lineOf(source, directive.start)} imports $target',
];

void main() {
  const file = 'lib/shikoo/ui/home.dart';

  test('the guard catches every way out of lib/shikoo/ui', () {
    final escapes = [
      "import 'package:fl_clash/providers/providers.dart';",
      "import '../../providers/app.dart';",
      "import '../app/app.dart';",
      "import 'package:fl_clash/shikoo/app/main.dart';",
      "export 'package:fl_clash/widgets/focus.dart';",
      "import 'package:fl_clash/shikoo/engine/../../providers/providers.dart';",
      "import\n    'package:fl_clash/providers/providers.dart';",
      "import 'theme.dart'\n    if (dart.library.io) 'package:fl_clash/state.dart';",
    ];
    for (final escape in escapes) {
      expect(violations(file, escape), hasLength(1), reason: escape);
    }
  });

  test('the guard lets the engine, translations and screens through', () {
    expect(
      violations(file, '''
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import '../engine/controller.dart';
import 'package:fl_clash/shikoo/l10n/generated/shikoo_l10n.dart';
import 'theme.dart' show ShikooTheme;
'''),
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
          f.readAsStringSync(),
        ),
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
