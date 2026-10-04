import 'dart:async';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShikooPasteError { empty, notShikoo, revoked, offline }

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
  DioException(type: DioExceptionType.badResponse) => ShikooPasteError.revoked,
  DioException() => ShikooPasteError.offline,
  _ => ShikooPasteError.revoked,
};
