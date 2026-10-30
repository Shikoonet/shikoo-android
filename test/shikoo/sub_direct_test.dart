import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/diag.dart';
import 'package:fl_clash/shikoo/engine/direct_dns.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:yaml/yaml.dart';

import '../helpers/test_profiles.dart';

class _Setup extends SetupAction {
  var applied = 0;

  @override
  Future<bool> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applied++;
    return true;
  }
}

String _tun(String host) => 'AND,((IN-TYPE,TUN),(DOMAIN,$host)),DIRECT';

void _memoryDatabase() {
  final before = database;
  database = Database(NativeDatabase.memory());
  addTearDown(() async {
    await database.close();
    database = before;
  });
}

Future<List<String>> _subscriptionRules() async => [
  for (final rule in await database.rulesDao.queryGlobalAddedRules().get())
    if (rule.id >= subscriptionDirectIds) rule.rawValue,
];

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('one rule a subscription host', () {
    setUp(_memoryDatabase);

    test('hosts of several services, a host twice and links without a host '
        'give one rule each, written once', () async {
      final urls = [
        'https://b.panel.example/sub/one',
        'https://a.panel.example:8443/sub/two?target=clash',
        'https://B.PANEL.example/sub/three',
        '',
        'not a link',
        '/sub/four',
      ];
      expect(await keepSubscriptionsDirect(urls), isTrue);
      expect(await keepSubscriptionsDirect(urls), isFalse);
      expect(await _subscriptionRules(), [
        _tun('a.panel.example'),
        _tun('b.panel.example'),
      ]);
    });

    test('a removed service and a changed link leave no rule behind, and the '
        "door's rules stay", () async {
      await keepApiDirect();
      await keepSubscriptionsDirect([
        'https://a.panel.example/sub/1',
        'https://b.panel.example/sub/2',
      ]);
      expect(
        await keepSubscriptionsDirect(['https://b.panel.example/sub/2']),
        isTrue,
      );
      expect(await _subscriptionRules(), [_tun('b.panel.example')]);
      await keepSubscriptionsDirect(['https://c.panel.example/sub/2']);
      expect(await _subscriptionRules(), [_tun('c.panel.example')]);
      await keepSubscriptionsDirect([]);
      expect(await _subscriptionRules(), isEmpty);
      expect([
        for (final rule
            in await database.rulesDao.queryGlobalAddedRules().get())
          rule.rawValue,
      ], contains('DOMAIN,app.chopon.uk,DIRECT'));
    });

    test(
      'an address for a host matches that address alone, v4 or v6',
      () async {
        await keepSubscriptionsDirect([
          'http://10.0.2.2:18089/sub',
          'http://[2001:db8::1]:8080/sub',
        ]);
        expect(
          await _subscriptionRules(),
          unorderedEquals([
            'AND,((IN-TYPE,TUN),(IP-CIDR,10.0.2.2/32,no-resolve)),DIRECT',
            'AND,((IN-TYPE,TUN),(IP-CIDR,2001:db8::1/128,no-resolve)),DIRECT',
          ]),
        );
      },
    );

    test('the core gets the rule ahead of the subscription, its host found '
        "with the device's DNS", () async {
      await database.profilesDao.putAll([
        const Profile(id: 1, autoUpdateDuration: Duration.zero).toCompanion(),
      ]);
      await keepSubscriptionsDirect([
        'https://a.panel.example/sub/1',
        'http://10.0.2.2:18089/sub',
      ]);
      final made = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 1,
          rawConfig: {
            'dns': {
              'enable': true,
              'nameserver': ['https://1.1.1.1/dns-query#PROXY'],
            },
            'proxies': [],
            'rules': ['MATCH,PROXY'],
          },
          realPatchConfig: const PatchClashConfig(),
          overrideDns: false,
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: await database.rulesDao.queryAddedRules(1).get(),
          defaultUA: 'FlClash-Test',
        ),
      );
      final config = loadYaml(made.yaml) as YamlMap;
      final rules = config['rules'] as List;
      expect(
        rules.take(2),
        unorderedEquals([
          _tun('a.panel.example'),
          'AND,((IN-TYPE,TUN),(IP-CIDR,10.0.2.2/32,no-resolve)),DIRECT',
        ]),
      );
      expect(rules.skip(2), ['MATCH,PROXY']);
      expect((config['dns'] as YamlMap)['nameserver-policy'], {
        'a.panel.example': 'system',
      });
    });

    // core/shikoo_direct_inbound_test.go runs this shape in mihomo.
    test("the app's own inbound: loopback, this run's credentials, the "
        'subscription hosts direct and nothing else', () async {
      await keepApiDirect();
      await keepSubscriptionsDirect([
        'https://a.panel.example/sub/1',
        'http://10.0.2.2:18089/sub',
      ]);
      await openDirectInbound();
      addTearDown(() => shikooDirectAuth = null);
      final auth = shikooDirectAuth!;
      final added = await database.rulesDao.queryGlobalAddedRules().get();
      final made = await makeRealProfileTask(
        MakeRealProfileState(
          profilesPath: '/profiles',
          profileId: 1,
          rawConfig: withDirectInbound(
            {
              'proxies': [],
              'rules': ['MATCH,PROXY'],
            },
            added,
            auth,
          ),
          realPatchConfig: const PatchClashConfig(),
          overrideDns: false,
          appendSystemDns: false,
          proxyGroups: const [],
          rules: const [],
          addedRules: added,
          defaultUA: 'FlClash-Test',
        ),
      );
      final config = loadYaml(made.yaml) as YamlMap;

      expect(auth.user, hasLength(24));
      expect(auth.pass, isNot(auth.user));
      expect(
        directInboundProxy(),
        'PROXY ${auth.user}:${auth.pass}@127.0.0.1:${auth.port}',
      );
      expect(config['listeners'], [
        {
          'name': 'shikoo-direct',
          'type': 'http',
          'listen': '127.0.0.1',
          'port': '${auth.port}',
          'users': [
            {'username': auth.user, 'password': auth.pass},
          ],
          'rule': 'shikoo-direct',
        },
      ]);
      expect(
        (config['sub-rules'] as YamlMap)['shikoo-direct'],
        unorderedEquals([
          'DOMAIN,a.panel.example,DIRECT',
          'IP-CIDR,10.0.2.2/32,DIRECT,no-resolve',
          'MATCH,REJECT',
        ]),
      );
      expect(
        ((config['sub-rules'] as YamlMap)['shikoo-direct'] as List).last,
        'MATCH,REJECT',
      );
      expect(config['skip-auth-prefixes'], isEmpty);
    });
  });

  test('the rules follow the services; only while connected does a change '
      'reach the core at once', () async {
    _memoryDatabase();
    final a = Profile.normal(url: 'https://a.panel.example/sub/1');
    final b = Profile.normal(url: 'https://b.panel.example/sub/2');
    await database.profilesDao.putAll([a.toCompanion()]);
    final setup = _Setup();
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([a])),
        setupActionProvider.overrideWith(() => setup),
      ],
    );
    addTearDown(container.dispose);
    final profiles = container.read(profilesProvider.notifier) as TestProfiles;

    await followSubscriptions(container);
    expect(await _subscriptionRules(), [_tun('a.panel.example')]);
    expect(setup.applied, 0, reason: 'off, the next connect reads them');

    container.read(runTimeProvider.notifier).value = 1;
    profiles.put(b);
    await _until(() => setup.applied == 1);
    expect(await _subscriptionRules(), [
      _tun('a.panel.example'),
      _tun('b.panel.example'),
    ]);
    expect(setup.applied, 1);

    profiles.put(b.copyWith(label: 'renamed'));
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(setup.applied, 1, reason: 'the same hosts reload nothing');

    await profiles.del(a.id);
    await _until(() => setup.applied == 2);
    expect(await _subscriptionRules(), [_tun('b.panel.example')]);
  });

  test("the report's core lines lose the subscription host the rule names", () {
    const host = 'sub.panel.example';
    const line =
        '[TCP] 172.19.0.1:40312 --> $host:443 match '
        'AND((IN-TYPE,TUN),(DOMAIN,$host)) using DIRECT';
    for (final known in [RegExp(RegExp.escape(host)), null]) {
      expect(cleanLine(line, known), isNot(contains('panel')));
      expect(cleanLine(line, known), endsWith('using DIRECT'));
    }
  });
}
