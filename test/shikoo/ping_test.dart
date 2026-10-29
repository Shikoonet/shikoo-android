import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/ping.dart';
import 'package:flutter_test/flutter_test.dart';

const _version = 'V3.7.x 🆔 info';
const _panel = [_version, 'آلمان ۲', 'هلند ۱', 'انگلیس', 'آمریکا ۲'];

bool _whole(String name) => false;

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

  test('the app picks a usage-multiplier server only when no other answered '
      '(#29)', () {
    const panel = ['NL 3 x ضریب مصرف', 'ضریب مصرف FR 4 x', 'Germany 3'];
    final pings = {panel[0]: 60, panel[1]: 70, panel[2]: 113};
    expect(fastest(panel, (n) => pings[n], handshake: _whole), 'Germany 3');
    pings['Germany 3'] = -1;
    expect(
      fastest(panel, (n) => pings[n], handshake: _whole),
      'NL 3 x ضریب مصرف',
    );
  });

  group('an OpenVPN reset, one round trip, never beats a whole test (Sam, '
      '2026-10-29)', () {
    bool reset(String name) => name.startsWith('OV');
    String? pick(Map<String, int> pings) =>
        fastest([...pings.keys], (n) => pings[n], handshake: reset);

    test('a mixed service: the slower VLESS', () {
      expect(pick(const {'OV ۱': 4, 'OV ۲': 9, 'VLESS ۱': 150}), 'VLESS ۱');
    });

    test('OpenVPN alone: its fastest reset', () {
      expect(pick(const {'OV ۱': 40, 'OV ۲': 9, 'OV ۳': -1}), 'OV ۲');
    });

    test('every other server silent: the OpenVPN', () {
      expect(pick(const {'OV ۱': 12, 'VLESS ۱': -1, 'WG ۱': -1}), 'OV ۱');
    });

    test('an ordinary reset before a usage multiplier, even a faster one '
        '(#29; Sam: no multiplier first)', () {
      expect(pick(const {'OV ۱': 12, 'VLESS ضریب مصرف 4 x': 90}), 'OV ۱');
      expect(pick(const {'OV ۱': 120, 'VLESS ضریب مصرف 4 x': 60}), 'OV ۱');
    });

    test('connect pressed: a reset answers first, yet is taken only once the '
        'round has ended with no whole test', () {
      String? connecting(Map<String, int> pings, {required bool pinging}) =>
          pickNow(
            names: [...pings.keys],
            ping: (n) => pings[n],
            pinging: pinging,
            urgent: true,
            handshake: reset,
          );
      expect(connecting(const {'OV ۱': 4}, pinging: true), isNull);
      expect(
        connecting(const {'OV ۱': 4, 'VLESS ۱': 150}, pinging: true),
        'VLESS ۱',
      );
      expect(connecting(const {'OV ۱': 4}, pinging: false), 'OV ۱');
    });
  });

  test('a usage multiplier is known wherever «ضریب» stands in the name, and '
      'with either yeh (#29)', () {
    for (final name in [
      'ضریب مصرف NE 4 x',
      'NL 3 x ضریب مصرف',
      '🇩🇪 آلمان ۴ x ضریب مصرف',
      'ضر\u064Aب مصرف FR 4 x',
    ]) {
      expect(multiplied(name), isTrue, reason: name);
    }
    for (final name in [
      'Germany 3',
      'Germany همراه',
      'Italy (Gemini+YouTube بدون تبلیغ)',
    ]) {
      expect(multiplied(name), isFalse, reason: name);
    }
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
  });

  test("the panel's info rows are not servers", () {
    for (final row in [
      'V3.7.9 🆔 : (user123) 📊 (50 GB) ⏰ (30)',
      'قبل از اتصال به هر سرور یکبار به روز رسانی کنید',
    ]) {
      expect(isServer('Vless', row), isFalse, reason: row);
    }
  });

  test('groups are not servers', () {
    for (final group in [
      'Selector',
      'URLTest',
      'Fallback',
      'LoadBalance',
      'Relay',
    ]) {
      expect(isServer(group, '⚡ Fastest'), isFalse, reason: group);
    }
    expect(isServer('Direct', 'DIRECT'), isFalse);
    for (final server in ['Vless', 'WireGuard', 'Http']) {
      expect(isServer(server, '🇩🇪 آلمان ۲'), isTrue, reason: server);
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
      handshake: _whole,
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

    test('connect pressed: a usage-multiplier first answer is taken at once; '
        'an ordinary server that answered too wins (#29)', () {
      const four = 'ضریب مصرف NE 4 x';
      String? connecting(Map<String, int> pings) => pickNow(
        names: const [four, 'هلند ۱'],
        ping: (n) => pings[n],
        pinging: true,
        urgent: true,
        handshake: _whole,
      );
      expect(connecting(const {four: 60}), four, reason: 'connect never waits');
      expect(connecting(const {four: 60, 'هلند ۱': 90}), 'هلند ۱');
    });
  });

  test('the pill rests on «picked automatically»; it spins only while connect '
      'waits, and says none answered once a ping or a connect found none', () {
    ShikooPick p({
      bool selected = false,
      bool waiting = false,
      bool noAnswer = false,
    }) => derivePick(selected: selected, waiting: waiting, noAnswer: noAnswer);
    expect(p(), ShikooPick.auto, reason: 'nothing runs before Connect or Ping');
    expect(p(selected: true), ShikooPick.server);
    expect(p(selected: true, waiting: true), ShikooPick.server);
    expect(p(waiting: true), ShikooPick.finding);
    expect(p(noAnswer: true), ShikooPick.none);
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
