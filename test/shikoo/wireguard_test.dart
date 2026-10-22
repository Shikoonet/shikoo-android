import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
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

const _filled = {'mtu': 1280, 'persistent-keepalive': 25, 'udp': true};

void main() {
  test('the config the core runs fills what the panel left out of a WireGuard '
      'server, keeps what it set, and leaves other servers alone', () async {
    final panel = {'mtu': 1420, 'persistent-keepalive': 0, 'udp': false};
    final made = await makeRealProfileTask(
      MakeRealProfileState(
        profilesPath: '/profiles',
        profileId: 1,
        rawConfig: {
          'proxies': [_wireGuard('bare'), _wireGuard('set', panel), _vless],
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
    expect(proxies[2], _vless);
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
}
