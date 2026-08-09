import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/schedule.dart';
import 'schedule_math.dart';

/// 上课提醒通知服务。
///
/// 基于 flutter_local_notifications 的本地通知：
/// - 每次应用启动或数据变化时，为未来两周内的课程预约提醒；
/// - 提醒方式（上方通知弹窗 / 锁屏弹窗 / 声音）来自全局设置；
/// - Web 等不支持的平台会自动静默跳过。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin? _plugin =
      kIsWeb ? null : FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _tzReady = false;

  /// 初始化通知插件（应用启动时调用）。
  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: iosInit,
      );
      await _plugin!.initialize(settings: settings);
      await _plugin!
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 请求通知权限（设置页使用）。
  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _plugin!
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin!
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
  }

  Future<void> _ensureTimezone() async {
    if (_tzReady) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      _tzReady = true;
    } catch (_) {
      try {
        tzdata.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
        _tzReady = true;
      } catch (_) {}
    }
  }

  /// 同步提醒：取消旧提醒，为正在使用的课程表未来两周内的课程预约提醒。
  Future<void> syncReminders(
    List<Schedule> schedules,
    List<Course> courses,
    AppSettings settings,
  ) async {
    if (!_ready) return;
    try {
      await _plugin!.cancelAll();
    } catch (_) {}
    if (schedules.isEmpty) return;
    if (!(settings.notifyBanner ||
        settings.notifyLockScreen ||
        settings.notifySound)) {
      return;
    }

    Schedule? active;
    if (settings.activeScheduleId != null) {
      for (final s in schedules) {
        if (s.id == settings.activeScheduleId) {
          active = s;
          break;
        }
      }
    }
    active ??= schedules.first;

    await _ensureTimezone();

    final now = DateTime.now();
    final thisMonday =
        ScheduleMath.dateOnly(now).subtract(Duration(days: now.weekday - 1));
    // 提醒窗口：本周一 ~ 下周周日。
    final windowEnd = thisMonday.add(const Duration(days: 13));

    var notifId = 1;
    for (final course in courses) {
      if (course.scheduleId != active.id) continue;
      final remind = course.remindMinutes;
      if (remind == null) continue;
      for (final ct in course.classTimes) {
        for (final w in course.weeks) {
          final d = ScheduleMath.dateOf(w, ct.weekday, active);
          if (d.isBefore(thisMonday) || d.isAfter(windowEnd)) continue;
          final hm = ct.start.split(':');
          final classStart =
              DateTime(d.year, d.month, d.day, int.parse(hm[0]), int.parse(hm[1]));
          final fire = classStart.subtract(Duration(minutes: remind));
          if (!fire.isAfter(now)) continue;
          final loc = ct.location?.display ?? course.location.display;
          try {
            await _plugin!.zonedSchedule(
              id: notifId++,
              title: '课途提醒 · ${course.name}',
              body: '还有$remind分钟上课${loc.isEmpty ? '' : '，地点：$loc'}',
              scheduledDate: tz.TZDateTime.from(fire, tz.local),
              notificationDetails: _details(settings, Color(course.colorValue)),
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          } catch (_) {}
        }
      }
    }
  }

  NotificationDetails _details(AppSettings s, Color color) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'course_reminder',
        '上课提醒',
        channelDescription: '课程开始前的上课提醒',
        importance:
            s.notifyBanner ? Importance.high : Importance.defaultImportance,
        priority: s.notifyBanner ? Priority.high : Priority.defaultPriority,
        playSound: s.notifySound,
        visibility: s.notifyLockScreen
            ? NotificationVisibility.public
            : NotificationVisibility.private,
        color: color,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(
        sound: s.notifySound ? 'default' : null,
        presentSound: s.notifySound,
      ),
      macOS: const DarwinNotificationDetails(),
    );
  }
}
