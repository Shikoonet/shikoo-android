import 'dart:io';

/// Opens every request at the address [_rewrite] gives, so a local server can stand in for an https host.
class RedirectingClient implements HttpClient {
  RedirectingClient(this._inner, this._rewrite);

  final HttpClient _inner;
  final Uri Function(Uri url) _rewrite;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _inner.openUrl(method, _rewrite(url));

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set findProxy(String Function(Uri url)? find) => _inner.findProxy = find;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
