/// Gregorian to Solar Hijri (Jalali), the arithmetic of jdf.scr.ir's `gregorian_to_jalali`.
/// No package in the dependency tree does this; intl only formats the Gregorian calendar.
({int year, int month, int day}) toJalali(DateTime date) {
  const monthStarts = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy = date.year;
  final leapYear = date.month > 2 ? gy + 1 : gy;
  var days =
      355666 +
      365 * gy +
      (leapYear + 3) ~/ 4 -
      (leapYear + 99) ~/ 100 +
      (leapYear + 399) ~/ 400 +
      date.day +
      monthStarts[date.month - 1];
  var year = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  year += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    year += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  return days < 186
      ? (year: year, month: 1 + days ~/ 31, day: 1 + days % 31)
      : (year: year, month: 7 + (days - 186) ~/ 30, day: 1 + (days - 186) % 30);
}
