import 'dart:io' show InternetAddress, InternetAddressType;

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const shikooDirectIds = 7470000;
const iranDirectIds = shikooDirectIds + 200;
const subscriptionDirectIds = shikooDirectIds + 500;

/// `category-ir` holds all of `.ir`. `no-resolve`: resolving here would hold up every foreign site, so
/// an IP counts only for a connection that came without a name.
final iranDirectRules = [
  Rule.parse('GEOSITE,category-ir,DIRECT', id: iranDirectIds),
  Rule.parse('GEOIP,IR,DIRECT,no-resolve', id: iranDirectIds + 1),
];

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
  RuleAction.GEOSITE => 'geosite:${rule.content}',
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
