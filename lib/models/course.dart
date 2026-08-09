import '../utils/ids.dart';

/// 上课地点：楼宇名称 + 房号/地址。
class CourseLocation {
  String building;
  String room;

  CourseLocation({this.building = '', this.room = ''});

  bool get isEmpty => building.trim().isEmpty && room.trim().isEmpty;

  String get display {
    final b = building.trim();
    final r = room.trim();
    if (b.isEmpty) return r;
    if (r.isEmpty) return b;
    return '$b $r';
  }

  CourseLocation copy() => CourseLocation(building: building, room: room);

  factory CourseLocation.fromJson(Map<String, dynamic> json) => CourseLocation(
        building: json['building'] as String? ?? '',
        room: json['room'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'building': building, 'room': room};
}

/// 上课时间：星期几 + 节次段（如第1-3节）+ 上课时间 + 下课时间，可为该节课单独设置地点。
class ClassTime {
  /// 1=周一 ... 7=周日。
  int weekday;

  /// 节次段：起始节与结束节，可能相等（单节）。
  int startPeriod;
  int endPeriod;

  /// 上课/下课时间，格式 "HH:mm"。
  String start;
  String end;

  /// 单节课的地点覆盖，为空则使用课程总体地点。
  CourseLocation? location;

  ClassTime({
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.start,
    required this.end,
    this.location,
  });

  String get weekdayLabel =>
      ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

  /// 节次段文案，如「第3节」或「第1-3节」。
  String get periodLabel => startPeriod == endPeriod
      ? '第$startPeriod节'
      : '第$startPeriod-$endPeriod节';

  bool get isSinglePeriod => startPeriod == endPeriod;

  ClassTime copy() => ClassTime(
        weekday: weekday,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        start: start,
        end: end,
        location: location?.copy(),
      );

  factory ClassTime.fromJson(Map<String, dynamic> json) {
    // 兼容旧数据：仅存了单节 period。
    final legacyPeriod = json['period'] as int?;
    final start = json['startPeriod'] as int? ?? legacyPeriod ?? 1;
    return ClassTime(
      weekday: json['weekday'] as int,
      startPeriod: start,
      endPeriod: json['endPeriod'] as int? ?? start,
      start: json['start'] as String,
      end: json['end'] as String,
      location: json['location'] == null
          ? null
          : CourseLocation.fromJson(
              (json['location'] as Map).cast<String, dynamic>()),
    );
  }

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'start': start,
        'end': end,
        'location': location?.toJson(),
      };
}

/// 考试信息（选填）。
class ExamInfo {
  DateTime? date;
  String? timeText;
  String? location;
  String? seat;

  ExamInfo({this.date, this.timeText, this.location, this.seat});

  bool get isEmpty =>
      date == null &&
      (timeText == null || timeText!.trim().isEmpty) &&
      (location == null || location!.trim().isEmpty) &&
      (seat == null || seat!.trim().isEmpty);

  factory ExamInfo.fromJson(Map<String, dynamic> json) => ExamInfo(
        date: json['date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
        timeText: json['timeText'] as String?,
        location: json['location'] as String?,
        seat: json['seat'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'date': date?.millisecondsSinceEpoch,
        'timeText': timeText,
        'location': location,
        'seat': seat,
      };
}

/// 课程。
class Course {
  /// 稳定内部 ID，用于本地编辑定位（与用户可见的编号 [id] 区分）。
  String uid;

  /// 所属课程表 ID。
  String scheduleId;

  /// 编号（用户可自定义，默认从 1 开始递增）。
  String id;

  /// 课程名称（必填）。
  String name;

  /// 教师（选填）。
  String? teacher;

  /// 上课周（1-based，必选，可多个）。
  List<int> weeks;

  /// 上课时间组，至少一组。
  List<ClassTime> classTimes;

  /// 总体上课地点（必填），可为某节课单独覆盖。
  CourseLocation location;

  /// 颜色 ARGB 值。
  int colorValue;

  /// 提前提醒分钟数；null 表示不提醒。
  int? remindMinutes;

  /// 考试信息（选填）。
  ExamInfo? exam;

  /// 备注（选填）。
  String? note;

  Course({
    String? uid,
    required this.scheduleId,
    required this.id,
    required this.name,
    this.teacher,
    List<int>? weeks,
    List<ClassTime>? classTimes,
    CourseLocation? location,
    int? colorValue,
    this.remindMinutes,
    this.exam,
    this.note,
  })  : uid = uid ?? genId(),
        weeks = weeks ?? [],
        classTimes = classTimes ?? [],
        location = location ?? CourseLocation(),
        colorValue = colorValue ?? 0xFF7FA8E0;

  String get remindText {
    if (remindMinutes == null) return '不提醒';
    final m = remindMinutes!;
    if (m >= 1440) return '提前一天';
    if (m >= 60) return '提前${m ~/ 60}小时${m % 60 == 0 ? '' : '${m % 60}分'}';
    return '提前$m分钟';
  }

  Course copy() => Course(
        uid: uid,
        scheduleId: scheduleId,
        id: id,
        name: name,
        teacher: teacher,
        weeks: List.of(weeks),
        classTimes: classTimes.map((c) => c.copy()).toList(),
        location: location.copy(),
        colorValue: colorValue,
        remindMinutes: remindMinutes,
        exam: exam,
        note: note,
      );

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        uid: json['uid'] as String? ?? genId(),
        scheduleId: json['scheduleId'] as String,
        id: json['id'] as String,
        name: json['name'] as String,
        teacher: json['teacher'] as String?,
        weeks: (json['weeks'] as List? ?? []).cast<int>(),
        classTimes: (json['classTimes'] as List? ?? [])
            .map((e) => ClassTime.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        location: json['location'] == null
            ? CourseLocation()
            : CourseLocation.fromJson(
                (json['location'] as Map).cast<String, dynamic>()),
        colorValue: json['colorValue'] as int? ?? 0xFF7FA8E0,
        remindMinutes: json['remindMinutes'] as int?,
        exam: json['exam'] == null
            ? null
            : ExamInfo.fromJson((json['exam'] as Map).cast<String, dynamic>()),
        note: json['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'scheduleId': scheduleId,
        'id': id,
        'name': name,
        'teacher': teacher,
        'weeks': weeks,
        'classTimes': classTimes.map((c) => c.toJson()).toList(),
        'location': location.toJson(),
        'colorValue': colorValue,
        'remindMinutes': remindMinutes,
        'exam': exam?.toJson(),
        'note': note,
      };
}
