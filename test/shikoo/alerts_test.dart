import 'package:fl_clash/shikoo/app/alerts.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Controller extends Mock implements ShikooController {
  @override
  bool foreground = false;

  @override
  bool offByCustomer = false;

  final opened = <int?>[];

  @override
  void openService(int? id) => opened.add(id);
}

const _channel = MethodChannel('shikoo/alerts');
const _on = ShikooConnection.on;
const _off = ShikooConnection.off;
const _connecting = ShikooConnection.connecting;
const _error = ShikooConnection.error;

ShikooService _service({int id = 1, bool ended = false, bool empty = false}) =>
    ShikooService(
      id: id,
      name: 'test_user · یک‌ماهه',
      usedBytes: empty ? 100 : 10,
      totalBytes: 100,
      expire: DateTime.now().add(Duration(days: ended ? -1 : 30)),
    );

ShikooState _state(
  ShikooConnection connection, {
  ShikooService? service,
  String? selected = 'Germany 3',
}) => ShikooState(
  connection: connection,
  connectedFor: Duration.zero,
  isTV: false,
  servers: const [],
  service: service ?? _service(),
  selected: selected,
);

final _fake = NotifierProvider<ShikooCell<ShikooState>, ShikooState>(
  () => ShikooCell(_state(_off)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _Controller controller;
  late ShikooAlerts alerts;
  late List<MethodCall> native;
  late bool shown;

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  List<String> posted() => [
    for (final call in native)
      if (call.method == 'post') (call.arguments as Map)['kind'] as String,
  ];

  List<String> cancelled() => [
    for (final call in native)
      if (call.method == 'cancel') call.arguments as String,
  ];

  Map<Object?, Object?> last(String kind) =>
      native
              .lastWhere(
                (c) =>
                    c.method == 'post' && (c.arguments as Map)['kind'] == kind,
              )
              .arguments
          as Map;

  ShikooAlerts build({ShikooState? initial}) {
    container = ProviderContainer(
      overrides: [
        if (initial != null) _fake.overrideWith(() => ShikooCell(initial)),
        shikooStateProvider.overrideWith((ref) => ref.watch(_fake)),
        shikooControllerProvider.overrideWithValue(controller),
      ],
    );
    addTearDown(container.dispose);
    return container.read(shikooAlertsProvider);
  }

  Future<void> set(ShikooState state) async {
    container.read(_fake.notifier).set(state);
    container.read(shikooStateProvider);
    await pumpEventQueue();
  }

  /// Lets [alertSettle] run out.
  Future<void> settle() async {
    await Future<void>.delayed(alertSettle * 2);
    await pumpEventQueue();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    alertSettle = const Duration(milliseconds: 20);
    controller = _Controller();
    native = [];
    shown = true;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      native.add(call);
      return switch (call.method) {
        'target' => null,
        _ => shown,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    alerts = build();
  });

  group('2: the VPN stopped on its own', () {
    test(
      'a drop heads up once, Home on tap, «وصل دوباره» and «دیگر نشان نده», and '
      'goes on the next connect',
      () async {
        await set(_state(_on));
        await set(_state(_off));
        expect(posted(), isEmpty, reason: 'not before it settles');
        await settle();
        expect(posted(), ['dropped']);
        final alert = last('dropped');
        expect(alert['title'], 'شیکونت قطع شد');
        expect(
          alert['body'],
          'اتصال خودبه‌خود قطع شد. اینترنتت الان مستقیم است، نه از راه شیکونت.',
        );
        expect(alert['tap'], 'home');
        expect(alert['channel'], 'هشدارهای اتصال');
        expect(alert['actions'], [
          ['وصل دوباره', 'start'],
          ['دیگر نشان نده', 'mute'],
        ]);

        await set(_state(_error));
        await settle();
        expect(posted(), ['dropped'], reason: 'once per drop');

        native.clear();
        await set(_state(_on));
        expect(cancelled(), contains('dropped'));
      },
    );

    test('made after the tunnel came up, it still sees the drop', () async {
      alerts = build(initial: _state(_on));
      await set(_state(_off));
      await settle();
      expect(posted(), ['dropped']);
    });

    test(
      'a switch of server or core, a stop and a start, is no drop',
      () async {
        await set(_state(_on));
        await set(_state(_off));
        await set(_state(_connecting));
        await set(_state(_on));
        await settle();
        expect(posted(), isEmpty);
      },
    );

    test('a switch whose start fails is a drop', () async {
      await set(_state(_on));
      await set(_state(_off));
      await set(_state(_connecting));
      await settle();
      expect(posted(), isEmpty, reason: 'still trying');
      await set(_state(_error));
      await settle();
      expect(posted(), ['dropped']);
    });

    test('a connect that never came up is no drop', () async {
      await set(_state(_connecting));
      await set(_state(_error));
      await settle();
      expect(posted(), isEmpty);
    });

    test('none after the customer\'s own stop, from the app or the VPN '
        'notification and tile', () async {
      await set(_state(_on));
      controller.offByCustomer = true;
      await set(_state(_off));
      await settle();
      expect(posted(), isEmpty);

      alerts.onStart();
      expect(controller.offByCustomer, isFalse);
      await set(_state(_on));
      alerts.onStop();
      expect(controller.offByCustomer, isTrue);
      await set(_state(_off));
      await settle();
      expect(posted(), isEmpty);
    });

    test('none while the app is on screen', () async {
      controller.foreground = true;
      await set(_state(_on));
      await set(_state(_off));
      await settle();
      expect(posted(), isEmpty);
    });

    test('none once «دیگر نشان نده» turned it off', () async {
      await container.read(shikooAlertDroppedProvider.notifier).set(false);
      await set(_state(_on));
      await set(_state(_off));
      await settle();
      expect(posted(), isEmpty);
    });

    test(
      'Kotlin holds the revoke\'s alert, in the language of the moment',
      () async {
        await alerts.start();
        Map<Object?, Object?> revoked() =>
            native.lastWhere((c) => c.method == 'revokedAlert').arguments
                as Map;
        expect(revoked()['kind'], 'dropped');
        expect(
          revoked()['body'],
          'برنامهٔ دیگری اتصال را گرفت و شیکونت قطع شد.',
        );
        await container.read(shikooLookProvider.notifier).setLanguage('en');
        await pumpEventQueue();
        expect(revoked()['title'], 'ShikooNet disconnected');
        expect(
          revoked()['body'],
          'Another app took over the connection, so ShikooNet stopped.',
        );
        expect(revoked()['channel'], 'Connection alerts');
      },
    );
  });

  group('3: the service ended', () {
    test(
      'once per ending, with the card on tap and «تمدید» to the bot',
      () async {
        await set(_state(_on));
        await set(_state(_on, service: _service(ended: true)));
        expect(posted(), ['ended']);
        final alert = last('ended');
        expect(alert['title'], 'اعتبار سرویست تمام شد');
        expect(
          alert['body'],
          '«\u2068test_user\u2069 ·\u00A0\u2068یک‌ماهه\u2069» تمام شد و اتصال قطع شد. '
          'با تمدید دوباره فعال می‌شود.',
        );
        expect(alert['tap'], 'card:1');
        expect(alert['actions'], [
          ['تمدید', 'url:${ShikooLinks.renew}'],
        ]);

        await set(_state(_on, service: _service(ended: true, empty: true)));
        await set(_state(_off, service: _service(ended: true)));
        expect(posted(), ['ended'], reason: 'the same ending');

        native.clear();
        await set(_state(_on, service: _service()));
        expect(cancelled(), contains('ended'), reason: 'renewed');
      },
    );

    test('out of data says so in the title', () async {
      await set(_state(_on));
      await set(_state(_on, service: _service(empty: true)));
      expect(last('ended')['title'], 'حجم سرویست تمام شد');
    });

    test('a connect with another service clears it; one with the ended '
        'service keeps it', () async {
      await set(_state(_on));
      await set(_state(_on, service: _service(ended: true)));
      native.clear();
      await set(_state(_off, service: _service(ended: true)));
      await set(_state(_on, service: _service(ended: true)));
      expect(cancelled(), isNot(contains('ended')));
      await set(_state(_off, service: _service(id: 2)));
      await set(_state(_on, service: _service(id: 2)));
      expect(cancelled(), contains('ended'));
    });

    test('none without a tunnel, for a service ended before, or for another '
        'service', () async {
      await set(_state(_off, service: _service(ended: true)));
      await set(_state(_on, service: _service(ended: true)));
      await set(_state(_on, service: _service(id: 2, ended: true)));
      expect(posted(), isEmpty);
    });
  });

  group('1: connected, but no internet', () {
    test('once per connect or server picked; gone when traffic passes, or '
        'with a switch or a stop', () async {
      await set(_state(_on));
      await alerts.noTraffic('🇩🇪 Germany 3');
      await alerts.noTraffic('🇩🇪 Germany 3');
      expect(posted(), ['noTraffic']);
      final alert = last('noTraffic');
      expect(alert['title'], 'وصل، ولی اینترنت رد نمی‌شود');
      expect(
        alert['body'],
        'از «\u2068Germany\u00A03\u2069» هیچ سایتی باز نشد. یک سرور دیگر انتخاب کن.',
      );
      expect(alert['tap'], 'list');
      expect(alert['actions'], [
        ['انتخاب سرور دیگر', 'open:list'],
        ['دیگر نشان نده', 'mute'],
      ]);

      native.clear();
      alerts.trafficPassed();
      expect(cancelled(), ['noTraffic']);

      native.clear();
      await set(_state(_on, selected: 'Netherlands 1'));
      expect(cancelled(), ['noTraffic'], reason: 'the customer switched');
      await alerts.noTraffic('Netherlands 1');
      expect(posted(), ['noTraffic']);

      native.clear();
      await set(_state(_off, selected: 'Netherlands 1'));
      expect(cancelled(), contains('noTraffic'));
      await set(_state(_on, selected: 'Netherlands 1'));
      await alerts.noTraffic('Netherlands 1');
      expect(posted(), ['noTraffic'], reason: 'a new connect');
    });

    test(
      'one not shown, in the app or with notifications off, may come later',
      () async {
        await set(_state(_on));
        controller.foreground = true;
        await alerts.noTraffic('Germany 3');
        controller.foreground = false;
        shown = false;
        await alerts.noTraffic('Germany 3');
        shown = true;
        await alerts.noTraffic('Germany 3');
        expect(posted(), ['noTraffic', 'noTraffic']);
      },
    );

    test('none once «دیگر نشان نده» turned it off, until Settings turns it '
        'back on', () async {
      await set(_state(_on));
      await messenger.handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(const MethodCall('muted', 'noTraffic')),
        (_) {},
      );
      expect(container.read(shikooAlertNoTrafficProvider), isFalse);
      expect(container.read(shikooAlertDroppedProvider), isTrue);
      await alerts.noTraffic('Germany 3');
      expect(posted(), isEmpty);
      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      await reloaded.read(shikooAlertNoTrafficProvider.notifier).load();
      expect(reloaded.read(shikooAlertNoTrafficProvider), isFalse);

      await container.read(shikooAlertNoTrafficProvider.notifier).set(true);
      await alerts.noTraffic('Germany 3');
      expect(posted(), ['noTraffic']);
    });
  });

  group('3: the account refused', () {
    test(
      'at most once a day for each server, across starts, with «پشتیبانی»',
      () async {
        await set(_state(_on));
        await alerts.refused('🇳🇱 Netherlands 1');
        await alerts.refused('🇳🇱 Netherlands 1');
        expect(posted(), ['refused']);
        final alert = last('refused');
        expect(alert['title'], 'حسابت پذیرفته نشد');
        expect(alert['tap'], 'card:1');
        expect(alert['actions'], [
          ['پشتیبانی', 'url:${ShikooLinks.support}'],
        ]);

        alerts = build();
        await set(_state(_on));
        await alerts.refused('🇳🇱 Netherlands 1');
        expect(posted(), ['refused'], reason: 'the same day, a new start');
        await alerts.refused('Germany 5');
        expect(posted(), ['refused', 'refused']);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'shikoo.alerts.refused',
          '{"🇳🇱 Netherlands 1": "2026-01-01"}',
        );
        await alerts.refused('🇳🇱 Netherlands 1');
        expect(posted(), hasLength(3), reason: 'another day');

        native.clear();
        await set(_state(_off));
        await set(_state(_on));
        expect(cancelled(), contains('refused'));
      },
    );
  });

  group('4: the server was removed', () {
    test('once for each server, gone with the next connect', () async {
      await set(_state(_on));
      await alerts.removed('🇩🇪 Germany 5');
      await alerts.removed('🇩🇪 Germany 5');
      expect(posted(), ['removed']);
      expect(last('removed')['tap'], 'list');
      expect(last('removed')['actions'], [
        ['انتخاب سرور', 'open:list'],
      ]);
      await alerts.removed('Germany 6');
      expect(posted(), ['removed', 'removed']);

      native.clear();
      await set(_state(_off));
      await set(_state(_on));
      expect(cancelled(), contains('removed'));
    });
  });

  test('English names the same things', () async {
    await container.read(shikooLookProvider.notifier).setLanguage('en');
    await set(_state(_on));
    await alerts.noTraffic('Germany 3');
    expect(last('noTraffic')['title'], 'Connected, but no internet');
    expect(
      last('noTraffic')['body'],
      'Nothing opened through “\u2068Germany\u00A03\u2069”. Pick another server.',
    );
    expect(last('noTraffic')['actions'], [
      ['Pick another server', 'open:list'],
      ['Don’t show again', 'mute'],
    ]);
  });

  test('a tap opens the card in use, a service\'s card, or Home', () async {
    for (final target in ['list', 'card:7', 'home']) {
      await messenger.handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(MethodCall('open', target)),
        (_) {},
      );
    }
    expect(controller.opened, [1, 7]);

    messenger.setMockMethodCallHandler(
      _channel,
      (call) async => call.method == 'target' ? 'card:3' : true,
    );
    await alerts.start();
    expect(controller.opened, [1, 7, 3], reason: 'tapped while no app ran');
  });
}
