import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/schedule.dart';
import '../services/holiday_service.dart';
import '../services/notification_service.dart';
import '../services/schedule_share_service.dart';
import '../utils/ids.dart';

/// 应用全局状态：课程表、课程、设置，以及所有增删改操作。
class AppState extends ChangeNotifier {
  List<Schedule> schedules = [];
  List<Course> courses = [];
  AppSettings settings = AppSettings();
  bool loaded = false;

  /// 国务院节假日调休缓存：date("YYYY-MM-DD") -> 是否放假。
  /// true 表示放假（自动停课），false 表示调休补班（照常上课）。
  Map<String, bool> holidays = {};

  /// 日期 -> 所属假期名（放假日与补班日归一到主名，如「国庆节」），
  /// 用于把每个补班日精确对应到它所属的假期。
  Map<String, String> holidayNames = {};

  Schedule? get activeSchedule {
    if (schedules.isEmpty) return null;
    final id = settings.activeScheduleId;
    if (id != null) {
      for (final s in schedules) {
        if (s.id == id) return s;
      }
    }
    return schedules.first;
  }

  List<Course> coursesOf(String scheduleId) =>
      courses.where((c) => c.scheduleId == scheduleId).toList();

  Future<void> load() async {
    final data = await Repository.load();
    schedules = data.schedules;
    courses = data.courses;
    settings = data.settings;
    loaded = true;
    notifyListeners();
    NotificationService.instance.syncReminders(schedules, courses, settings);
    // 后台拉取当前课程表覆盖年份的节假日，已有缓存则跳过。
    _refreshActiveScheduleHolidays();
  }

  /// 当前课程表覆盖的年份范围（第一周周一到最后一周日）。
  List<int> _yearsOf(Schedule s) {
    final lastDay =
        s.firstMonday.add(Duration(days: (s.totalWeeks - 1) * 7));
    return [for (var y = s.firstMonday.year; y <= lastDay.year; y++) y];
  }

  /// 拉取指定年份的节假日并刷新缓存（后台执行，网络失败静默降级）。
  Future<void> refreshHolidays(List<int> years) async {
    await HolidayService.ensureYears(years);
    holidays = HolidayService.cache;
    holidayNames = HolidayService.names;
    notifyListeners();
  }

  void _refreshActiveScheduleHolidays() {
    final s = activeSchedule;
    if (s == null) return;
    refreshHolidays(_yearsOf(s));
  }

  Future<void> _save() async =>
      Repository.save(schedules, courses, settings);

  void _sync() =>
      NotificationService.instance.syncReminders(schedules, courses, settings);

  // ---------- 课程表 ----------

  Future<void> addSchedule(Schedule s) async {
    schedules.add(s);
    if (settings.activeScheduleId == null) settings.activeScheduleId = s.id;
    await _save();
    notifyListeners();
    _sync();
  }

  Future<void> updateSchedule(Schedule s) async {
    final i = schedules.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      schedules[i] = s;
      await _save();
      notifyListeners();
      _sync();
    }
  }

  Future<void> deleteSchedule(String id) async {
    schedules.removeWhere((e) => e.id == id);
    courses.removeWhere((c) => c.scheduleId == id);
    if (settings.activeScheduleId == id) {
      settings.activeScheduleId =
          schedules.isNotEmpty ? schedules.first.id : null;
    }
    await _save();
    notifyListeners();
    _sync();
  }

  Future<void> setActiveSchedule(String id) async {
    settings.activeScheduleId = id;
    await _save();
    notifyListeners();
    _sync();
  }

  /// 调整课程表顺序（ReorderableListView 传入的 oldIndex/newIndex）。
  Future<void> reorderSchedules(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex < 0 || oldIndex >= schedules.length) return;
    if (newIndex < 0 || newIndex >= schedules.length) return;
    final s = schedules.removeAt(oldIndex);
    schedules.insert(newIndex, s);
    await _save();
    notifyListeners();
  }

  /// 导入分享的课程表（每张课程表作为新课程表导入）。
  ///
  /// 所有 id 刷新为本地新 id，课程的 scheduleId 指向导入后的新 id；
  /// 与已有课程表同名时自动追加「（副本N）」后缀，避免覆盖。
  Future<ScheduleImportResult> importSchedules(
      List<ScheduleSharePackage> packages) async {
    final names = <String>[];
    var renamed = 0;
    final existing = schedules.map((s) => s.name).toSet();
    for (final p in packages) {
      final newId = genId();
      var name = p.schedule.name;
      var candidate = name;
      var n = 1;
      while (existing.contains(candidate)) {
        candidate = '$name（副本${n++}）';
      }
      if (candidate != name) {
        renamed++;
        name = candidate;
      }
      existing.add(name);

      final s = p.schedule.copy()
        ..id = newId
        ..name = name;
      schedules.add(s);
      for (final c in p.courses) {
        courses.add(c.copy()
          ..uid = genId()
          ..scheduleId = newId);
      }
      names.add(name);
    }
    if (settings.activeScheduleId == null && schedules.isNotEmpty) {
      settings.activeScheduleId = schedules.first.id;
    }
    await _save();
    notifyListeners();
    _sync();
    return ScheduleImportResult(names: names, renamed: renamed);
  }

  // ---------- 课程 ----------

  Future<void> addCourse(Course c) async {
    courses.add(c);
    await _save();
    notifyListeners();
    _sync();
  }

  Future<void> updateCourse(Course c) async {
    final i = courses.indexWhere((e) => e.uid == c.uid);
    if (i >= 0) {
      courses[i] = c;
      await _save();
      notifyListeners();
      _sync();
    }
  }

  Future<void> deleteCourse(String uid) async {
    courses.removeWhere((c) => c.uid == uid);
    await _save();
    notifyListeners();
    _sync();
  }

  /// 调整某课程表下课程的顺序（在全局课程列表中原地移动，保持结构）。
  Future<void> reorderCourses(
      String scheduleId, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final items = coursesOf(scheduleId);
    if (oldIndex < 0 || oldIndex >= items.length) return;
    if (newIndex < 0 || newIndex >= items.length) return;
    final moving = items[oldIndex];
    final from = courses.indexOf(moving);
    final to = courses.indexOf(items[newIndex]);
    courses.removeAt(from);
    // 移除后目标下标可能前移一位。
    courses.insert(to > from ? to - 1 : to, moving);
    await _save();
    notifyListeners();
  }

  // ---------- 设置 ----------

  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    await _save();
    notifyListeners();
    _sync();
  }
}

/// 导入结果：导入的课程表名称列表与因重名而改名的数量。
class ScheduleImportResult {
  final List<String> names;
  final int renamed;

  ScheduleImportResult({required this.names, required this.renamed});
}
