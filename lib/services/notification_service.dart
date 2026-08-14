import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
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
///   Windows 计划通知系统限制「3 天过期」，故 Windows 只预约 3 天内的
///   提醒（下次启动会重新排满）；
/// - 通知的开关、声音、锁屏显示等由系统通知设置统一管理
///   （Android 通知渠道 / Windows 系统 Toast / iOS 系统设置），
///   应用内不再提供重复开关；
/// - Web 等不支持的平台会自动静默跳过。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// 与 Android 原生（MainActivity）通信，打开系统通知设置页。
  static const MethodChannel _androidChannel =
      MethodChannel('classpath/share');

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
        // Windows 系统 Toast：未打包 exe 也会在注册表注册 AUMID 后正常弹窗。
        windows: WindowsInitializationSettings(
          appName: '课途',
          appUserModelId: 'DaHedan.ClassPath',
          guid: 'a3f8c1d2-9b4e-4c5a-8d6f-1e2a3b4c5d6e',
        ),
      );
      await _plugin!.initialize(settings: settings);
      final androidImpl = _plugin!
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      // 显式创建通知渠道：让系统「应用信息 → 通知」里立刻出现
      // 「上课提醒」类别，用户可在此管理声音/锁屏等。
      try {
        await androidImpl?.createNotificationChannel(
          const AndroidNotificationChannel(
            'course_reminder',
            '上课提醒',
            description: '课程开始前的上课提醒',
            importance: Importance.high,
            playSound: true,
          ),
        );
      } catch (e) {
        debugPrint('[Notification] create channel failed: $e');
      }
      _ready = true;
      debugPrint('[Notification] initialized, ready=$_ready');
    } catch (e) {
      _ready = false;
      debugPrint('[Notification] initialize failed: $e');
    }
  }

  /// 请求通知权限（iOS/macOS 使用；Android 引导到系统通知设置）。
  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _plugin!
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {}
  }

  /// 打开系统通知设置：
  /// - Android：跳转本应用「应用信息」页（部分 ROM 直接进通知设置页
  ///   会缺横幅/锁屏/声音开关，故走应用信息页与系统设置路径一致）；
  /// - iOS/macOS：重新请求权限；
  /// - Windows：跳转系统「通知和操作」设置页管理 Toast 开关
  ///   （无法像 Android 那样直接定位到本应用的开关）。
  Future<void> openSystemNotificationSettings() async {
    if (!_ready) return;
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      try {
        await _androidChannel.invokeMethod('openNotificationSettings');
      } catch (_) {}
    } else if (Platform.isIOS || Platform.isMacOS) {
      await requestPermission();
    } else if (Platform.isWindows) {
      try {
        await Process.start(
          'cmd',
          ['/c', 'start', 'ms-settings:notifications'],
        );
      } catch (_) {}
    }
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
    debugPrint('[Notification] sync: schedules=${schedules.length} '
        'courses=${courses.length} ready=$_ready');
    try {
      await _plugin!.cancelAll();
    } catch (_) {}
    if (schedules.isEmpty) return;

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
    // Windows 计划通知默认从送达之日起 3 天过期（微软官方限制），超出会被
    // 系统静默丢弃；而每次启动/数据变更都会重排提醒，因此 Windows 只预约
    // 3 天内的提醒即可覆盖，其余平台仍按两周窗口预约。
    final horizon =
        Platform.isWindows ? now.add(const Duration(days: 3)) : windowEnd;

    var notifId = 1;
    var scheduled = 0;
    var skipped = 0;
    for (final course in courses) {
      if (course.scheduleId != active.id) continue;
      final remind = course.remindMinutes;
      if (remind == null) continue;
      for (final ct in course.classTimes) {
        final weeks = ct.weeks ??
            [for (var i = 1; i <= active.totalWeeks; i++) i];
        for (final w in weeks) {
          final d = ScheduleMath.dateOf(w, ct.weekday, active);
          if (d.isBefore(thisMonday) || d.isAfter(windowEnd)) continue;
          final hm = ct.start.split(':');
          final classStart = DateTime(
              d.year, d.month, d.day, int.parse(hm[0]), int.parse(hm[1]));
          final fire = classStart.subtract(Duration(minutes: remind));
          if (!fire.isAfter(now)) continue;
          if (fire.isAfter(horizon)) {
            // Windows 3 天外 / 两周窗口外的提醒由下次启动重排覆盖。
            skipped++;
            continue;
          }
          final loc = ct.location?.display ?? course.location.display;
          await _scheduleOne(
            id: notifId++,
            title: '课途提醒 · ${course.name}',
            body: '还有$remind分钟上课${loc.isEmpty ? '' : '，地点：$loc'}',
            scheduledDate: tz.TZDateTime.from(fire, tz.local),
            color: Color(course.colorValue),
          );
          scheduled++;
        }
      }
    }
    debugPrint('[Notification] sync done: scheduled=$scheduled '
        'skipped(超期未排)=$skipped');
  }

  /// 预约一条提醒。
  ///
  /// Android 12+ 若系统关闭了「闹钟和提醒」精确闹钟权限，插件会抛
  /// `exact_alarms_not_permitted`，此时自动退回系统自动调度（仍会提醒，
  /// 但可能延迟几分钟）；下次启动若权限恢复会重新用精确闹钟。
  Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required Color color,
  }) async {
    try {
      await _plugin!.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: _details(color),
        // 使用精确闹钟，确保到点准时提醒。Android 12+ 需要
        // USE_EXACT_ALARM 权限（已在 Manifest 声明），Android 11
        // 及以下无需任何权限即可精确触发。
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') {
        debugPrint('[Notification] schedule failed(id=$id): $e');
        return;
      }
      debugPrint('[Notification] 精确闹钟被限制(id=$id)，退回系统调度');
      try {
        await _plugin!.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: _details(color),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e2) {
        debugPrint('[Notification] schedule failed(id=$id): $e2');
      }
    } catch (e) {
      debugPrint('[Notification] schedule failed(id=$id): $e');
    }
  }

  /// 通知渠道与样式：Android 渠道创建后，声音/锁屏显示等由用户在
  /// 系统「应用信息 → 通知」中调整；Windows 走系统 Toast 默认样式。
  NotificationDetails _details(Color color) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'course_reminder',
        '上课提醒',
        channelDescription: '课程开始前的上课提醒',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        visibility: NotificationVisibility.public,
        color: color,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
  }
}
