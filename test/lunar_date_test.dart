import 'package:flutter_test/flutter_test.dart';
import 'package:an_xin_ban/lunar_date.dart';

void main() {
  String lunar(int year, int month, int day) =>
      LunarDate(DateTime(year, month, day)).monthDay;

  test('matches the published calendar', () {
    // 2026-11-10 is 丙午年十月初二; 2026-02-17 is Lunar New Year's Day.
    expect(lunar(2026, 11, 10), '十月初二');
    expect(LunarDate(DateTime(2026, 11, 10)).year, '丙午');
    expect(lunar(2026, 2, 17), '正月初一');
    expect(lunar(2026, 2, 16), '十二月廿九');
    expect(LunarDate(DateTime(2026, 2, 16)).year, '乙巳');
    expect(lunar(2025, 1, 29), '正月初一');
  });

  test('says months and days the way they are said in Taiwan', () {
    expect(lunar(2026, 12, 9), '十一月初一');
    expect(lunar(2027, 1, 8), '十二月初一');
    expect(lunar(2026, 11, 18), '十月初十');
    expect(lunar(2026, 11, 23), '十月十五');
    expect(lunar(2026, 11, 28), '十月二十');
    expect(lunar(2026, 11, 29), '十月廿一');
  });

  test('marks leap months', () {
    expect(lunar(2025, 7, 25), '閏六月初一');
    expect(lunar(2025, 8, 23), '七月初一');
  });
}
