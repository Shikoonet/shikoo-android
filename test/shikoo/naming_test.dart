import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('countryOf reads a flag emoji, then a Persian or English word', () {
    expect(countryOf('آلمان ۲'), 'DE');
    expect(countryOf('🇫🇮 Finland 2'), 'FI');
    expect(countryOf('🇹🇷 سرور ویژه'), 'TR');
    expect(countryOf('USA 1'), 'US');
    expect(countryOf('UK'), 'GB');
    expect(countryOf('Ukraine'), isNull);
    expect(countryOf('WireGuard 3'), isNull);
  });

  test('withoutFlags drops flag emoji only', () {
    expect(withoutFlags('🇩🇪 آلمان ۲'), 'آلمان ۲');
    expect(withoutFlags('هلند ۱'), 'هلند ۱');
  });

  test('headerText decodes the base64: form and keeps plain text', () {
    expect(headerText('base64:2KfZhdi02Kg='), 'امشب');
    expect(headerText('https://t.me/x'), 'https://t.me/x');
    expect(headerText('base64:@@'), isNull);
    expect(headerText('  '), isNull);
    expect(headerText(null), isNull);
  });
}
