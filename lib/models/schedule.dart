import '../utils/ids.dart';

/// 节次时间段，如「第1-2节 对应 08:15-09:35」。
class PeriodTime {
  int startPeriod;
  int endPeriod;
  String start; // "08:15"
  String end; // "09:35"

  PeriodTime({
    required this.startPeriod,
    required this.endPeriod,
    required this.start,
    required this.end,
  });

  bool contains(int period) =>
      period >= startPeriod && period <= endPeriod;

  String get label =>
      startPeriod == endPeriod ? '第$startPeriod节' : '第$startPeriod-$endPeriod节';

  String get display => '$label  $start-$end';

  PeriodTime copy() => PeriodTime(
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        start: start,
        end: end,
      );

  factory PeriodTime.fromJson(Map<String, dynamic> json) => PeriodTime(
        startPeriod: json['startPeriod'] as int,
        endPeriod: json['endPeriod'] as int,
        start: json['start'] as String,
        end: json['end'] as String,
      );

  Map<String, dynamic> toJson() => {
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'start': start,
        'end': end,
      };
}

/// 学校楼宇。每栋楼宇可设置若干节次时间段。
class Building {
  String name;
  List<PeriodTime> periodTimes;

  Building({required this.name, List<PeriodTime>? periodTimes})
      : periodTimes = periodTimes ?? [];

  /// 该楼宇在第 [period] 节的时间段，未设置则为 null。
  PeriodTime? timeOf(int period) {
    for (final t in periodTimes) {
      if (t.contains(period)) return t;
    }
    return null;
  }

  Building copy() => Building(
        name: name,
        periodTimes: periodTimes.map((t) => t.copy()).toList(),
      );

  factory Building.fromJson(Map<String, dynamic> json) => Building(
        name: json['name'] as String,
        periodTimes: (json['periodTimes'] as List? ?? [])
            .map((e) => PeriodTime.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'periodTimes': periodTimes.map((t) => t.toJson()).toList(),
      };
}

/// 用餐时间，按节次设置，如「第5节后」。
class MealTime {
  /// 第几节之后用餐；0 表示未设置。
  int afterPeriod;
  String label; // 午餐 / 晚餐

  MealTime({required this.afterPeriod, required this.label});

  bool get enabled => afterPeriod > 0;

  String get display => enabled ? '$label（第$afterPeriod节后）' : '$label（未设置）';

  MealTime copy() => MealTime(afterPeriod: afterPeriod, label: label);

  factory MealTime.fromJson(Map<String, dynamic> json) => MealTime(
        afterPeriod: json['afterPeriod'] as int? ?? 0,
        label: json['label'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'afterPeriod': afterPeriod, 'label': label};
}

/// 调休安排：把 [source] 那天的课用在 [date] 这天。
///
/// 例如国务院规定 2026-10-10（周六）为调休补班日，
/// 学校安排当天按周一（10-05）的课表上课，
/// 则 date=2026-10-10、source=2026-10-05。
class RescheduleDay {
  /// 调休补班日 "YYYY-MM-DD"（实际显示课程的这一天）。
  String date;

  /// 原本日期 "YYYY-MM-DD"（使用这一天的课）。
  String source;

  RescheduleDay({required this.date, required this.source});

  RescheduleDay copy() => RescheduleDay(date: date, source: source);

  factory RescheduleDay.fromJson(Map<String, dynamic> json) => RescheduleDay(
        date: json['date'] as String,
        source: json['source'] as String,
      );

  Map<String, dynamic> toJson() => {'date': date, 'source': source};
}

/// 课程表。
class Schedule {
  String id;
  String name;

  /// 总周数（1-53）。
  int totalWeeks;

  /// 第一周周一的日期（仅日期部分有效）。
  DateTime firstMonday;

  /// 一日总节数。
  int periodsPerDay;

  /// 学校楼宇，至少一个。
  List<Building> buildings;

  MealTime lunch;
  MealTime dinner;

  /// 调休安排：把 source 那天的课用在 date 这天。
  List<RescheduleDay> reschedules;

  Schedule({
    String? id,
    required this.name,
    required this.totalWeeks,
    required this.firstMonday,
    required this.periodsPerDay,
    List<Building>? buildings,
    MealTime? lunch,
    MealTime? dinner,
    List<RescheduleDay>? reschedules,
  })  : id = id ?? genId(),
        buildings = buildings ?? [],
        lunch = lunch ?? MealTime(afterPeriod: 0, label: '午餐'),
        dinner = dinner ?? MealTime(afterPeriod: 0, label: '晚餐'),
        reschedules = reschedules ?? [];

  /// 第一个楼宇的时间段，用于课程表左侧展示默认节次时间。
  Building? get firstBuilding => buildings.isNotEmpty ? buildings.first : null;

  String get info =>
      '共$totalWeeks周 · 每日$periodsPerDay节 · ${buildings.length}栋楼宇';

  Schedule copy() => Schedule(
        id: id,
        name: name,
        totalWeeks: totalWeeks,
        firstMonday: firstMonday,
        periodsPerDay: periodsPerDay,
        buildings: buildings.map((b) => b.copy()).toList(),
        lunch: lunch.copy(),
        dinner: dinner.copy(),
        reschedules: reschedules.map((r) => r.copy()).toList(),
      );

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
        id: json['id'] as String,
        name: json['name'] as String,
        totalWeeks: json['totalWeeks'] as int,
        firstMonday: DateTime.fromMillisecondsSinceEpoch(
            json['firstMonday'] as int),
        periodsPerDay: json['periodsPerDay'] as int,
        buildings: (json['buildings'] as List? ?? [])
            .map((e) => Building.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        lunch: MealTime.fromJson(
            (json['lunch'] as Map? ?? <String, dynamic>{}).cast<String, dynamic>()),
        dinner: MealTime.fromJson(
            (json['dinner'] as Map? ?? <String, dynamic>{}).cast<String, dynamic>()),
        reschedules: (json['reschedules'] as List? ?? [])
            .map((e) => RescheduleDay.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'totalWeeks': totalWeeks,
        'firstMonday': firstMonday.millisecondsSinceEpoch,
        'periodsPerDay': periodsPerDay,
        'buildings': buildings.map((b) => b.toJson()).toList(),
        'lunch': lunch.toJson(),
        'dinner': dinner.toJson(),
        'reschedules': reschedules.map((r) => r.toJson()).toList(),
      };
}
