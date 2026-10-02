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
      expect(up, isTrue);
      expect(calls, 3);
    });

    test('gives up after the timeout, as when consent is refused', () async {
      final up = await waitForTunnel(
        () async => null,
        timeout: const Duration(milliseconds: 30),
        stillWanted: () => true,
        every: tick,
      );
      expect(up, isFalse);
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
      expect(up, isFalse);
      expect(calls, 2);
    });
  });
}
