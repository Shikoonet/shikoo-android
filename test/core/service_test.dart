import 'dart:async';

import 'package:fl_clash/core/desktop/helper_client.dart';
import 'package:fl_clash/core/desktop/lifecycle.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/core/desktop/rpc_client.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/core/service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';

import 'desktop/fakes.dart';

final class _MockLifecycle extends Mock
    implements DesktopCoreLifecycleController {}

final class _MockRpcClient extends Mock implements CoreRpcChannel {}

void main() {
  late _MockLifecycle lifecycle;
  late _MockRpcClient rpcClient;
  late StreamController<DesktopCoreFailure> crashes;
  late CoreService service;

  const result = CoreLifecycleResult(
    revision: 1,
    outcome: CoreLifecycleOutcome.applied,
  );

  setUp(() {
    lifecycle = _MockLifecycle();
    rpcClient = _MockRpcClient();
    crashes = StreamController<DesktopCoreFailure>.broadcast();
    when(() => lifecycle.crashEvents).thenAnswer((_) => crashes.stream);
    when(() => lifecycle.start()).thenAnswer((_) async => result);
    when(() => lifecycle.restart()).thenAnswer((_) async => result);
    when(() => lifecycle.stop()).thenAnswer((_) async => result);
    when(() => lifecycle.close()).thenAnswer((_) async => result);
    when(() => rpcClient.close()).thenAnswer((_) async {});
    service = CoreService.forTesting(
      lifecycle: lifecycle,
      rpcClient: rpcClient,
    );
  });

  tearDown(() async {
    await service.close();
    await crashes.close();
  });

  test(
    'delegates lifecycle commands without owning platform details',
    () async {
      expect(await service.start(), same(result));
      expect(await service.restart(), same(result));
      expect(await service.stop(), same(result));

      verify(() => lifecycle.start()).called(1);
      verify(() => lifecycle.restart()).called(1);
      verify(() => lifecycle.stop()).called(1);
    },
  );

  test('delegates Core method calls to the RPC channel', () async {
    when(
      () => rpcClient.invoke<bool>(
        method: CoreMethod.getIsInit,
        arguments: null,
        timeout: null,
      ),
    ).thenAnswer((_) async => true);

    expect(
      await service.invokeMethod<bool>(method: CoreMethod.getIsInit),
      isTrue,
    );
  });

  test('forwards lifecycle crash events once', () async {
    final listener = _CrashListener();
    coreEventManager.addListener(listener);

    crashes.add(
      const DesktopCoreFailure(
        code: 'unexpected_disconnect',
        phase: DesktopCorePhase.running,
        revision: 2,
      ),
    );
    await pumpEventQueue();

    expect(listener.messages, ['core done']);
    coreEventManager.removeListener(listener);
  });

  test('close coalesces lifecycle and RPC cleanup', () async {
    final first = service.close();
    final second = service.close();

    expect(await first, same(result));
    expect(await second, same(result));
    verify(() => lifecycle.close()).called(1);
    verify(() => rpcClient.close()).called(1);
  });

  test("a Core started while the Helper does not answer stays the App's "
      'until a restart, which the Helper takes once it answers', () async {
    final transport = FakeDesktopCoreTransport();
    final direct = FakeLauncher(owner: CoreProcessOwner.direct, pid: 42);
    final helper = FakeLauncher(owner: CoreProcessOwner.helper, pid: 84);
    var answers = HelperReadiness.notReady;
    final owned = CoreService.forTesting(
      lifecycle: DesktopCoreLifecycle(
        transportFactory: () => transport,
        launcherResolver: HelperLauncherResolver(
          hasHelper: true,
          directLauncher: direct,
          helperLauncher: helper,
          helperReady: () async => answers,
        ),
        sessionIdFactory: () => '0123456789abcdef0123456789abcdef',
        verifyPeerPid: true,
      ),
      rpcClient: rpcClient,
    );
    expect(owned.owner, isNull);

    final start = owned.start();
    transport.ready();
    await direct.started;
    transport.connect(pid: 42, generation: 1);
    await start;
    expect(owned.owner, CoreProcessOwner.direct);

    answers = HelperReadiness.ready;
    expect(await owned.start(), isNotNull);
    expect(owned.owner, CoreProcessOwner.direct, reason: 'a live Core stays');

    final restart = owned.restart();
    await direct.lease.stopStarted;
    transport.disconnect(1);
    await helper.started;
    transport.connect(pid: 84, generation: 2);
    await restart;
    expect(owned.owner, CoreProcessOwner.helper);

    final close = owned.close();
    await helper.lease.stopStarted;
    transport.disconnect(2);
    await close;
    expect(owned.owner, isNull);
  });
}

final class _CrashListener with CoreEventListener {
  final List<String> messages = [];

  @override
  void onCrash(String message) {
    messages.add(message);
  }
}
