import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/shikoo/engine/direct_dns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const doh = 'https://doh.pub/dns-query';

  test('a server name is also asked of plain UDP resolvers, after the '
      'defaults, once however often the config is made', () {
    final once = shikooDns({
      'nameserver': [doh],
      'proxy-server-nameserver': [doh],
    }, <Rule>[]);
    expect(once['proxy-server-nameserver'], [doh, '8.8.8.8', '1.1.1.1']);
    expect(once['nameserver'], [doh]);
    expect(shikooDns(once, <Rule>[])['proxy-server-nameserver'], [
      doh,
      '8.8.8.8',
      '1.1.1.1',
    ]);
  });

  test('a panel that names no server-name resolver keeps falling back to '
      'its nameserver', () {
    expect(
      shikooDns({
        'nameserver': [doh],
      }, <Rule>[]).containsKey('proxy-server-nameserver'),
      isFalse,
    );
  });
}
