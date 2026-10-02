import 'package:fl_clash/shikoo/ui/jalali.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gregorian dates map to the Solar Hijri calendar', () {
    final cases = {
      DateTime(2026, 10, 25): (year: 1405, month: 8, day: 3),
      DateTime(2026, 10, 3): (year: 1405, month: 7, day: 11),
      DateTime(2026, 3, 21): (year: 1405, month: 1, day: 1),
      DateTime(2026, 3, 20): (year: 1404, month: 12, day: 29),
      DateTime(2025, 3, 20): (year: 1403, month: 12, day: 30),
      DateTime(2024, 3, 20): (year: 1403, month: 1, day: 1),
      DateTime(2000, 1, 1): (year: 1378, month: 10, day: 11),
    };
    cases.forEach((date, jalali) => expect(toJalali(date), jalali));
  });
}
