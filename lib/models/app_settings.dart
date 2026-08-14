import 'package:flutter/material.dart';

/// 主页课程表显示模式。
enum TimetableMode {
  /// 单周模式：显示所选周，可选择周次（默认当前周）。
  currentWeek,

  /// 本学期模式：不区分周次，显示整学期课程。
  semester,
}

/// 应用全局设置。
class AppSettings {
  /// 正在使用的课程表 ID。
  String? activeScheduleId;

  /// 主页显示模式。
  TimetableMode mode;

  /// 深浅主题。
  ThemeMode themeMode;

  AppSettings({
    this.activeScheduleId,
    this.mode = TimetableMode.currentWeek,
    this.themeMode = ThemeMode.system,
  });

  AppSettings copyWith({
    String? activeScheduleId,
    bool clearActiveSchedule = false,
    TimetableMode? mode,
    ThemeMode? themeMode,
  }) =>
      AppSettings(
        activeScheduleId: clearActiveSchedule
            ? null
            : (activeScheduleId ?? this.activeScheduleId),
        mode: mode ?? this.mode,
        themeMode: themeMode ?? this.themeMode,
      );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        activeScheduleId: json['activeScheduleId'] as String?,
        mode: json['mode'] == 'semester'
            ? TimetableMode.semester
            : TimetableMode.currentWeek,
        themeMode: _themeFromName(json['themeMode'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'activeScheduleId': activeScheduleId,
        'mode': mode.name,
        'themeMode': themeMode.name,
      };

  static ThemeMode _themeFromName(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
