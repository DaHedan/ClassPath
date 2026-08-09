import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/schedule.dart';

/// 本地存储仓库：使用 SharedPreferences + JSON，数据仅保存在本地。
class Repository {
  static const _kSchedules = 'classpath_schedules';
  static const _kCourses = 'classpath_courses';
  static const _kSettings = 'classpath_settings';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _instance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  static Future<({List<Schedule> schedules, List<Course> courses, AppSettings settings})>
      load() async {
    try {
      final p = await _instance();
      final schedules = _decodeList(p.getString(_kSchedules), Schedule.fromJson);
      final courses = _decodeList(p.getString(_kCourses), Course.fromJson);
      final settingsRaw = p.getString(_kSettings);
      final settings = settingsRaw == null
          ? AppSettings()
          : AppSettings.fromJson(
              (jsonDecode(settingsRaw) as Map).cast<String, dynamic>());
      return (schedules: schedules, courses: courses, settings: settings);
    } catch (_) {
      return (
        schedules: <Schedule>[],
        courses: <Course>[],
        settings: AppSettings()
      );
    }
  }

  static Future<void> save(
    List<Schedule> schedules,
    List<Course> courses,
    AppSettings settings,
  ) async {
    try {
      final p = await _instance();
      await p.setString(
          _kSchedules, jsonEncode(schedules.map((e) => e.toJson()).toList()));
      await p.setString(
          _kCourses, jsonEncode(courses.map((e) => e.toJson()).toList()));
      await p.setString(_kSettings, jsonEncode(settings.toJson()));
    } catch (_) {
      // 本地写入失败时静默处理，避免影响 UI。
    }
  }

  static List<T> _decodeList<T>(
      String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}
