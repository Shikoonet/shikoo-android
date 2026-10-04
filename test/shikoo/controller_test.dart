import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriveConnection', () {
    test('connecting wins until native confirms', () {
      expect(
        deriveConnection(connecting: true, running: true, error: null),
        ShikooConnection.connecting,
      );
    });

    test('a running tunnel is on, even after an old error', () {
      expect(
        deriveConnection(
          connecting: false,
          running: true,
          error: ShikooError.connectTimeout,
        ),
        ShikooConnection.on,
      );
    });

    test('only a connect timeout is a connection error', () {
      expect(
        deriveConnection(
          connecting: false,
          running: false,
          error: ShikooError.connectTimeout,
        ),
        ShikooConnection.error,
      );
      expect(
        deriveConnection(
          connecting: false,
          running: false,
          error: ShikooError.serverChange,
        ),
        ShikooConnection.off,
      );
    });
  });

  group('waitForTunnel', () {
    const tick = Duration(milliseconds: 1);

    test('returns true once native reports a run time', () async {
      var calls = 0;
      final up = await waitForTunnel(
        () async => ++calls < 3 ? null : DateTime(2026),
        timeout: const Duration(seconds: 5),
        stillWanted: () => true,
        every: tick,
      );
      expect(up, isNotNull);
      expect(calls, 3);
    });

    test('gives up after the timeout, as when consent is refused', () async {
      final up = await waitForTunnel(
        () async => null,
        timeout: const Duration(milliseconds: 30),
        stillWanted: () => true,
        every: tick,
      );
      expect(up, isNull);
    });

    test('time under the consent dialog does not count', () async {
      var calls = 0;
      final up = await waitForTunnel(
        () async => ++calls < 52 ? null : DateTime(2026),
        timeout: const Duration(milliseconds: 200),
        stillWanted: () => true,
        paused: () => calls < 50,
        every: const Duration(milliseconds: 5),
      );
      expect(up, isNotNull, reason: 'a late OK still connects');
    });

    test('stops at once when the user cancels', () async {
      var calls = 0;
      final up = await waitForTunnel(
        () async {
          calls++;
          return null;
        },
        timeout: const Duration(seconds: 5),
        stillWanted: () => calls < 2,
        every: tick,
      );
      expect(up, isNull);
      expect(calls, 2);
    });
  });

  test('a name another service has gets a Persian number, never "(1)"', () {
    expect(unusedName('user123 · الماس', {}), 'user123 · الماس');
    expect(
      unusedName('user123 · الماس', {'user123 · الماس'}),
      'user123 · الماس ۲',
    );
    final taken = {'a', for (var n = 2; n < 10; n++) 'a ${'۰۱۲۳۴۵۶۷۸۹'[n]}'};
    expect(unusedName('a', taken), 'a ۱۰');
  });

  test('a link with a known username is that service\'s new link', () {
    final a = Profile.normal(
      url: 'https://s.4g3.uk/sub/old',
    ).copyWith(label: 'user123 · الماس');
    final b = Profile.normal(
      url: 'https://s.4g3.uk/sub/b',
    ).copyWith(label: 'user789 · معمولی');
    final profiles = [a, b];
    expect(
      serviceOf(profiles, 'https://s.4g3.uk/sub/new', 'user123 · الماس'),
      a,
    );
    expect(
      serviceOf(profiles, 'https://s.4g3.uk/sub/new', 'user123 · طلایی'),
      a,
      reason: 'the tier changed, the username did not',
    );
    expect(serviceOf(profiles, 'https://S.4g3.uk/sub/b/', null), b);
    expect(
      serviceOf(profiles, 'https://s.4g3.uk/sub/c', 'user456 · طلایی'),
      isNull,
    );
  });
}
