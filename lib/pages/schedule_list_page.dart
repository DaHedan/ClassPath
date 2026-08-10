import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/course.dart';
import '../models/schedule.dart';
import '../services/schedule_math.dart';
import '../state/app_state.dart';
import 'course_detail_page.dart';
import 'schedule_export_page.dart';
import 'schedule_form_page.dart';
import 'schedule_import_page.dart';
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
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
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: app.schedules.isEmpty
          ? Center(
              child: Text(
                '还没有课程表，点击下方按钮新建或导入',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: app.schedules.length,
              // 拖动拇指自绘在每行前，footer（课程面板）不参与排序。
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) =>
                  app.reorderSchedules(oldIndex, newIndex),
              footer: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ActiveCoursesPanel(
                  schedule: app.activeSchedule!,
                  courses: app.coursesOf(app.activeSchedule!.id),
                ),
              ),
              itemBuilder: (context, index) {
                final s = app.schedules[index];
                return Card(
                  key: ValueKey(s.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      // 拖动拇指：按住即可调整课程表顺序。
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.drag_handle,
                            size: 20,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          leading: Radio<String>(
                            value: s.id,
                            groupValue: activeId,
                            onChanged: (_) => app.setActiveSchedule(s.id),
                          ),
                          title: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${s.info} · ${app.coursesOf(s.id).length}门课',
                            style: const TextStyle(fontSize: 12),
                          ),
                          isThreeLine: false,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ScheduleFormPage(schedule: s),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '分享',
                                icon: const Icon(
                                  Icons.share_outlined,
                                  size: 20,
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ScheduleExportPage(
                                      schedule: s,
                                      courses: app.coursesOf(s.id),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '编辑',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ScheduleFormPage(schedule: s),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '删除',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: Colors.red,
                                ),
                                onPressed: () => confirmDelete(s.id, s.name),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      // 两个按钮放在底部栏（不浮动），列表区域结束于按钮上方，
      // 课程面板滚动到底时下边缘不会进入按钮区域。
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FloatingActionButton.extended(
                heroTag: 'fab_new_schedule',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScheduleFormPage()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('新建课程表'),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.extended(
                heroTag: 'fab_import_schedule',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScheduleImportPage()),
                ),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('导入课程表'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 课程表列表底部的卡片：展示选中（主页正在使用）课程表的课程列表，
/// 每门课一行详细信息（编号、教师、上课时间、地点、上课周）。
class _ActiveCoursesPanel extends StatelessWidget {
  final Schedule schedule;
  final List<Course> courses;

  const _ActiveCoursesPanel({required this.schedule, required this.courses});

  /// 地点紧凑文本：楼宇与房号之间不加空格（如「第一教学楼A101」）。
  static String _locText(CourseLocation loc) {
    final b = loc.building.trim();
    final r = loc.room.trim();
    if (b.isEmpty) return r;
    if (r.isEmpty) return b;
    return '$b$r';
  }

  /// 一门课的详细信息（不含课程名）。
  String _detailOf(Course c) {
    final parts = <String>[];
    if (c.id.isNotEmpty) parts.add('编号${c.id}');
    final teacher = (c.teacher ?? '').trim();
    if (teacher.isNotEmpty) parts.add(teacher);
    for (final ct in c.classTimes) {
      final loc = ct.location != null && !ct.location!.isEmpty
          ? ct.location!
          : c.location;
      final l = _locText(loc);
      var t = '${ct.weekdayLabel}${ct.periodLabel} ${ct.start}-${ct.end}';
      if (l.isNotEmpty) t = '$t $l';
      if (ct.weeks != null) t = '$t ${ScheduleMath.weeksToText(ct.weeks!)}';
      parts.add(t);
    }
    return parts.join(' · ');
  }

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
                Icon(
                  Icons.school_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
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
                Text(
                  '${courses.length}门',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (courses.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '该课程表暂无课程',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // 拖动拇指自绘在每行前。
                buildDefaultDragHandles: false,
                itemCount: courses.length,
                onReorder: (oldIndex, newIndex) => context
                    .read<AppState>()
                    .reorderCourses(schedule.id, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final c = courses[index];
                  return Row(
                    key: ValueKey(c.uid),
                    children: [
                      // 拖动拇指：按住即可调整课程顺序。
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.drag_handle,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Expanded(child: _courseRow(context, c)),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 每门课一行：色点 + 名称 + 详细信息，点击进入课程详情。
  Widget _courseRow(BuildContext context, Course c) {
    final theme = Theme.of(context);
    final detail = _detailOf(c);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CourseDetailPage(course: c)),
      ),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Color(c.colorValue),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: c.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (detail.isNotEmpty)
                      TextSpan(
                        text: ' · $detail',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
