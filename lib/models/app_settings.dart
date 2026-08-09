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

  /// 提醒方式：上方通知弹窗。
  bool notifyBanner;

  /// 提醒方式：锁屏弹窗。
  bool notifyLockScreen;

  /// 提醒方式：声音。
  bool notifySound;

  AppSettings({
    this.activeScheduleId,
    this.mode = TimetableMode.currentWeek,
    this.themeMode = ThemeMode.system,
    this.notifyBanner = true,
    this.notifyLockScreen = true,
    this.notifySound = true,
  });

  AppSettings copyWith({
    String? activeScheduleId,
    bool clearActiveSchedule = false,
    TimetableMode? mode,
    ThemeMode? themeMode,
    bool? notifyBanner,
    bool? notifyLockScreen,
    bool? notifySound,
  }) =>
      AppSettings(
        activeScheduleId: clearActiveSchedule
            ? null
            : (activeScheduleId ?? this.activeScheduleId),
        mode: mode ?? this.mode,
        themeMode: themeMode ?? this.themeMode,
        notifyBanner: notifyBanner ?? this.notifyBanner,
        notifyLockScreen: notifyLockScreen ?? this.notifyLockScreen,
        notifySound: notifySound ?? this.notifySound,
      );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        activeScheduleId: json['activeScheduleId'] as String?,
        mode: json['mode'] == 'semester'
            ? TimetableMode.semester
            : TimetableMode.currentWeek,
        themeMode: _themeFromName(json['themeMode'] as String?),
        notifyBanner: json['notifyBanner'] as bool? ?? true,
        notifyLockScreen: json['notifyLockScreen'] as bool? ?? true,
        notifySound: json['notifySound'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'activeScheduleId': activeScheduleId,
        'mode': mode.name,
        'themeMode': themeMode.name,
        'notifyBanner': notifyBanner,
        'notifyLockScreen': notifyLockScreen,
        'notifySound': notifySound,
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
