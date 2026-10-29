import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/shikoo/engine/core_xray.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Xray serves the servers core/shikoo_xray.go converts', () {
    final json = File('core/testdata/xray_serves.json').readAsStringSync();
    final cases = jsonDecode(json) as List;
    expect(cases, isNotEmpty);
    for (final entry in cases.cast<Map<String, dynamic>>()) {
      final proxy = entry['proxy'] as Map<String, dynamic>;
      expect(
        xraySpec.serves(protocolOf(proxy), proxy),
        entry['serves'],
        reason: '${proxy['name']}',
      );
    }
  });

  test('VLESS and WireGuard list Xray as a ready option', () {
    final rows = coreRows(
      {ShikooProtocol.vless, ShikooProtocol.wireguard},
      const {ShikooProtocol.vless: ShikooCore.xray},
    );
    for (final row in rows) {
      expect(
        row.options,
        contains((core: ShikooCore.xray, ready: true)),
        reason: row.protocol.name,
      );
    }
    expect(rows.first.chosen, ShikooCore.xray);
  });
}
