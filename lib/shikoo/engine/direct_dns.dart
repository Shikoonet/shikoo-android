import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const shikooDirectIds = 7470000;

/// SHIKOO_PATCHES 21: Shikoo's DIRECT hosts resolve with the device's DNS unless the panel's policy names that host.
Map<String, dynamic> withDirectHostsOnSystemDns(
  Map<String, dynamic> dns,
  Iterable<Rule> added,
) => {
  ...dns,
  'nameserver-policy': {
    for (final rule in added)
      if (rule.id >= shikooDirectIds &&
          rule.id < shikooDirectIds + 1000 &&
          rule.ruleAction == RuleAction.DOMAIN)
        rule.content!: 'system',
    ...?(dns['nameserver-policy'] as Map?),
  },
};
