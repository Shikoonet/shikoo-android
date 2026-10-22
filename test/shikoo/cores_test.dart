import 'dart:io';

import 'package:fl_clash/shikoo/engine/core_sing_box.dart';
import 'package:fl_clash/shikoo/engine/core_wireguard.dart';
import 'package:fl_clash/shikoo/engine/core_xray.dart';
import 'package:fl_clash/shikoo/engine/cores.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Readiness is set here, not by the build, so a package that flips its own core's flag breaks nothing.
Map<ShikooCore, ShikooCoreSpec> _readyOnly(Set<ShikooCore> ready) => {
  for (final MapEntry(key: core, value: spec) in shikooCoreSpecs.entries)
    core: (
      ready: core == ShikooCore.mihomo || ready.contains(core),
      shape: spec.shape,
      serves: spec.serves,
    ),
};

final _allReady = _readyOnly(ShikooCore.values.toSet());
final _noneReady = _readyOnly(const {});

const _reality = {
  'name': 'آلمان ۱',
  'type': 'vless',
  'reality-opts': {'public-key': 'k', 'short-id': 's'},
};
const _xhttp = {'name': 'هلند ۱', 'type': 'vless', 'network': 'xhttp'};
const _encrypted = {'name': 'هلند ۲', 'type': 'vless', 'encryption': 'mlkem'};
const _wireguard = {'name': 'آلمان ۳', 'type': 'wireguard'};
const _ssh = {'name': 'ssh', 'type': 'ssh'};
const _vmess = {'name': 'vmess', 'type': 'vmess'};

void main() {
  test('the protocol comes from the profile type, in any case', () {
    expect(protocolOf(_reality), ShikooProtocol.vless);
    expect(protocolOf(const {'type': 'Vless'}), ShikooProtocol.vless);
    expect(protocolOf(_wireguard), ShikooProtocol.wireguard);
    expect(protocolOf(const {'type': 'OpenVPN'}), ShikooProtocol.openvpn);
    expect(protocolOf(_ssh), ShikooProtocol.ssh);
    expect(protocolOf(_vmess), ShikooProtocol.other);
    expect(protocolOf(const {'type': 'Socks5'}), ShikooProtocol.other);
  });

  test('a pick this build lacks, or one that cannot carry the server, stays on '
      'mihomo', () {
    const choices = {
      ShikooProtocol.vless: ShikooCore.singBox,
      ShikooProtocol.wireguard: ShikooCore.wireguard,
    };
    expect(
      coreFor(_reality, choices, specs: _noneReady),
      ShikooCore.mihomo,
      reason: 'not ready',
    );
    expect(coreFor(_reality, choices, specs: _allReady), ShikooCore.singBox);
    expect(coreFor(_xhttp, choices, specs: _allReady), ShikooCore.mihomo);
    expect(coreFor(_encrypted, choices, specs: _allReady), ShikooCore.mihomo);
    expect(
      coreFor(_wireguard, choices, specs: _allReady),
      ShikooCore.wireguard,
    );
    expect(
      coreFor(_wireguard, choices, specs: _allReady, tunnel: false),
      ShikooCore.mihomo,
      reason: "Windows' proxy mode has no tunnel to own",
    );
    expect(coreFor(_ssh, choices, specs: _allReady), ShikooCore.mihomo);
  });

  test('the running core is the pick only once Go replaced the server', () {
    const choices = {ShikooProtocol.vless: ShikooCore.xray};
    expect(
      runningCore(_reality, 'Socks5', choices, specs: _allReady),
      ShikooCore.xray,
    );
    expect(
      runningCore(_reality, 'Vless', choices, specs: _allReady),
      ShikooCore.mihomo,
      reason: 'Go left it to mihomo: the core is missing or failed',
    );
    expect(
      runningCore(null, 'Socks5', choices, specs: _allReady),
      ShikooCore.mihomo,
    );
    expect(
      runningCore(_wireguard, 'WireGuard', const {
        ShikooProtocol.wireguard: ShikooCore.wireguard,
      }, specs: _allReady),
      ShikooCore.wireguard,
      reason: 'an owner core takes the tunnel, not a server in mihomo',
    );
  });

  test('a row per protocol present, each with every core that carries it and '
      'whether it is ready', () {
    final rows = coreRows(
      {ShikooProtocol.ssh, ShikooProtocol.vless, ShikooProtocol.other},
      const {ShikooProtocol.vless: ShikooCore.xray},
      specs: _noneReady,
    );
    expect(rows.map((row) => row.protocol), [
      ShikooProtocol.vless,
      ShikooProtocol.ssh,
    ]);
    expect(rows.first.chosen, ShikooCore.mihomo, reason: 'xray is not ready');
    expect(rows.first.options, [
      (core: ShikooCore.mihomo, ready: true),
      (core: ShikooCore.xray, ready: false),
      (core: ShikooCore.singBox, ready: false),
    ]);
    expect(rows.last.options, [
      (core: ShikooCore.mihomo, ready: true),
      (core: ShikooCore.singBox, ready: false),
    ]);
    expect(
      coreRows(
        {ShikooProtocol.wireguard},
        const {ShikooProtocol.wireguard: ShikooCore.wireguard},
        specs: _allReady,
      ).single.chosen,
      ShikooCore.wireguard,
    );
  });

  test(
    'an owner core holds the tunnel per server; every other shares mihomo\'s',
    () {
      expect(tunnelKey(ShikooCore.wireguard, 'آلمان ۳'), 'wireguard/آلمان ۳');
      expect(tunnelKey(ShikooCore.xray, 'آلمان ۱'), 'mihomo');
      expect(tunnelKey(ShikooCore.mihomo, 'آلمان ۱'), 'mihomo');
    },
  );

  test('only servers a core behind mihomo carries are marked, and all-mihomo '
      'gives the config back untouched', () {
    final config = {
      'mixed-port': 7890,
      'proxies': [_reality, _xhttp, _wireguard, _ssh, _vmess],
    };
    expect(identical(markCores(config, const {}), config), isTrue);
    expect(
      identical(
        markCores(config, const {
          ShikooProtocol.vless: ShikooCore.xray,
        }, specs: _noneReady),
        config,
      ),
      isTrue,
      reason: 'xray is not ready',
    );

    final marked = markCores(config, const {
      ShikooProtocol.vless: ShikooCore.singBox,
      ShikooProtocol.wireguard: ShikooCore.xray,
      ShikooProtocol.ssh: ShikooCore.mihomo,
    }, specs: _allReady);
    expect(
      [
        for (final proxy in marked['proxies'] as List)
          (proxy as Map)[shikooCoreKey],
      ],
      ['singBox', null, 'xray', null, null],
    );
    expect(marked['mixed-port'], 7890);
    expect(_reality.containsKey(shikooCoreKey), isFalse);
    expect(
      identical(
        markCores(config, const {
          ShikooProtocol.wireguard: ShikooCore.wireguard,
        }, specs: _allReady),
        config,
      ),
      isTrue,
      reason: 'an owner core is not marked: it takes the tunnel instead',
    );
  });

  test('OpenVPN defaults to the official core once this build has it ready, '
      "never over the user's own pick nor in Windows' proxy mode", () {
    const ovpn = {'name': 'ovpn', 'type': 'openvpn'};
    final official = _readyOnly({ShikooCore.openvpn});
    expect(
      coreFor(ovpn, const {}, specs: _noneReady),
      ShikooCore.mihomo,
      reason: 'the default is not ready yet',
    );
    expect(coreFor(ovpn, const {}, specs: official), ShikooCore.openvpn);
    expect(
      coreFor(ovpn, const {}, specs: official, tunnel: false),
      ShikooCore.mihomo,
      reason: 'proxy mode has no tunnel for it to own',
    );
    expect(
      coreFor(ovpn, const {
        ShikooProtocol.openvpn: ShikooCore.mihomo,
      }, specs: official),
      ShikooCore.mihomo,
    );
    expect(
      coreFor(ovpn, const {
        ShikooProtocol.openvpn: ShikooCore.singBox,
      }, specs: _allReady),
      ShikooCore.singBox,
    );
    expect(
      runningCore(ovpn, 'OpenVPN', const {}, specs: official),
      ShikooCore.openvpn,
    );
    expect(
      [
        _reality,
        _wireguard,
        _ssh,
      ].map((server) => coreFor(server, const {}, specs: _allReady)),
      everyElement(ShikooCore.mihomo),
      reason: 'the other protocols still default to mihomo',
    );
    final ovpnConfig = <String, dynamic>{
      'proxies': [ovpn],
    };
    expect(
      identical(markCores(ovpnConfig, const {}, specs: official), ovpnConfig),
      isTrue,
      reason: 'a default that owns the tunnel is not marked',
    );

    ({ShikooCore chosen, ShikooCore defaultCore}) row(
      ShikooChoices choices,
      Map<ShikooCore, ShikooCoreSpec> specs,
    ) {
      final row = coreRows(
        {ShikooProtocol.openvpn},
        choices,
        specs: specs,
      ).single;
      return (chosen: row.chosen, defaultCore: row.defaultCore);
    }

    expect(row(const {}, _noneReady), (
      chosen: ShikooCore.mihomo,
      defaultCore: ShikooCore.mihomo,
    ));
    expect(row(const {}, official), (
      chosen: ShikooCore.openvpn,
      defaultCore: ShikooCore.openvpn,
    ));
    expect(row(const {ShikooProtocol.openvpn: ShikooCore.mihomo}, official), (
      chosen: ShikooCore.mihomo,
      defaultCore: ShikooCore.openvpn,
    ));
    expect(
      coreRows(
        {ShikooProtocol.vless},
        const {},
        specs: _allReady,
      ).single.defaultCore,
      ShikooCore.mihomo,
    );
  });

  test('each stub carries what its package starts from', () {
    expect(xraySpec.shape, ShikooShape.behindMihomo);
    expect(singBoxSpec.shape, ShikooShape.behindMihomo);
    expect(wireguardSpec.shape, ShikooShape.ownsTunnel);
    expect(xraySpec.serves(ShikooProtocol.ssh, const {}), isFalse);
    expect(singBoxSpec.serves(ShikooProtocol.openvpn, const {}), isTrue);
  });

  test('a core behind mihomo is ready only if the Go core registers it under '
      'the same name, and Go registers no other', () {
    final registered = {
      for (final file in Directory('core').listSync().whereType<File>())
        if (file.path.endsWith('.go') && !file.path.endsWith('_test.go'))
          for (final match in RegExp(
            r'registerShikooCore\("([^"]+)"',
          ).allMatches(file.readAsStringSync()))
            match[1]!,
    };
    final behind = {
      for (final MapEntry(key: core, value: spec) in shikooCoreSpecs.entries)
        if (spec.shape == ShikooShape.behindMihomo) core.name: spec.ready,
    };
    for (final name in registered) {
      expect(behind.containsKey(name), isTrue, reason: '$name is not in Dart');
    }
    for (final MapEntry(key: name, value: ready) in behind.entries) {
      if (ready) {
        expect(registered, contains(name), reason: '$name is not in Go');
      }
    }
  });

  test('the pick survives a restart, and a core this build lacks is skipped '
      'with its key kept', () async {
    SharedPreferences.setMockInitialValues({'shikoo.core.ssh': 'naive'});
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await first
        .read(shikooCoresProvider.notifier)
        .set(ShikooProtocol.vless, ShikooCore.xray);

    final second = ProviderContainer();
    addTearDown(second.dispose);
    await second.read(shikooCoresProvider.notifier).load();

    expect(second.read(shikooCoresProvider), {
      ShikooProtocol.vless: ShikooCore.xray,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('shikoo.core.ssh'), 'naive');
  });
}
