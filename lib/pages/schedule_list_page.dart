import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/course.dart';
import '../models/schedule.dart';
import '../state/app_state.dart';
import 'course_detail_page.dart';
import 'schedule_form_page.dart';
import 'settings_page.dart';

/// 课程表管理页（主页右上角菜单进入）：
/// 添加 / 编辑 / 删除课程表，选择正在使用的课程表，进入设置。
class ScheduleListPage extends StatelessWidget {
  const ScheduleListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final activeId = app.activeSchedule?.id;

    Future<void> confirmDelete(String id, String name) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除课程表'),
          content: Text('确定删除「$name」吗？该课程表下的所有课程将一并删除。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除')),
          ],
        ),
      );
      if (ok == true) await app.deleteSchedule(id);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程表管理'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: app.schedules.isEmpty
          ? Center(
              child: Text('还没有课程表，点击下方按钮创建',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            )
          : ListView.builder(
              // 底部留出空间给「新建课程表」FAB。
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: app.schedules.length + 1,
              itemBuilder: (context, index) {
                // 最后一个条目：选中课程表的课程面板。
                if (index == app.schedules.length) {
                  return _ActiveCoursesPanel(
                    schedule: app.activeSchedule!,
                    courses: app.coursesOf(app.activeSchedule!.id),
                  );
                }
                final s = app.schedules[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Radio<String>(
                      value: s.id,
                      groupValue: activeId,
                      onChanged: (_) => app.setActiveSchedule(s.id),
                    ),
                    title: Text(s.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${s.info} · ${app.coursesOf(s.id).length}门课',
                      style: const TextStyle(fontSize: 12),
                    ),
                    isThreeLine: false,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ScheduleFormPage(schedule: s)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '编辑',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    ScheduleFormPage(schedule: s)),
                          ),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          onPressed: () => confirmDelete(s.id, s.name),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScheduleFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('新建课程表'),
      ),
    );
  }
}

/// 课程表列表底部的卡片：展示选中（主页正在使用）课程表的课程横向列表。
class _ActiveCoursesPanel extends StatelessWidget {
  final Schedule schedule;
  final List<Course> courses;

  const _ActiveCoursesPanel({
    required this.schedule,
    required this.courses,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.school_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '当前课程表「${schedule.name}」的课程',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Text('${courses.length}门',
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 8),
            if (courses.isEmpty)
              Text(
                '该课程表暂无课程',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.outline),
              )
            else
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: courses.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) =>
                      Center(child: _courseChip(context, courses[index])),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 课程名小色块，点击进入课程详情。
  Widget _courseChip(BuildContext context, Course c) {
    final color = Color(c.colorValue);
    final textColor =
        color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CourseDetailPage(course: c)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
