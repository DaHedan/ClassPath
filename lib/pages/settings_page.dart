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
          _sectionHeader(theme, '通知'),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('通知设置'),
            subtitle: const Text('通知开关、声音、锁屏显示请到系统设置中管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => NotificationService.instance
                .openSystemNotificationSettings(),
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
