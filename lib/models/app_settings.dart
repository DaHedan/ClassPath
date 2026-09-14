import 'package:flutter/material.dart';

/// 主页课程表显示模式。
enum TimetableMode {
  /// 单日模式：聚焦一天，左右滑动切换星期（默认当天）。
  day,

  /// 单周模式：把所选周的一周并排显示，可选择周次（默认当前周）。
  week,

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

  /// 已同意的《用户协议》版本号（手机端首次启动确认）。
  /// 为 null 表示从未同意过；协议内容变更后，版本号不同会再次要求确认。
  String? agreementVersion;

  AppSettings({
    this.activeScheduleId,
    this.mode = TimetableMode.day,
    this.themeMode = ThemeMode.system,
    this.agreementVersion,
  });

  AppSettings copyWith({
    String? activeScheduleId,
    bool clearActiveSchedule = false,
    TimetableMode? mode,
    ThemeMode? themeMode,
    String? agreementVersion,
  }) =>
      AppSettings(
        activeScheduleId: clearActiveSchedule
            ? null
            : (activeScheduleId ?? this.activeScheduleId),
        mode: mode ?? this.mode,
        themeMode: themeMode ?? this.themeMode,
        agreementVersion: agreementVersion ?? this.agreementVersion,
      );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        activeScheduleId: json['activeScheduleId'] as String?,
        mode: _modeFromName(json['mode'] as String?),
        themeMode: _themeFromName(json['themeMode'] as String?),
        agreementVersion: json['agreementVersion'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'activeScheduleId': activeScheduleId,
        'mode': mode.name,
        'themeMode': themeMode.name,
        'agreementVersion': agreementVersion,
      };

  /// 解析持久化的模式名。旧版本的「单周」实为单日聚焦视图，
  /// 其存储值 'currentWeek' 归入单日模式。
  static TimetableMode _modeFromName(String? name) {
    switch (name) {
      case 'semester':
        return TimetableMode.semester;
      case 'week':
        return TimetableMode.week;
      default:
        return TimetableMode.day;
    }
  }

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
