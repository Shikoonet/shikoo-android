import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:flutter_test/flutter_test.dart';

const _version = 'V3.7.x 🆔 info';
const _panel = [_version, 'آلمان ۲', 'هلند ۱', 'انگلیس', 'آمریکا ۲'];

void main() {
  group('pingServers', () {
    test('never runs more than four at once', () async {
      var running = 0;
      var most = 0;
      final names = [for (var i = 0; i < 20; i++) 's$i'];
      await pingServers(names, (name) async {
        most = running + 1 > most ? running + 1 : most;
        running++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        return 50;
      }, (_, _) {});
      expect(most, pingConcurrency);
    });

    test(
      'a failure is tested again and reported only after the second',
      () async {
        final calls = <String, int>{};
        final results = <String, int>{};
        final reported = <String>[];
        await pingServers(
          ['ok', 'once', 'dead', 'silent'],
          (name) async {
            final n = calls[name] = (calls[name] ?? 0) + 1;
            return switch (name) {
              'ok' => 80,
              'once' => n == 1 ? -1 : 120,
              'dead' => -1,
              _ => null,
            };
          },
          (name, ms) {
            results[name] = ms;
            reported.add(name);
          },
        );
        expect(calls, {'ok': 1, 'once': 2, 'dead': 2, 'silent': 2});
        expect(results, {'ok': 80, 'once': 120, 'dead': -1, 'silent': -1});
        expect(reported.toSet(), hasLength(4), reason: 'one verdict each');
      },
    );

    test('second tests wait until every first one is done', () async {
      final order = <String>[];
      await pingServers(
        ['dead', 'a', 'b'],
        (name) async {
          order.add(name);
          return name == 'dead' ? -1 : 50;
        },
        (_, _) {},
        concurrency: 1,
      );
      expect(order, ['dead', 'a', 'b', 'dead']);
    });
  });

  group('sortByPing', () {
    test('fastest first; no answer and untested last, in panel order', () {
      final pings = {'a': -1, 'b': 120, 'd': 80, 'e': 120};
      expect(sortByPing(['a', 'b', 'c', 'd', 'e'], (n) => pings[n]), [
        'd',
        'b',
        'e',
        'a',
        'c',
      ]);
    });

    test('a 4x-usage server sorts by its ping like any other', () {
      final pings = {'🇩🇪 آلمان ۴ x ضریب مصرف': 60, 'هلند ۱': 90};
      expect(
        sortByPing(['هلند ۱', '🇩🇪 آلمان ۴ x ضریب مصرف'], (n) => pings[n]),
        ['🇩🇪 آلمان ۴ x ضریب مصرف', 'هلند ۱'],
      );
    });
  });

  test('keepOrder keeps the sorted order and appends new servers', () {
    expect(keepOrder(['c', 'a', 'b'], ['a', 'b', 'c', 'd']), [
      'c',
      'a',
      'b',
      'd',
    ]);
    expect(keepOrder(['c', 'gone', 'a'], ['a', 'c']), ['c', 'a']);
    expect(keepOrder(const [], ['x', 'y']), ['x', 'y']);
  });

  test('isDue: never run, or the interval has passed', () {
    final now = DateTime(2026, 10, 3, 12);
    expect(isDue(null, now, refreshEvery), isTrue);
    expect(
      isDue(now.subtract(const Duration(minutes: 9)), now, refreshEvery),
      isFalse,
    );
    expect(
      isDue(now.subtract(const Duration(minutes: 10)), now, refreshEvery),
      isTrue,
    );
    expect(
      isDue(now.subtract(const Duration(minutes: 1)), now, pingEvery),
      isFalse,
    );
    expect(
      isDue(now.subtract(const Duration(minutes: 3)), now, pingEvery),
      isTrue,
    );
  });

  test('groups are not servers', () {
    for (final group in [
      'Selector',
      'URLTest',
      'Fallback',
      'LoadBalance',
      'Relay',
    ]) {
      expect(isServer(group), isFalse, reason: group);
    }
    expect(isServer('Direct'), isFalse);
    for (final server in ['Vless', 'WireGuard', 'Http']) {
      expect(isServer(server), isTrue, reason: server);
    }
  });

  group('never connects blind to the first row', () {
    String? pick(
      Map<String, int> pings, {
      required bool pinging,
      required bool urgent,
    }) => pickNow(
      names: _panel,
      ping: (n) => pings[n],
      pinging: pinging,
      urgent: urgent,
    );

    test(
      'first install, or the selected server removed: wait for the round',
      () {
        expect(pick(const {}, pinging: true, urgent: false), isNull);
        expect(
          pick(const {'هلند ۱': 90}, pinging: true, urgent: false),
          isNull,
          reason: 'not connected: the fastest is chosen when the round ends',
        );
        expect(
          pick(
            const {_version: -1, 'آلمان ۲': 140, 'هلند ۱': 90, 'انگلیس': -1},
            pinging: false,
            urgent: false,
          ),
          'هلند ۱',
        );
      },
    );

    test(
      'connected when the selected server was removed: the fastest at once',
      () {
        expect(
          pick(
            const {'آلمان ۲': 140, 'آمریکا ۲': 75},
            pinging: true,
            urgent: true,
          ),
          'آمریکا ۲',
        );
      },
    );

    test(
      'app run again while connected, no pings yet: the first that answers',
      () {
        expect(pick(const {}, pinging: true, urgent: true), isNull);
        expect(
          pick(
            const {_version: -1, 'انگلیس': 210},
            pinging: true,
            urgent: true,
          ),
          'انگلیس',
        );
      },
    );

    test('every server silent: nothing, never the first row', () {
      final silent = {for (final name in _panel) name: -1};
      expect(pick(silent, pinging: false, urgent: true), isNull);
      expect(pick(silent, pinging: false, urgent: false), isNull);
    });
  });

  test('the pill finds, then names the server or says none answered', () {
    ShikooPick p({
      bool selected = false,
      bool pinging = false,
      bool roundEnded = true,
      bool anyAnswer = false,
    }) => derivePick(
      selected: selected,
      pinging: pinging,
      roundEnded: roundEnded,
      anyAnswer: anyAnswer,
    );
    expect(p(selected: true), ShikooPick.server);
    expect(p(roundEnded: false), ShikooPick.finding);
    expect(p(pinging: true), ShikooPick.finding);
    expect(p(anyAnswer: true), ShikooPick.finding);
    expect(p(), ShikooPick.none);
  });

  test('connect pressed and nobody answered is an error', () {
    expect(
      deriveConnection(
        connecting: false,
        running: false,
        error: ShikooError.noServer,
      ),
      ShikooConnection.error,
    );
  });
}
