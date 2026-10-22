import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/direct_dns.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _iran = ['GEOSITE,category-ir,DIRECT', 'GEOIP,IR,DIRECT,no-resolve'];
const _door = [
  'DOMAIN,app.chopon.uk,DIRECT',
  'DOMAIN,www.aparat.com,DIRECT',
  'DOMAIN,www.digikala.com,DIRECT',
  'DOMAIN,connectivitycheck.gstatic.com,DIRECT',
];
const _subscription = 'AND,((IN-TYPE,TUN),(DOMAIN,sub.panel.example)),DIRECT';
const _panelRules = ['DOMAIN-SUFFIX,ir,PROXY', 'MATCH,PROXY'];

Future<YamlMap> _config({bool tun = true}) async {
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
        'rules': _panelRules,
      },
      realPatchConfig: PatchClashConfig(tun: Tun(enable: tun)),
      overrideDns: false,
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: await database.rulesDao.queryAddedRules(1).get(),
      defaultUA: 'FlClash-Test',
    ),
  );
  return loadYaml(made.yaml) as YamlMap;
}

Future<Map<int, String>> _stored() async => {
  for (final rule in await database.rulesDao.queryGlobalAddedRules().get())
    rule.id: rule.rawValue,
};

void main() {
  setUp(() async {
    final before = database;
    database = Database(NativeDatabase.memory());
    addTearDown(() async {
      await database.close();
      database = before;
    });
    await database.profilesDao.putAll([
      const Profile(id: 1, autoUpdateDuration: Duration.zero).toCompanion(),
    ]);
    await keepApiDirect();
    await keepSubscriptionsDirect(['https://sub.panel.example/sub/1']);
  });

  for (final tun in [true, false]) {
    test('${tun ? 'tunnel' : 'proxy'} mode: Iranian sites go DIRECT ahead of '
        "the subscription's rules, beside the door's and the subscription's, "
        "found with the device's DNS", () async {
      await keepIranDirect(true);
      final config = await _config(tun: tun);
      expect((config['tun'] as YamlMap)['enable'], tun);
      final rules = config['rules'] as List;
      expect(
        rules.take(7),
        unorderedEquals([..._iran, ..._door, _subscription]),
      );
      expect(rules.skip(7), _panelRules);
      expect((config['dns'] as YamlMap)['nameserver-policy'], {
        'geosite:category-ir': 'system',
        'app.chopon.uk': 'system',
        'www.aparat.com': 'system',
        'www.digikala.com': 'system',
        'connectivitycheck.gstatic.com': 'system',
        'sub.panel.example': 'system',
      });
    });
  }

  test("the two rules keep Shikoo's ids, apart from the door's and the "
      "subscriptions'", () async {
    await keepIranDirect(true);
    final stored = await _stored();
    expect(stored, {
      shikooDirectIds: _door[0],
      for (final (i, rule) in _door.skip(1).indexed) 7470100 + i: rule,
      7470200: _iran[0],
      7470201: _iran[1],
      subscriptionDirectIds: _subscription,
    });
  });

  test('off takes both rules and their DNS out and leaves the rest; on again, '
      'even twice, brings back the same config', () async {
    await keepIranDirect(true);
    final on = await _config();
    await keepIranDirect(false);
    final off = await _config();
    final rules = off['rules'] as List;
    expect(rules.take(5), unorderedEquals([..._door, _subscription]));
    expect(rules.skip(5), _panelRules);
    expect(
      (off['dns'] as YamlMap)['nameserver-policy'],
      isNot(contains('geosite:category-ir')),
    );
    await keepIranDirect(true);
    await keepIranDirect(true);
    final again = await _config();
    expect(again['rules'], unorderedEquals(on['rules'] as List));
    expect(again['dns'], on['dns']);
  });

  test('quick turns land in the order they were made', () async {
    await Future.wait([false, true, false, true, false].map(keepIranDirect));
    expect((await _stored()).values.where(_iran.contains), isEmpty);
    await Future.wait([true, false, true, false, true].map(keepIranDirect));
    expect((await _stored()).values, containsAll(_iran));
  });
}
