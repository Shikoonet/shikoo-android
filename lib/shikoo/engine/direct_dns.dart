import 'dart:io' show InternetAddress, InternetAddressType;

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const shikooDirectIds = 7470000;
const iranDirectIds = shikooDirectIds + 200;
const subscriptionDirectIds = shikooDirectIds + 500;

/// Inside the block [shikooDns] sends to the device's DNS: Iranian sites, and the streaming server leaves in Iran too.
const streamingIds = shikooDirectIds + 300;

const shikooRuleSets = {'shikoo-ir-site': 'domain', 'shikoo-ir-ip': 'ipcidr'};

final iranDirectRules = [
  Rule.parse('DOMAIN-SUFFIX,xn--mgba3a4fra,DIRECT', id: iranDirectIds),
];

/// What the streaming server carries, measured through it on 2026-10-29 (namava.ir and the sites' ad hosts it
/// refuses, so they stay with Iran's rules). `MATCH` is FlClash's stand-in for the target of the panel's last rule.
final streamingRules = [
  for (final (i, domain) in const [
    'filimo.com',
    'gapfilm.ir',
    'sheyda.com',
  ].indexed)
    Rule.parse('DOMAIN-SUFFIX,$domain,MATCH', id: streamingIds + i),
];

void shikooIranSets(Map<dynamic, dynamic> config, Iterable<Rule> added) {
  final rules = config['rules'] as List?;
  // mihomo's own end is DIRECT: spelled out, [streamingRules]' MATCH has a target even where a profile has none.
  if (added.any((rule) => rule.ruleTarget?.toUpperCase() == 'MATCH') &&
      !(rules ?? const []).any(
        (rule) => '$rule'.trim().toUpperCase().startsWith('MATCH'),
      )) {
    config['rules'] = [...?rules, 'MATCH,DIRECT'];
  }
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
