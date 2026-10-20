import 'dart:io' show InternetAddress;

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const shikooDirectIds = 7470000;
const subscriptionDirectIds = shikooDirectIds + 500;

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
  RuleAction.AND => _tunDomain.firstMatch(rule.content ?? '')?[1],
  _ => null,
};

/// Tunnel only: an update sent past the local proxy (on Android, into the tunnel) goes DIRECT, one sent to it takes the server.
Rule subscriptionDirectRule(String host, int id) => Rule.parse(
  InternetAddress.tryParse(host) == null
      ? 'AND,((IN-TYPE,TUN),(DOMAIN,$host)),DIRECT'
      : 'AND,((IN-TYPE,TUN),(IP-CIDR,$host/32,no-resolve)),DIRECT',
  id: id,
);
