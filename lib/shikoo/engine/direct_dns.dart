import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const shikooDirectIds = 7470000;

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
      if (rule.id >= shikooDirectIds &&
          rule.id < shikooDirectIds + 1000 &&
          rule.ruleAction == RuleAction.DOMAIN)
        rule.content!: 'system',
    ...?(dns['nameserver-policy'] as Map?),
  },
};
