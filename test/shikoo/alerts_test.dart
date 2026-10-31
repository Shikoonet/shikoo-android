import 'package:fl_clash/shikoo/app/alerts.dart';
import 'package:fl_clash/shikoo/engine/clock.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

ShikooService _service({
  int id = 1,
  bool ended = false,
  bool empty = false,
  bool refused = false,
}) => ShikooService(
  id: id,
  name: 'test_user · یک‌ماهه',
  usedBytes: empty ? 100 : 10,
  totalBytes: 100,
  expire: DateTime.now().add(Duration(days: ended ? -1 : 30)),
  loginRefused: refused,
);

ShikooState _state(
  ShikooConnection connection, {
  ShikooService? service,
  String? selected = 'Germany 3',
  bool noTraffic = false,
  int? ping,
  ShikooNotice? notice,
}) => ShikooState(
  connection: connection,
  connectedFor: Duration.zero,
  isTV: false,
  servers: [
    if (selected != null)
      ShikooServer(name: selected, type: 'vless', ping: ping),
  ],
  service: service ?? _service(),
  selected: selected,
  connectedNoTraffic: noTraffic,
  notice: notice,
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
          '«\u2068test_user\u2069 ·\u00A0\u2068یک‌ماهه\u2069» تمام شد. '
          'با تمدید دوباره فعال می‌شود.',
        );
        expect(alert['tap'], 'card:1');
        expect(alert['actions'], [
          ['تمدید', 'url:${ShikooLinks.renew}'],
        ]);

        await set(_state(_off, service: _service(ended: true)));
        await set(_state(_on, service: _service(ended: true)));
        expect(posted(), ['ended'], reason: 'the same ending');

        native.clear();
        await set(_state(_on, service: _service()));
        expect(cancelled(), ['ended'], reason: 'renewed while connected');
      },
    );

    test('out of data says so in the title, and its date running out later '
        'is the same ending', () async {
      await set(_state(_on));
      await set(_state(_on, service: _service(empty: true)));
      expect(last('ended')['title'], 'حجم سرویست تمام شد');
      await set(_state(_on, service: _service(ended: true, empty: true)));
      expect(posted(), ['ended']);
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
      await set(_state(_on, service: _service(id: 3)));
      await set(_state(_on, service: _service(id: 4, ended: true)));
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

  Future<void> muted(String kind) => messenger.handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall('muted', kind)),
    (_) {},
  );

  group('1 from the state: connected with no traffic', () {
    test('posts once when it begins, and goes when traffic passes', () async {
      await set(_state(_on));
      expect(posted(), isEmpty);
      await set(_state(_on, noTraffic: true));
      expect(posted(), ['noTraffic']);
      expect(last('noTraffic')['body'], contains('Germany'));

      native.clear();
      await set(_state(_on));
      expect(cancelled(), ['noTraffic']);

      await set(_state(_on, noTraffic: true));
      expect(posted(), isEmpty, reason: 'one for each connect');
    });

    test('a failed ping alone counts, as the app\'s own card does', () async {
      await set(_state(_on, ping: -1));
      expect(posted(), ['noTraffic']);
    });

    test('a new server, or a new connect, gets its own', () async {
      await set(_state(_on, noTraffic: true));
      await set(_state(_on, selected: 'Netherlands 1', noTraffic: true));
      expect(posted(), ['noTraffic', 'noTraffic']);
      expect(last('noTraffic')['body'], contains('Netherlands'));

      await set(_state(_off, selected: 'Netherlands 1'));
      await set(_state(_on, selected: 'Netherlands 1', noTraffic: true));
      expect(posted(), hasLength(3));
    });

    test(
      'never for the streaming server, which pings with no internet',
      () async {
        await set(_state(_on, selected: '🇮🇷 فیلیمو', noTraffic: true));
        await set(_state(_on, selected: '🇮🇷 Filimo', ping: -1));
        expect(posted(), isEmpty);
      },
    );

    test(
      'none while it is only connecting, or while the app is on screen',
      () async {
        await set(_state(_connecting, noTraffic: true));
        await set(_state(_off, noTraffic: true));
        controller.foreground = true;
        await set(_state(_on, noTraffic: true));
        expect(posted(), isEmpty);
      },
    );

    test(
      '«دیگر نشان نده» stops the next one, and Settings brings it back',
      () async {
        await set(_state(_on, noTraffic: true));
        expect(last('noTraffic')['actions'], [
          ['انتخاب سرور دیگر', 'open:list'],
          ['دیگر نشان نده', 'mute'],
        ]);
        await muted('noTraffic');

        native.clear();
        await set(_state(_off));
        await set(_state(_on, noTraffic: true));
        expect(posted(), isEmpty);

        await container.read(shikooAlertNoTrafficProvider.notifier).set(true);
        await set(_state(_off));
        await set(_state(_on, noTraffic: true));
        expect(posted(), ['noTraffic']);
      },
    );

    test(
      'the switch is the key Kotlin writes, without the plugin\'s prefix',
      () async {
        SharedPreferences.setMockInitialValues({
          'shikoo.alerts.noTraffic': false,
        });
        final read = ProviderContainer();
        addTearDown(read.dispose);
        await read.read(shikooAlertNoTrafficProvider.notifier).load();
        expect(read.read(shikooAlertNoTrafficProvider), isFalse);
      },
    );
  });

  group('3 from the state: the shelf account refused', () {
    ShikooState refused({bool on = true}) => _state(
      _error,
      selected: 'Netherlands 1',
      service: _service(refused: on),
    );

    test('posts when the refusal begins, and goes when it clears', () async {
      await set(refused(on: false));
      expect(posted(), isEmpty);
      await set(refused());
      expect(posted(), ['refused']);
      final alert = last('refused');
      expect(alert['body'], contains('Netherlands'));
      expect(alert['tap'], 'card:1');
      expect(alert['actions'], [
        ['پشتیبانی', 'url:${ShikooLinks.support}'],
      ]);

      native.clear();
      await set(refused(on: false));
      expect(cancelled(), ['refused']);
    });

    test('a retry refused again the same day posts nothing more', () async {
      await set(refused());
      await set(refused(on: false));
      await set(refused());
      expect(posted(), ['refused']);
    });

    test('a day is the unit: later the same day is none, the next day is '
        'one, and the clock is the server-corrected one', () async {
      addTearDown(() => shikooSkew = Duration.zero);
      shikooSkew = DateTime(2026, 10, 15, 12).difference(DateTime.now());
      await alerts.refused('Germany 5');
      expect(posted(), ['refused']);
      shikooSkew += const Duration(hours: 3);
      await alerts.refused('Germany 5');
      expect(posted(), ['refused'], reason: 'the same day, three hours on');
      shikooSkew += const Duration(days: 1);
      await alerts.refused('Germany 5');
      expect(posted(), ['refused', 'refused'], reason: 'the next day');
    });

    test('none while the app is on screen, after the customer\'s own stop, '
        'or with no server to name', () async {
      controller.foreground = true;
      await set(refused());
      await set(refused(on: false));
      controller.foreground = false;
      controller.offByCustomer = true;
      await set(refused());
      await set(refused(on: false));
      controller.offByCustomer = false;
      await set(
        _state(_error, selected: null, service: _service(refused: true)),
      );
      expect(posted(), isEmpty);
    });
  });

  group('4 from the state: the server was removed', () {
    ShikooState gone(String server) =>
        _state(_off, selected: null, notice: SelectedGone(server));

    test('after the app\'s own disconnect, one alert names the server and '
        'the drop alert stays quiet; the next connect clears it', () async {
      await set(_state(_on));
      controller.offByCustomer = true;
      await set(gone('🇩🇪 Germany 5'));
      await settle();
      expect(posted(), ['removed']);
      expect(last('removed')['body'], contains('Germany'));
      expect(last('removed')['tap'], 'list');

      native.clear();
      await set(_state(_on, selected: 'Netherlands 1'));
      expect(cancelled(), contains('removed'));
    });

    test('once for each server removed', () async {
      await set(gone('Germany 5'));
      await set(_state(_off));
      await set(gone('Germany 5'));
      expect(posted(), ['removed']);
      await set(_state(_off));
      await set(gone('Germany 6'));
      expect(posted(), ['removed', 'removed']);
    });

    test(
      'other news after an update, and the app on screen, post nothing',
      () async {
        await set(
          _state(
            _on,
            notice: const ServersChanged(added: 0, removed: ['Germany 6']),
          ),
        );
        await set(_state(_on, notice: const RefreshFailed()));
        controller.foreground = true;
        await set(gone('Germany 5'));
        expect(posted(), isEmpty);
      },
    );
  });

  group('1 and 3: leaving the app with the problem still holding', () {
    Future<void> leave() async {
      controller.foreground = false;
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      await pumpEventQueue();
    }

    Future<void> onScreen(ShikooState state) async {
      controller.foreground = true;
      await set(state);
    }

    ShikooState refused({bool on = true, String? server = 'Netherlands 1'}) =>
        _state(
          _error,
          selected: server,
          service: _service(refused: on),
        );

    test(
      'a no-traffic that began on screen is said once when the app '
      'leaves, and a second leave in the same episode says nothing',
      () async {
        await onScreen(_state(_on, noTraffic: true));
        expect(posted(), isEmpty);
        await leave();
        expect(posted(), ['noTraffic']);
        expect(last('noTraffic')['body'], contains('Germany'));

        native.clear();
        controller.foreground = true;
        await leave();
        expect(posted(), isEmpty);
      },
    );

    test('a new connect, or a new server, is a new episode', () async {
      await onScreen(_state(_on, noTraffic: true));
      await leave();
      await onScreen(_state(_off));
      await onScreen(_state(_on, noTraffic: true));
      await leave();
      expect(posted(), ['noTraffic', 'noTraffic'], reason: 'a new connect');

      await onScreen(_state(_on, selected: 'Netherlands 1', noTraffic: true));
      await leave();
      expect(posted(), hasLength(3), reason: 'a new server');
      expect(last('noTraffic')['body'], contains('Netherlands'));
    });

    test('nothing once the problem has cleared, or while only connecting, '
        'and only the step of leaving counts', () async {
      await onScreen(_state(_on, noTraffic: true));
      await onScreen(_state(_on));
      await leave();
      await onScreen(_state(_connecting, noTraffic: true));
      await leave();
      await onScreen(_state(_on, noTraffic: true));
      controller.foreground = false;
      for (final step in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.resumed,
      ]) {
        WidgetsBinding.instance.handleAppLifecycleStateChanged(step);
      }
      await pumpEventQueue();
      expect(posted(), isEmpty);
    });

    test(
      '«دیگر نشان نده» is respected, until Settings turns it back on',
      () async {
        await container.read(shikooAlertNoTrafficProvider.notifier).set(false);
        await onScreen(_state(_on, noTraffic: true));
        await leave();
        expect(posted(), isEmpty);
        await container.read(shikooAlertNoTrafficProvider.notifier).set(true);
        await leave();
        expect(posted(), ['noTraffic']);
      },
    );

    test('never for the streaming server', () async {
      await onScreen(_state(_on, selected: '🇮🇷 Filimo', noTraffic: true));
      await onScreen(_state(_on, selected: '🇮🇷 فیلیمو', ping: -1));
      await leave();
      expect(posted(), isEmpty);
    });

    test('a refusal that began on screen is said once when the app leaves, '
        'and not again the same day', () async {
      await onScreen(refused());
      expect(posted(), isEmpty);
      await leave();
      expect(posted(), ['refused']);
      expect(last('refused')['tap'], 'card:1');

      controller.foreground = true;
      await leave();
      await onScreen(refused(on: false));
      await onScreen(refused());
      await leave();
      expect(posted(), ['refused'], reason: 'the same refusal, the same day');

      alerts = build();
      await onScreen(refused());
      await leave();
      expect(posted(), ['refused'], reason: 'a new start, the same day');
    });

    test('no refusal alert while the account is fine, or with no server to '
        'name', () async {
      await onScreen(refused(on: false));
      await leave();
      await onScreen(refused(server: null));
      await leave();
      expect(posted(), isEmpty);
    });
  });

  test('English names the account and server alerts', () async {
    await container.read(shikooLookProvider.notifier).setLanguage('en');
    await set(
      _state(
        _error,
        selected: 'Netherlands 1',
        service: _service(refused: true),
      ),
    );
    expect(last('refused')['title'], 'Your account was refused');
    expect(
      last('refused')['body'],
      '“\u2068Netherlands\u00A01\u2069” didn’t accept your username and password. Message support.',
    );
    expect(last('refused')['actions'], [
      ['Support', 'url:${ShikooLinks.support}'],
    ]);

    await set(
      _state(_off, selected: null, notice: const SelectedGone('Germany 5')),
    );
    expect(last('removed')['title'], 'Your server was removed');
    expect(last('removed')['actions'], [
      ['Pick a server', 'open:list'],
    ]);
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
