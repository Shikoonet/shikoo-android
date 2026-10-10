import 'package:fl_clash/shikoo/engine/naming.dart';
import 'package:fl_clash/shikoo/engine/settings.dart';
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
    expect(countryOf('shikoonetturkey'), 'TR');
    expect(countryOf('shikoonetgermany'), 'DE');
    expect(countryOf('shikoonetusa'), 'US');
    expect(countryOf('Jerusalem'), isNull);
    expect(countryOf('Medusa 1'), isNull);
    expect(countryOf('Tuk Tuk'), isNull);
    expect(countryOf('Belarussia'), isNull);
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

  test('usableLink drops a bare t.me and anything that is not a web link', () {
    expect(usableLink('https://t.me/'), isNull);
    expect(usableLink('https://t.me'), isNull);
    expect(usableLink('javascript:alert(1)'), isNull);
    expect(usableLink('t.me/x'), isNull);
    expect(usableLink(null), isNull);
    expect(usableLink('https://t.me/${'x' * 600}'), isNull);
    expect(usableLink('https://t.me/${'پ' * 480}'), isNull);
    expect(usableLink('https://t.me/${'پ' * 50}'), hasLength(lessThan(513)));
    expect(usableLink('https://t.me/shikoo_help'), 'https://t.me/shikoo_help');
    expect(
      usableLink('https://shikoo.example/help'),
      'https://shikoo.example/help',
    );
  });
}
