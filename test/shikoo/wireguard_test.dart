import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:fl_clash/shikoo/engine/wireguard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> _wireGuard(String name, [Map<String, dynamic>? set]) => {
  'name': name,
  'type': 'wireguard',
  'server': '203.0.113.7',
  'port': 51820,
  'ip': '10.0.0.2',
  'private-key': 'not-a-key',
  'public-key': 'not-a-key',
  ...?set,
};

const _vless = {
  'name': 'vless',
  'type': 'vless',
  'server': '203.0.113.8',
  'port': 443,
};

const _filled = {
  'mtu': 1280,
  'persistent-keepalive': 25,
  'udp': true,
  'remote-dns-resolve': true,
  'dns': ['1.1.1.1', '8.8.8.8'],
};

void main() {
  test('the config the core runs fills what the panel left out of a WireGuard '
      'server, keeps what it set, and leaves other servers alone', () async {
    final panel = {
      'mtu': 1420,
      'persistent-keepalive': 0,
      'udp': false,
      'remote-dns-resolve': false,
    };
    final dnsOnly = {
      'dns': ['9.9.9.9'],
    };
    final made = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 1,
        rawConfig: {
          'proxies': [
            _wireGuard('bare'),
            _wireGuard('set', panel),
            _wireGuard('dns only', dnsOnly),
            _vless,
          ],
          'rules': ['MATCH,DIRECT'],
        },
        realPatchConfig: const PatchClashConfig(),
        overrideDns: false,
        appendSystemDns: false,
        proxyGroups: const [],
        rules: const [],
        addedRules: const [],
        defaultUA: 'FlClash-Test',
      ),
    );
    final proxies = (loadYaml(made.yaml) as YamlMap)['proxies'] as List;

    expect(proxies[0], {..._wireGuard('bare'), ..._filled});
    expect(proxies[1], _wireGuard('set', panel));
    expect(proxies[2], {
      ..._wireGuard('dns only', dnsOnly),
      'mtu': 1280,
      'persistent-keepalive': 25,
      'udp': true,
    });
    expect(proxies[3], _vless);
  });

  test("another service's servers are pinged with the same fill", () {
    final main = mainGroupOf({
      'proxies': [_wireGuard('wg'), _vless],
      'proxy-groups': [
        {
          'name': 'PROXY',
          'type': 'select',
          'proxies': ['wg', 'vless'],
        },
      ],
    })!;

    expect(main.servers['wg'], {..._wireGuard('wg'), ..._filled});
    expect(main.servers['vless'], _vless);
  });

  group('names inside the tunnel only where its DNS lookups can pass', () {
    bool resolvesInside(Map<String, dynamic> panel) {
      final proxy = _wireGuard('wg', panel);
      wireGuardDefaults(proxy);
      return proxy['remote-dns-resolve'] == true;
    }

    Map<String, dynamic> peers(List<String> allowed) => {
      'peers': [
        {'server': '203.0.113.7', 'port': 51820, 'allowed-ips': allowed},
      ],
    };

    test('not when the panel turned UDP off: the core sends no UDP then', () {
      expect(resolvesInside({'udp': false}), isFalse);
      expect(resolvesInside({'udp': true}), isTrue);
    });

    test('not without an IPv4 address: the lookups go to 1.1.1.1 and '
        '8.8.8.8', () {
      expect(resolvesInside({'ip': null, 'ipv6': 'fd00::7'}), isFalse);
      expect(resolvesInside({'ipv6': 'fd00::8'}), isTrue);
    });

    test("not when the peers' allowed-ips leave 1.1.1.1 or 8.8.8.8 out", () {
      expect(resolvesInside(peers(['104.16.0.0/12', '10.99.0.0/16'])), isFalse);
      expect(resolvesInside(peers(['1.1.1.1/32'])), isFalse);
      expect(resolvesInside(peers(['1.1.1.1'])), isFalse);
      expect(
        resolvesInside(peers(['::/0', 'nonsense', '8.8.8.8/33'])),
        isFalse,
      );
      expect(resolvesInside(peers(['0.0.0.0/0'])), isTrue);
      expect(resolvesInside(peers(['0.0.0.0/1', '128.0.0.0/1'])), isTrue);
      expect(resolvesInside(peers(['1.1.1.1', '8.8.0.0/16'])), isTrue);
    });

    test('not, and no error, when allowed-ips is not a list', () {
      final proxy = _wireGuard('wg', {
        'peers': [
          {'server': '203.0.113.7', 'port': 51820, 'allowed-ips': '0.0.0.0/0'},
        ],
      });
      expect(() => wireGuardDefaults(proxy), returnsNormally);
      expect(proxy.containsKey('remote-dns-resolve'), isFalse);
    });
  });
}
