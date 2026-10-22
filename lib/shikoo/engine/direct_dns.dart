import 'dart:io' show InternetAddress, InternetAddressType;

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const shikooDirectIds = 7470000;
const iranDirectIds = shikooDirectIds + 200;
const subscriptionDirectIds = shikooDirectIds + 500;

const shikooRuleSets = {'shikoo-ir-site': 'domain', 'shikoo-ir-ip': 'ipcidr'};

/// `category-ir` holds all of `.ir`. `no-resolve`: resolving here would hold up every foreign site, so
/// an IP counts only for a connection that came without a name.
final iranDirectRules = [
  Rule.parse('RULE-SET,shikoo-ir-site,DIRECT', id: iranDirectIds),
  Rule.parse('RULE-SET,shikoo-ir-ip,DIRECT,no-resolve', id: iranDirectIds + 1),
  Rule.parse('DOMAIN-SUFFIX,xn--mgba3a4fra,DIRECT', id: iranDirectIds + 2),
];

void shikooRuleProviders(Map<dynamic, dynamic> config, Iterable<Rule> added) {
  final used = {
    for (final rule in added)
      if (shikooRuleSets[rule.ruleProvider] case final behavior?)
        rule.ruleProvider!: {
          'type': 'file',
          'behavior': behavior,
          'format': 'mrs',
          'path': './${rule.ruleProvider}.mrs',
        },
  };
  if (used.isEmpty) return;
  config['rule-providers'] = {...used, ...?(config['rule-providers'] as Map?)};
}

final _tunDomain = RegExp(r'^\(\(IN-TYPE,TUN\),\(DOMAIN,([^()]+)\)\)$');

/// SHIKOO_PATCHES 21: Shikoo's DIRECT hosts resolve with the device's DNS unless the panel's policy names that host.
/// No `listen`: the tunnel answers DNS through dns-hijack, and the server it opened answered any app and the Wi-Fi.
Map<String, dynamic> shikooDns(
  Map<String, dynamic> dns,
  Iterable<Rule> added,
  Object? subscriptionSets,
) => {
  for (final MapEntry(:key, :value) in dns.entries)
    if (key != 'listen') key: value,
  'nameserver-policy': {
    for (final rule in added)
      if (rule.id >= shikooDirectIds && rule.id < shikooDirectIds + 1000)
        ?_domain(rule, subscriptionSets): 'system',
    ...?(dns['nameserver-policy'] as Map?),
  },
};

String? _domain(
  Rule rule,
  Object? subscriptionSets,
) => switch (rule.ruleAction) {
  RuleAction.DOMAIN => rule.content,
  RuleAction.DOMAIN_SUFFIX => '+.${rule.content}',
  // An `ipcidr` set here, or a subscription's set of our name, fails the whole config: no servers.
  RuleAction.RULE_SET
      when shikooRuleSets[rule.ruleProvider] == 'domain' &&
          !(subscriptionSets is Map &&
              subscriptionSets.containsKey(rule.ruleProvider)) =>
    'rule-set:${rule.ruleProvider}',
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
