import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/shikoo/engine/controller.dart';

enum ShikooPasteError { empty, notShikoo, revoked, serverDown, offline }

// ponytail: only the test link's domain; needs every domain Sam names, and moves with the panel.
const shikooSubscriptionDomains = ['4g3.uk'];

const shikooDebug = bool.fromEnvironment('SHIKOO_DEBUG');

const _emulatorHostMachine = '10.0.2.2';

const _maxLink = 2048;

final _link = RegExp(r'https?://[^\s‎‏]+', caseSensitive: false);
final _sentenceEnd = RegExp(r'[،.,)»]+$');

String? shikooLink(String text, {bool debug = shikooDebug}) {
  for (final match in _link.allMatches(text)) {
    final link = match[0]!.replaceFirst(_sentenceEnd, '');
    final uri = link.length > _maxLink ? null : Uri.tryParse(link);
    final host = uri?.host ?? '';
    final ours =
        (uri?.scheme == 'https' &&
            shikooSubscriptionDomains.any(
              (domain) => host == domain || host.endsWith('.$domain'),
            )) ||
        (debug && uri?.scheme == 'http' && host == _emulatorHostMachine);
    if (ours) return normalLink(link);
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
      when (response?.statusCode ?? 0) >= 500 =>
    ShikooPasteError.serverDown,
  DioException(type: DioExceptionType.badResponse) => ShikooPasteError.revoked,
  DioException() => ShikooPasteError.offline,
  _ => ShikooPasteError.revoked,
};

final _topLevelKey = RegExp(r'^[^\s-]', multiLine: true);
final _listItem = RegExp(r'^\s*-\s', multiLine: true);
final _itemName = RegExp(r'''name:\s*["']?([^"',}\n]*)''');

bool hasServers(String config) {
  final start = RegExp(r'^proxies:', multiLine: true).firstMatch(config)?.end;
  if (start == null) return false;
  final rest = config.substring(start);
  final section = rest.substring(0, _topLevelKey.firstMatch(rest)?.start);
  return section
      .split(_listItem)
      .skip(1)
      .any((item) => !isInfoRow(_itemName.firstMatch(item)?[1] ?? ''));
}
