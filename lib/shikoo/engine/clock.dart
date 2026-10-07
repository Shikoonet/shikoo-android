import 'dart:io' show HttpDate, HttpException, HttpHeaders;

import 'package:dio/dio.dart';
import 'package:fl_clash/plugins/app.dart';

// ponytail: raised by hand; the core panics as it loads before mid-2012 (xhttp/browser.go:71).
final shikooClockFloor = DateTime.utc(2026, 9, 1);

bool clockTooEarly(DateTime now) => now.isBefore(shikooClockFloor);

const clockOff = Duration(minutes: 10);

/// Server minus device, zero within [clockOff]; until the next answer, even after a fix offline.
Duration shikooSkew = Duration.zero;

DateTime shikooNow() => DateTime.now().add(shikooSkew);

Duration? _skewOf(String? date) {
  if (date == null) return null;
  try {
    return HttpDate.parse(date).difference(DateTime.now());
  } on HttpException {
    return null;
  }
}

bool _keep(Duration skew) {
  shikooSkew = skew.abs() > clockOff ? skew : Duration.zero;
  return shikooSkew != Duration.zero;
}

void learnClock(String? date) {
  if (_skewOf(date) case final skew?) _keep(skew);
}

final _plain = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
    followRedirects: false,
    validateStatus: (_) => true,
  ),
);

/// Plain http's `Date` decides, as no clock can break it; [url] may hold a token, only its host goes.
Future<bool> clockFailed(Object error, String url) async {
  final reason = '${error is DioException ? error.error : error}';
  final early = reason.contains('not yet valid');
  if (!early && !reason.contains('has expired')) return false;
  final at = Uri.parse(url);
  final Response<void> response;
  try {
    response = await _plain.head<void>(
      Uri(
        scheme: 'http',
        host: at.host,
        port: at.scheme == 'http' ? at.port : null,
      ).toString(),
    );
  } on DioException {
    return early;
  }
  final skew = _skewOf(response.headers.value(HttpHeaders.dateHeader));
  return skew == null ? early : _keep(skew);
}

Future<void> openDateSettings() async {
  await app?.methodChannel.invokeMethod<bool>('openDateSettings');
}
