import 'dart:async';

import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/shikoo/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Core extends Mock implements CoreHandlerInterface {}

void main() {
  test('the port password and the core log reach the core only after its '
      'first config, the log on every start', () async {
    final core = _Core();
    when(core.startLog).thenAnswer((_) {});
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    final pushed = <List<String>>[];
    container.listen(
      updateParamsProvider,
      (_, next) => pushed.add(next.authentication),
    );
    final attached = Completer<void>();

    final locking = afterAttach(attached.future, container);
    await pumpEventQueue();
    expect(pushed, isEmpty);
    verifyNever(core.startLog);

    attached.complete();
    await locking;
    await pumpEventQueue();
    expect(pushed.single, hasLength(1));
    verify(core.startLog).called(1);

    await afterAttach(Future.value(), container);
    await pumpEventQueue();
    expect(pushed, hasLength(1));
    verify(core.startLog).called(1);
  });
}
