import 'dart:async';

import 'package:dio/dio.dart';

enum ShikooPasteError { empty, notShikoo, revoked, offline }

// ponytail: only the test link's domain; needs every domain Sam names, and moves with the panel.
const shikooSubscriptionDomains = ['4g3.uk'];

const shikooDebug = bool.fromEnvironment('SHIKOO_DEBUG');

const _emulatorHostMachine = '10.0.2.2';

final _link = RegExp(r'https?://\S+', caseSensitive: false);

String? shikooLink(String text, {bool debug = shikooDebug}) {
  final link = _link.firstMatch(text)?[0];
  final host = Uri.tryParse(link ?? '')?.host.toLowerCase() ?? '';
  final ours =
      shikooSubscriptionDomains.any(
        (domain) => host == domain || host.endsWith('.$domain'),
      ) ||
      (debug && host == _emulatorHostMachine);
  return ours ? link : null;
}

ShikooPasteError addFailure(Object error) => switch (error) {
  TimeoutException() => ShikooPasteError.offline,
  DioException(type: DioExceptionType.badResponse) => ShikooPasteError.revoked,
  DioException() => ShikooPasteError.offline,
  _ => ShikooPasteError.revoked,
};
