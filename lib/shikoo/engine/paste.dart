import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';

enum ShikooPasteError { empty, notShikoo, revoked, unavailable, offline }

// ponytail: only the test link's domain; needs every domain Sam names, and moves with the panel.
const shikooSubscriptionDomains = ['4g3.uk'];

const shikooDebug = bool.fromEnvironment('SHIKOO_DEBUG');

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

/// The host in lower case and no closing slash, so one link pasted twice is one service.
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

/// [config] as the core parsed it (`getConfig`): a server besides the panel's info rows, or a
/// provider, whose servers come later.
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
