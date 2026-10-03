import 'dart:convert';

const _countryWords = {
  'DE': ['آلمان', 'germany'],
  'FI': ['فنلاند', 'finland'],
  'NL': ['هلند', 'netherlands', 'holland'],
  'US': ['آمریکا', 'امریکا', 'usa', 'america', 'united states'],
  'GB': ['انگلیس', 'انگلستان', 'بریتانیا', 'uk', 'england', 'united kingdom'],
  'TR': ['ترکیه', 'turkey', 'türkiye'],
  'IT': ['ایتالیا', 'italy'],
  'FR': ['فرانسه', 'france'],
  'CA': ['کانادا', 'canada'],
  'SE': ['سوئد', 'sweden'],
  'AE': ['امارات', 'uae', 'emirates'],
  'AM': ['ارمنستان', 'armenia'],
  'RU': ['روسیه', 'russia'],
  'JP': ['ژاپن', 'japan'],
  'SG': ['سنگاپور', 'singapore'],
};

final _flagEmoji = RegExp('[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true);
final _wordBreak = RegExp(r'[^\p{L}]+', unicode: true);

/// ISO 3166 code from a flag emoji in the name, else from a Persian or English country word,
/// also at the end of a run-together word as in the panel's `shikoonetturkey`.
String? countryOf(String name) {
  final flag = _flagEmoji.firstMatch(name)?[0];
  if (flag != null) {
    return String.fromCharCodes(flag.runes.map((r) => r - 0x1F1A5));
  }
  final lower = name.toLowerCase();
  final words = lower.split(_wordBreak).toSet();
  for (final MapEntry(key: code, value: names) in _countryWords.entries) {
    if (names.any(
      (n) => n.contains(' ')
          ? lower.contains(n)
          : words.any((word) => word.endsWith(n)),
    )) {
      return code;
    }
  }
  return null;
}

String withoutFlags(String name) => name.replaceAll(_flagEmoji, '').trim();

/// Panels send some header values as `base64:<utf-8 text>`, so non-ASCII text survives HTTP.
String? headerText(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  const prefix = 'base64:';
  if (!value.startsWith(prefix)) return value.trim();
  try {
    return utf8.decode(base64.decode(value.substring(prefix.length).trim()));
  } on FormatException {
    return null;
  }
}
