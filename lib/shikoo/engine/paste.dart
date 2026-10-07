import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShikooPasteError { empty, notShikoo, revoked, unavailable, offline, clock }

// ponytail: only the test link's domain; needs every domain Sam names, and moves with the panel.
const shikooSubscriptionDomains = ['4g3.uk'];

const shikooDebug = bool.fromEnvironment('SHIKOO_DEBUG');

const shikooPastedKey = 'shikoo.pasted';

/// The profiles the customer pasted; an account that leaves takes every other one with it.
Future<Set<int>> pastedProfiles() async {
  final prefs = await SharedPreferences.getInstance();
  return {...?prefs.getStringList(shikooPastedKey)?.map(int.parse)};
}

Future<void> markPasted(Iterable<int> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(shikooPastedKey, [
    ...{...?prefs.getStringList(shikooPastedKey), for (final id in ids) '$id'},
  ]);
}

Future<void> forgetPasted(int id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(shikooPastedKey, [
    for (final kept in prefs.getStringList(shikooPastedKey) ?? <String>[])
      if (kept != '$id') kept,
  ]);
}

const _emulatorHostMachine = '10.0.2.2';

const _maxLink = 2048;

final _link = RegExp(r'https?://[^\s‎‏]+', caseSensitive: false);
final _sentenceEnd = RegExp(r'[،.,;!؟)»>]+$');

String? shikooLink(String text, {bool debug = shikooDebug}) {
  for (final match in _link.allMatches(text)) {
    final link = match[0]!.replaceFirst(_sentenceEnd, '');
    final uri = link.length > _maxLink ? null : Uri.tryParse(link);
    if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) continue;
    if (debug && uri.host == _emulatorHostMachine) return normalLink(link);
    if (shikooSubscriptionDomains.any(
      (domain) => uri.host == domain || uri.host.endsWith('.$domain'),
    )) {
      return normalLink(uri.replace(scheme: 'https').toString());
    }
  }
  return null;
}

String normalLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return link;
  final text = uri.toString();
  final slash = uri.path.length > 1 && uri.path.endsWith('/');
  return slash && !uri.hasQuery && !uri.hasFragment
      ? text.substring(0, text.length - 1)
      : text;
}

ShikooPasteError addFailure(Object error) => switch (error) {
  TimeoutException() => ShikooPasteError.offline,
  DioException(type: DioExceptionType.badResponse, :final response)
      when const {404, 410}.contains(response?.statusCode) =>
    ShikooPasteError.revoked,
  DioException(type: DioExceptionType.badResponse) =>
    ShikooPasteError.unavailable,
  DioException() => ShikooPasteError.offline,
  _ => ShikooPasteError.unavailable,
};

/// [config] from the core's `getConfig`; a provider counts, as its servers arrive later.
bool configHasServers(Map<String, dynamic> config) {
  final providers = config['proxy-providers'];
  if (providers is Map && providers.isNotEmpty) return true;
  final proxies = config['proxies'];
  return proxies is List &&
      proxies.any(
        (proxy) =>
            proxy is! Map || isServer('${proxy['type']}', '${proxy['name']}'),
      );
}
