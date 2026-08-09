import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/schedule.dart';
import '../services/notification_service.dart';

/// 应用全局状态：课程表、课程、设置，以及所有增删改操作。
class AppState extends ChangeNotifier {
  List<Schedule> schedules = [];
  List<Course> courses = [];
  AppSettings settings = AppSettings();
  bool loaded = false;

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

  // ---------- 设置 ----------

  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    await _save();
    notifyListeners();
    _sync();
  }
}
