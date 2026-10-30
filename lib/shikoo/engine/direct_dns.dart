import 'dart:convert' show base64Url;
import 'dart:io' show InternetAddress, InternetAddressType, ServerSocket;
import 'dart:math' show Random;

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const shikooDirectIds = 7470000;
const iranDirectIds = shikooDirectIds + 200;
const subscriptionDirectIds = shikooDirectIds + 500;

const shikooRuleSets = {'shikoo-ir-site': 'domain', 'shikoo-ir-ip': 'ipcidr'};

final iranDirectRules = [
  Rule.parse('DOMAIN-SUFFIX,xn--mgba3a4fra,DIRECT', id: iranDirectIds),
];

void shikooIranSets(Map<dynamic, dynamic> config, Iterable<Rule> added) {
  if (!added.any((rule) => rule.id == iranDirectIds)) return;
  final theirs = config['rule-providers'] is Map
      ? config['rule-providers'] as Map
      : const {};
  config['rule-providers'] = {
    for (final MapEntry(key: name, value: behavior) in shikooRuleSets.entries)
      name: {
        'type': 'file',
        'behavior': behavior,
        'format': 'mrs',
        'path': './$name.mrs',
      },
    ...theirs,
  };
  config['rules'] = [
    'RULE-SET,shikoo-ir-site,DIRECT',
    'RULE-SET,shikoo-ir-ip,DIRECT,no-resolve',
    ...?(config['rules'] as List?),
  ];
  // As a DNS policy an ipcidr set, as theirs may be, fails the whole config: no servers at all.
  if (!theirs.containsKey('shikoo-ir-site')) {
    (config['dns']['nameserver-policy'] as Map).putIfAbsent(
      'rule-set:shikoo-ir-site',
      () => 'system',
    );
  }
}

final _tunDomain = RegExp(r'^\(\(IN-TYPE,TUN\),\(DOMAIN,([^()]+)\)\)$');

/// SHIKOO_PATCHES 21: Shikoo's DIRECT hosts resolve with the device's DNS unless the panel's policy names that host.
/// No `listen`: the tunnel answers DNS through dns-hijack, and the server it opened answered any app and the Wi-Fi.
Map<String, dynamic> shikooDns(
  Map<String, dynamic> dns,
  Iterable<Rule> added,
) => {
  for (final MapEntry(:key, :value) in dns.entries)
    if (key != 'listen') key: value,
  'nameserver-policy': {
    for (final rule in added)
      if (rule.id >= shikooDirectIds && rule.id < shikooDirectIds + 1000)
        ?_domain(rule): 'system',
    ...?(dns['nameserver-policy'] as Map?),
  },
};

String? _domain(Rule rule) => switch (rule.ruleAction) {
  RuleAction.DOMAIN => rule.content,
  RuleAction.DOMAIN_SUFFIX => '+.${rule.content}',
  RuleAction.AND => _tunDomain.firstMatch(rule.content ?? '')?[1],
  _ => null,
};

/// Tunnel only, so an update sent to the local proxy takes the server. shortcut: a host shared with the door or a probe goes DIRECT both ways; make those rules tunnel-only if that happens.
Rule subscriptionDirectRule(
  String host,
  int id,
) => Rule.parse(switch (InternetAddress.tryParse(host)?.type) {
  null => 'AND,((IN-TYPE,TUN),(DOMAIN,$host)),DIRECT',
  final type =>
    'AND,((IN-TYPE,TUN),(IP-CIDR,$host/${type == InternetAddressType.IPv6 ? 128 : 32},no-resolve)),DIRECT',
}, id: id);

const shikooDirectInbound = 'shikoo-direct';

typedef ShikooDirectAuth = ({int port, String user, String pass});

ShikooDirectAuth? shikooDirectAuth;

/// shortcut: a port another app takes before the core binds it leaves updates to the server; pick it per apply if seen.
Future<void> openDirectInbound() async {
  final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = free.port;
  await free.close();
  final random = Random.secure();
  String secret() =>
      base64Url.encode([for (var i = 0; i < 18; i++) random.nextInt(256)]);
  shikooDirectAuth = (port: port, user: secret(), pass: secret());
}

String? directInboundProxy() => switch (shikooDirectAuth) {
  null => null,
  final a => 'PROXY ${a.user}:${a.pass}@127.0.0.1:${a.port}',
};

final _tunOnly = RegExp(
  r'^AND,\(\(IN-TYPE,TUN\),\((DOMAIN|IP-CIDR),([^,()]+)(,no-resolve)?\)\),DIRECT$',
);

/// mihomo's inbound for [directInboundProxy]: loopback, this run's credentials, and rules of its own, so another app on
/// the device that finds it leaves by it only for the subscription hosts [added] sends direct from the tunnel.
Map<String, dynamic> withDirectInbound(
  Map<String, dynamic> config,
  Iterable<Rule> added,
  ShikooDirectAuth auth,
) => {
  ...config,
  'listeners': [
    ...?(config['listeners'] as List?),
    {
      'name': shikooDirectInbound,
      'type': 'http',
      'listen': '127.0.0.1',
      'port': '${auth.port}',
      'users': [
        {'username': auth.user, 'password': auth.pass},
      ],
      'rule': shikooDirectInbound,
    },
  ],
  'sub-rules': {
    ...?(config['sub-rules'] as Map?),
    shikooDirectInbound: [
      for (final rule in added)
        if (_tunOnly.firstMatch(rule.rawValue) case final m?)
          '${m[1]},${m[2]},DIRECT${m[3] ?? ''}',
      'MATCH,REJECT',
    ],
  },
};
