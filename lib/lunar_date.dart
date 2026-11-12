import 'package:lunar/lunar.dart';

/// A day in the lunar calendar, worded the way it is said in Taiwan.
class LunarDate {
  LunarDate(DateTime date) : _lunar = Lunar.fromDate(date);

  final Lunar _lunar;

  /// "十月初二", or "閏六月十五" in a leap month.
  String get monthDay {
    final month = _lunar.getMonth();
    return '${month < 0 ? '閏' : ''}${_months[month.abs() - 1]}月'
        '${_day(_lunar.getDay())}';
  }

  /// The year's stem and branch, for example "丙午".
  String get year => _lunar.getYearInGanZhi();

  static String _day(int day) => switch (day) {
    <= 10 => '初${_numbers[day - 1]}',
    < 20 => '十${_numbers[day - 11]}',
    20 => '二十',
    < 30 => '廿${_numbers[day - 21]}',
    _ => '三十',
  };

  static const _numbers = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  static const _months = [
    '正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '十一', '十二', //
  ];
}
