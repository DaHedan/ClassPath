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

  Schedule({
    String? id,
    required this.name,
    required this.totalWeeks,
    required this.firstMonday,
    required this.periodsPerDay,
    List<Building>? buildings,
    MealTime? lunch,
    MealTime? dinner,
  })  : id = id ?? genId(),
        buildings = buildings ?? [],
        lunch = lunch ?? MealTime(afterPeriod: 0, label: '午餐'),
        dinner = dinner ?? MealTime(afterPeriod: 0, label: '晚餐');

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
      };
}
