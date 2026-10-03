abstract final class ShikooLinks {
  static const bot = 'https://t.me/shikoonet_bot';
  static const renew = '$bot?start=renew';
  static const support = 'https://t.me/admiinturbo';
}

String? usableLink(String? url) {
  final uri = url == null || url.length > 512 ? null : Uri.tryParse(url);
  if (uri == null || !{'https', 'http'}.contains(uri.scheme)) return null;
  final bareTelegram =
      {'t.me', 'telegram.me'}.contains(uri.host) &&
      uri.pathSegments.every((part) => part.isEmpty);
  return uri.host.isEmpty || bareTelegram ? null : uri.toString();
}
