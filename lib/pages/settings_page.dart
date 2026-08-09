import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';

/// 设置页：主页显示模式、深浅主题、提醒方式。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _sectionHeader(theme, '主页显示'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<TimetableMode>(
              segments: const [
                ButtonSegment(
                  value: TimetableMode.currentWeek,
                  label: Text('单周模式'),
                  icon: Icon(Icons.view_week_outlined),
                ),
                ButtonSegment(
                  value: TimetableMode.semester,
                  label: Text('本学期模式'),
                  icon: Icon(Icons.calendar_month_outlined),
                ),
              ],
              selected: {s.mode},
              onSelectionChanged: (v) =>
                  app.updateSettings(s.copyWith(mode: v.first)),
            ),
          ),
          const SizedBox(height: 8),
          _sectionHeader(theme, '主题'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) =>
                  app.updateSettings(s.copyWith(themeMode: v.first)),
            ),
          ),
          const SizedBox(height: 8),
          _sectionHeader(theme, '提醒方式'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('上方通知弹窗'),
            subtitle: const Text('课程提醒以顶部弹窗形式展示'),
            value: s.notifyBanner,
            onChanged: (v) => app.updateSettings(s.copyWith(notifyBanner: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screen_lock_portrait_outlined),
            title: const Text('锁屏弹窗'),
            subtitle: const Text('在锁屏界面上显示提醒内容'),
            value: s.notifyLockScreen,
            onChanged: (v) =>
                app.updateSettings(s.copyWith(notifyLockScreen: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('声音'),
            subtitle: const Text('提醒时播放声音'),
            value: s.notifySound,
            onChanged: (v) => app.updateSettings(s.copyWith(notifySound: v)),
          ),
          ListTile(
            leading: const Icon(Icons.perm_device_information_outlined),
            title: const Text('授权通知权限'),
            subtitle: const Text('系统通知需要在手机上授予通知权限'),
            onTap: () => NotificationService.instance.requestPermission(),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
      );
}
