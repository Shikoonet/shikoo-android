import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/shikoo/engine/core_sing_box.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sing-box serves the servers core/shikoo_singbox.go converts', () {
    final json = File('core/testdata/sing_box_serves.json').readAsStringSync();
    final cases = jsonDecode(json) as List;
    expect(cases, isNotEmpty);
    for (final entry in cases.cast<Map<String, dynamic>>()) {
      final proxy = entry['proxy'] as Map<String, dynamic>;
      expect(
        singBoxSpec.serves(protocolOf(proxy), proxy),
        entry['serves'],
        reason: '${proxy['name']}',
      );
    }
  });

  test('every protocol sing-box can carry lists it as a ready option', () {
    final rows = coreRows(ShikooProtocol.values.toSet(), const {
      ShikooProtocol.vless: ShikooCore.singBox,
    });
    for (final row in rows) {
      expect(
        row.options,
        contains((core: ShikooCore.singBox, ready: true)),
        reason: row.protocol.name,
      );
    }
    expect(rows.first.chosen, ShikooCore.singBox);
  });
}
