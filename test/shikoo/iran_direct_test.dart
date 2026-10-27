import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/shikoo/engine/account.dart';
import 'package:fl_clash/shikoo/engine/direct_dns.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:yaml/yaml.dart';

const _iran = [
  'DOMAIN-SUFFIX,ir,DIRECT',
  'DOMAIN-SUFFIX,xn--mgba3a4fra,DIRECT',
];
const _sets = [
  'RULE-SET,shikoo-ir-site,DIRECT',
  'RULE-SET,shikoo-ir-ip,DIRECT,no-resolve',
];
const _door = [
  'DOMAIN,app.chopon.uk,DIRECT',
  'DOMAIN,www.aparat.com,DIRECT',
  'DOMAIN,www.digikala.com,DIRECT',
  'DOMAIN,connectivitycheck.gstatic.com,DIRECT',
];
const _subscription = 'AND,((IN-TYPE,TUN),(DOMAIN,sub.panel.example)),DIRECT';
const _panelRules = ['DOMAIN-SUFFIX,ir,PROXY', 'MATCH,PROXY'];
const _ours = {
  'shikoo-ir-site': {
    'type': 'file',
    'behavior': 'domain',
    'format': 'mrs',
    'path': './shikoo-ir-site.mrs',
  },
  'shikoo-ir-ip': {
    'type': 'file',
    'behavior': 'ipcidr',
    'format': 'mrs',
    'path': './shikoo-ir-ip.mrs',
  },
};

/// MetaCubeX/meta-rules-dat 5b62abd8, `geo/geosite/category-ir.mrs` and `geo/geoip/ir.mrs` (SHIKOO_PATCHES 21).
const _shipped = {
  'shikoo-ir-site':
      'ace1a88835fbb5a25167cc5020070a9be7caf6c97f23f6915802cc622267f29e',
  'shikoo-ir-ip':
      'e559eba0cbd8da49b9c73f1be75ca3ea6a94f1cf3f3acbbbe47f776dfa8ec2c9',
};

Future<YamlMap> _config({
  bool tun = true,
  Map<String, Object>? panelSets,
}) async {
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
        'rule-providers': ?panelSets,
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
  TestWidgetsFlutterBinding.ensureInitialized();
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
        "their names found with the device's DNS", () async {
      await keepIranDirect(true);
      final config = await _config(tun: tun);
      expect((config['tun'] as YamlMap)['enable'], tun);
      final rules = config['rules'] as List;
      expect(
        rules.take(9),
        unorderedEquals([..._iran, ..._door, _subscription, ..._sets]),
      );
      expect(rules.skip(9), _panelRules);
      expect(config['rule-providers'], _ours);
      expect((config['dns'] as YamlMap)['nameserver-policy'], {
        'rule-set:shikoo-ir-site': 'system',
        '+.ir': 'system',
        '+.xn--mgba3a4fra': 'system',
        'app.chopon.uk': 'system',
        'www.aparat.com': 'system',
        'www.digikala.com': 'system',
        'connectivitycheck.gstatic.com': 'system',
        'sub.panel.example': 'system',
      });
    });
  }

  test("the subscription's own sets stay as FlClash left them, ours beside "
      'them, and theirs win a shared name', () async {
    // Not const: FlClash writes each provider's path into the map.
    final panelSets = <String, Object>{
      'ads': {
        'type': 'http',
        'behavior': 'domain',
        'url': 'https://panel.example/ads.yaml',
        'interval': 86400,
      },
      'shikoo-ir-ip': {'type': 'inline', 'behavior': 'classical'},
    };
    final off = (await _config(panelSets: panelSets))['rule-providers'];
    await keepIranDirect(true);
    final on = (await _config(panelSets: panelSets))['rule-providers'];
    expect((off as YamlMap).keys, unorderedEquals(panelSets.keys));
    expect(on, {...off, 'shikoo-ir-site': _ours['shikoo-ir-site']});
  });

  test("a subscription's set named like ours keeps its place and leaves the "
      'DNS policy, which the core would refuse for an ipcidr set', () async {
    await keepIranDirect(true);
    final theirs = {
      'type': 'inline',
      'behavior': 'ipcidr',
      'payload': ['10.0.0.0/8'],
    };
    final config = await _config(
      panelSets: <String, Object>{'shikoo-ir-site': theirs},
    );
    expect((config['rule-providers'] as YamlMap)['shikoo-ir-site'], theirs);
    expect(
      ((config['dns'] as YamlMap)['nameserver-policy'] as YamlMap).keys,
      allOf(
        isNot(contains('rule-set:shikoo-ir-site')),
        contains('+.xn--mgba3a4fra'),
      ),
    );
  });

  test("the rules keep Shikoo's ids, apart from the door's and the "
      "subscriptions'", () async {
    await keepIranDirect(true);
    expect(await _stored(), {
      shikooDirectIds: _door[0],
      for (final (i, rule) in _door.skip(1).indexed) 7470100 + i: rule,
      for (final (i, rule) in _iran.indexed) 7470200 + i: rule,
      subscriptionDirectIds: _subscription,
    });
  });

  test('off takes the rules, their sets and their DNS out and leaves the '
      'rest; on again, even twice, brings back the same config', () async {
    await keepIranDirect(true);
    final on = await _config();
    await keepIranDirect(false);
    final off = await _config();
    final rules = off['rules'] as List;
    expect(rules.take(5), unorderedEquals([..._door, _subscription]));
    expect(rules.skip(5), _panelRules);
    expect(off.containsKey('rule-providers'), isFalse);
    expect(
      ((off['dns'] as YamlMap)['nameserver-policy'] as YamlMap).keys,
      unorderedEquals([
        'app.chopon.uk',
        'www.aparat.com',
        'www.digikala.com',
        'connectivitycheck.gstatic.com',
        'sub.panel.example',
      ]),
    );
    await keepIranDirect(true);
    await keepIranDirect(true);
    final again = await _config();
    expect(again['rules'], unorderedEquals(on['rules'] as List));
    expect(again['dns'], on['dns']);
    expect(again['rule-providers'], on['rule-providers']);
  });

  test('the stored rows need no rule set: an older build on this data, '
      'which adds none, still loads its config', () async {
    await keepIranDirect(true);
    final block = [
      for (final rule in await database.rulesDao.queryGlobalAddedRules().get())
        if (rule.id >= iranDirectIds && rule.id < iranDirectIds + 100) rule,
    ];
    expect(block.map((rule) => rule.rawValue), _iran);
    expect(block.map((rule) => rule.ruleProvider), everyElement(isNull));
  });

  test(
    'rows an earlier build stored under the Iranian ids go, on or off',
    () async {
      for (final on in [true, false]) {
        for (final (i, rule) in [
          ..._sets,
          'DOMAIN-SUFFIX,xn--mgba3a4fra,DIRECT',
        ].indexed) {
          await database.rulesDao.putGlobalRule(
            Rule.parse(rule, id: iranDirectIds + i),
          );
        }
        await keepIranDirect(on);
        expect([
          for (final MapEntry(:key, :value) in (await _stored()).entries)
            if (key >= iranDirectIds && key < iranDirectIds + 100) value,
        ], on ? _iran : isEmpty);
      }
    },
  );

  test('quick turns land in the order they were made', () async {
    await Future.wait([false, true, false, true, false].map(keepIranDirect));
    expect((await _stored()).values.where(_iran.contains), isEmpty);
    await Future.wait([true, false, true, false, true].map(keepIranDirect));
    expect((await _stored()).values, containsAll(_iran));
  });

  test("the shipped sets reach the core's home, rewritten only when they "
      'differ', () async {
    final home = Directory.systemTemp.createTempSync('shikoo-sets-');
    addTearDown(() => home.deleteSync(recursive: true));
    File file(String name) => File(join(home.path, '$name.mrs'));
    String sha(String name) =>
        '${sha256.convert(file(name).readAsBytesSync())}';

    await writeRuleSets(home.path);
    expect({for (final name in _shipped.keys) name: sha(name)}, _shipped);

    final kept = file('shikoo-ir-ip').statSync().modified;
    file('shikoo-ir-site').writeAsStringSync('an older set');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await writeRuleSets(home.path);
    expect(sha('shikoo-ir-site'), _shipped['shikoo-ir-site']);
    expect(file('shikoo-ir-ip').statSync().modified, kept);
  });

  test('a home the sets cannot be written to is logged and the start goes '
      'on', () async {
    final home = Directory.systemTemp.createTempSync('shikoo-sets-');
    addTearDown(() => home.deleteSync(recursive: true));
    final lines = <String?>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message);
    addTearDown(() => debugPrint = print);

    await expectLater(writeRuleSets(join(home.path, 'missing')), completes);
    expect(lines, [startsWith('[APP] rule sets not written')]);
  });
}
