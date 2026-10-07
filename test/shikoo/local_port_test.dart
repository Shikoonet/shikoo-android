import 'dart:async';

import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the port password reaches the core only after its first config',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final pushed = <List<String>>[];
      container.listen(
        updateParamsProvider,
        (_, next) => pushed.add(next.authentication),
      );
      final attached = Completer<void>();

      final locking = lockLocalPortAfter(attached.future, container);
      await pumpEventQueue();
      expect(pushed, isEmpty);

      attached.complete();
      await locking;
      await pumpEventQueue();
      expect(pushed.single, hasLength(1));

      await lockLocalPortAfter(Future.value(), container);
      await pumpEventQueue();
      expect(pushed, hasLength(1));
    },
  );
}
