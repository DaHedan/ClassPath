import '../models/schedule.dart';

/// 日期 / 星期 / 周次相关的计算工具。
///
/// 星期以 DateTime.weekday 语义为准：1=周一 ... 7=周日。
class ScheduleMath {
  ScheduleMath._();

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// "YYYY-MM-DD" 格式的日期字符串（用于与节假日数据对齐）。
  static String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 某日期属于课程表的第几周（范围裁剪到 1..totalWeeks）。
  static int weekNumberOf(Schedule s, DateTime now) {
    final diff = dateOnly(now).difference(dateOnly(s.firstMonday)).inDays;
    if (diff < 0) return 1;
    final w = diff ~/ 7 + 1;
    if (w < 1) return 1;
    if (w > s.totalWeeks) return s.totalWeeks;
    return w;
  }

  /// 当前真实所在周（用于「回到本周」）。
  static int currentWeekOfNow(Schedule s) => weekNumberOf(s, DateTime.now());

  /// 第 [week] 周的周一日期。
  static DateTime mondayOf(Schedule s, int week) =>
      dateOnly(s.firstMonday).add(Duration(days: (week - 1) * 7));

  /// 第 [week] 周、星期 [weekday]（1-7）对应的日期。
  static DateTime dateOf(int week, int weekday, Schedule s) =>
      mondayOf(s, week).add(Duration(days: weekday - 1));

  /// 单周日期范围文本，如「8.5-8.11」。
  static String weekRangeText(Schedule s, int week) {
    final mon = mondayOf(s, week);
    final sun = mon.add(const Duration(days: 6));
    return '${_md(mon)}-${_md(sun)}';
  }

  static String _md(DateTime d) => '${d.month}.${d.day}';

  /// 中文日期，如「8月5日」。
  static String formatMd(DateTime d) => '${d.month}月${d.day}日';

  /// 完整日期，如「2026年8月5日 周三」。
  static String formatFull(DateTime d) {
    const weekNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${d.year}年${d.month}月${d.day}日 ${weekNames[d.weekday - 1]}';
  }

  static String weekdayName(int weekday) {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (weekday < 1 || weekday > 7) return '';
    return names[weekday - 1];
  }

  /// 将周列表压缩为文本，如 [1,2,3,5,9,10] -> 「第1-3、5、9-10周」。
  static String weeksToText(List<int> weeks) {
    if (weeks.isEmpty) return '未设置';
    final sorted = List.of(weeks)..sort();
    final parts = <String>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final w = sorted[i];
      if (w == prev + 1) {
        prev = w;
        continue;
      }
      parts.add(start == prev ? '$start' : '$start-$prev');
      start = w;
      prev = w;
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    return '第${parts.join('、')}周';
  }

  /// "HH:mm" -> 分钟数。
  static int timeToMinutes(String s) {
    final p = s.split(':');
    if (p.length != 2) return 0;
    return int.tryParse(p[0])! * 60 + int.tryParse(p[1])!;
  }

  /// 分钟数 -> "HH:mm"。
  static String minutesToTime(int m) {
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }
}
