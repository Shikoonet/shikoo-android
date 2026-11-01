import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/shikoo/engine/offline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const none = ConnectivityResult.none;
  const wifi = ConnectivityResult.wifi;

  /// What [startsOffline] says, and how often the name, the door and the resolvers were asked.
  Future<(bool, int, int, int)> ask(
    List<ConnectivityResult> networks, {
    String? host = 'wg.shikoo.test',
    bool resolves = false,
    bool door = false,
    bool resolvers = false,
  }) async {
    var names = 0, doors = 0, servers = 0;
    final offline = await startsOffline(
      networks: () async => networks,
      resolves: (_) async {
        names++;
        return resolves;
      },
      door: () async {
        doors++;
        return door;
      },
      resolvers: () async {
        servers++;
        return resolvers;
      },
      host: host,
    );
    return (offline, names, doors, servers);
  }

  test('no network but the none is offline, asking nothing', () async {
    expect(await ask([none]), (true, 0, 0, 0));
  });

  test('a network with a name that resolves is online, and never asks the '
      'door or the resolvers', () async {
    expect(await ask([wifi], resolves: true), (false, 1, 0, 0));
  });

  test('a network with a name that does not resolve is offline only when '
      'neither the door nor the resolvers answer', () async {
    expect(await ask([wifi]), (true, 1, 1, 1));
    expect(await ask([wifi], door: true), (false, 1, 1, 1));
    expect(await ask([wifi], resolvers: true), (false, 1, 1, 1));
  });

  test('names that fail while an address answers is not offline, as with a '
      'device resolver that is broken', () async {
    final (offline, _, _, servers) = await ask([wifi], resolvers: true);
    expect(offline, isFalse);
    expect(servers, 1);
  });

  test('any doubt is online: an address, no name, a VPN among the networks, '
      'an empty answer', () async {
    expect(await ask([wifi], host: '203.0.113.7'), (false, 0, 0, 0));
    expect(await ask([wifi], host: null), (false, 0, 0, 0));
    expect(await ask([wifi], host: ''), (false, 0, 0, 0));
    expect(await ask([ConnectivityResult.vpn]), (false, 0, 0, 0));
    expect(await ask([wifi, ConnectivityResult.vpn]), (false, 0, 0, 0));
    expect(await ask([]), (false, 0, 0, 0));
  });

  test('any real network beside none counts as a network', () async {
    expect(await ask([none, ConnectivityResult.mobile], resolves: true), (
      false,
      1,
      0,
      0,
    ));
  });

  test('the resolvers it tries are the ones the fallback of mihomo relies '
      'on, from one list', () {
    final source = File('lib/shikoo/engine/offline.dart').readAsStringSync();
    expect(source, contains('in shikooServerNameDns) _connects(server, 53)'));
    expect(source, isNot(contains('8.8.8.8')));
    expect(source, isNot(contains('1.1.1.1')));
  });

  test('anyTrue is true on the first yes without waiting for the rest, and '
      'false only when all say no', () async {
    final slow = Completer<bool>();
    expect(await anyTrue([slow.future, Future.value(true)]), isTrue);
    expect(await anyTrue([Future.value(false), Future.value(false)]), isFalse);
    expect(await anyTrue(const []), isFalse);
    slow.complete(false);
  });
}
