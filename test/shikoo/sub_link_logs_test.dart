import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/app.dart' show logsProvider;
import 'package:fl_clash/shikoo/app/main.dart' as app;
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _link = 'https://example.invalid/sub/AAAAsub7token0123456789abcdef';
const _token = 'AAAAsub7token0123456789abcdef';

void main() {
  test('an update hands its whole link to the app log: logcat, diag.log, the '
      'Logs page and the report get none of it, FlClash\'s in-memory list '
      'keeps it whole', () async {
    final printed = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = print);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState
      ..container = container
      ..isAttach = true;
    addTearDown(() => globalState.isAttach = false);

    // The call `_fetch` makes for every update (lib/shikoo/engine/controller.dart).
    FlClashHttpOverrides.findProxyForReader(container.read, Uri.parse(_link));
    expect(printed, [contains(_link)]);
    final raw = printed.single;
    expect(container.read(logsProvider).list.map((log) => log.payload), [
      contains(_link),
    ]);

    final main = File('lib/shikoo/app/main.dart').readAsStringSync();
    final call = RegExp(
      r'^\s*hideLinksInLogs\(\);',
      multiLine: true,
    ).firstMatch(main)?.start;
    expect(call, isNotNull);
    expect(call, lessThan(main.indexOf('shikooDiag.start(')));
    app.hideLinksInLogs();
    FlClashHttpOverrides.findProxyForReader(container.read, Uri.parse(_link));
    final logcat = printed.last;
    expect(logcat, '[APP] find <link> proxy: false');

    final home = Directory.systemTemp.createTempSync('sub-link-logs');
    addTearDown(() => home.deleteSync(recursive: true));
    final diag = ShikooDiag()..add('A', raw);
    await diag.start(home.path);
    diag
      ..add('A', raw)
      ..release();
    final ring = File('${home.path}/shikoo/diag.log').readAsStringSync();
    final page = diag.logEntries().map((entry) => entry.line).join('\n');
    for (final (where, text) in [
      ('logcat', logcat),
      ('diag.log', ring),
      ('Logs page and report log', page),
      ('report logcat', cleanLine(raw, null)),
    ]) {
      expect(text, isNot(contains(_token)), reason: where);
      expect(text, isNot(contains('example.invalid')), reason: where);
    }
    expect(ring, contains('[APP] find'));
  });

  test("a shelf account's link, the door's bare path or resolved, leaves its "
      'token in no logcat line and no report line', () {
    const token = 'k3Vq9_Zx-2LmB7tR0pYc4WnE8sJdA1hGfU6oKiQ5yXz';
    final printed = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = print);
    app.hideLinksInLogs();
    for (final line in [
      '{"id":42,"sub_url":"/api/v1/app/sub/$token","renewable":false}',
      'GET /api/v1/app/sub/$token 410',
      'DioException [bad response]: https://app.chopon.uk/api/v1/app/sub/$token',
      'FormatException: no config at (/api/v1/app/sub/$token).',
    ]) {
      debugPrint(line);
      expect(printed.last, isNot(contains(token)), reason: 'logcat: $line');
      expect(
        cleanLine(line, null),
        isNot(contains(token)),
        reason: 'diag.log and report: $line',
      );
    }
  });
}
