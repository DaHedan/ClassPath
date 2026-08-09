import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/course.dart';
import '../services/schedule_math.dart';
import '../state/app_state.dart';
import 'course_form_page.dart';

/// 课程详情页：展示某门课程的全部信息，并可编辑/删除。
///
/// 编辑保存后通过 AppState 监听实时刷新（按 uid 重新解析最新课程对象）。
class CourseDetailPage extends StatelessWidget {
  final Course course;

  const CourseDetailPage({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    // 从全局状态按 uid 重新解析，保证编辑保存后立即显示最新内容。
    final c = app.courses.where((e) => e.uid == course.uid).firstOrNull ??
        course;

    Future<void> delete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除课程'),
          content: Text('确定删除课程「${c.name}」吗？'),
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
      if (ok == true) {
        await app.deleteCourse(c.uid);
        if (context.mounted) Navigator.pop(context);
      }
    }

    final schedule = app.schedules
            .where((s) => s.id == c.scheduleId)
            .firstOrNull ??
        app.activeSchedule;

    void openEdit() {
      final s = schedule;
      if (s == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CourseFormPage(schedule: s, course: c),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: openEdit,
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 头部：颜色 + 名称 + 编号 + 教师
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(c.colorValue),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(c.colorValue)
                                      .computeLuminance() >
                                  0.5
                              ? Colors.black87
                              : Colors.white)),
                      Text(
                        '编号 ${c.id}'
                        '${c.teacher == null || c.teacher!.isEmpty ? '' : ' · ${c.teacher}'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _infoCard(theme, '上课时间', [
            for (final ct in c.classTimes)
              '${ct.weekdayLabel} ${ct.periodLabel}  ${ct.start}-${ct.end}',
          ]),
          const SizedBox(height: 8),
          _infoCard(theme, '上课地点', [
            '总体：${c.location.display.isEmpty ? '未设置' : c.location.display}',
            for (final ct in c.classTimes)
              if (ct.location != null && !ct.location!.isEmpty)
                '${ct.weekdayLabel}${ct.periodLabel}：${ct.location!.display}',
          ]),
          const SizedBox(height: 8),
          _infoCard(theme, '上课周', [ScheduleMath.weeksToText(c.weeks)]),
          const SizedBox(height: 8),
          _infoCard(theme, '提醒', [c.remindText]),
          if (c.exam != null && !c.exam!.isEmpty) ...[
            const SizedBox(height: 8),
            _infoCard(theme, '考试信息', [
              if (c.exam!.date != null)
                '日期：${ScheduleMath.formatFull(c.exam!.date!)}',
              if (c.exam!.timeText != null &&
                  c.exam!.timeText!.isNotEmpty)
                '时间：${c.exam!.timeText}',
              if (c.exam!.location != null &&
                  c.exam!.location!.isNotEmpty)
                '地点：${c.exam!.location}',
              if (c.exam!.seat != null && c.exam!.seat!.isNotEmpty)
                '座位号：${c.exam!.seat}',
            ]),
          ],
          const SizedBox(height: 8),
          if (c.note != null && c.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoCard(theme, '备注', [c.note!]),
          ],
        ],
      ),
    );
  }

  Widget _infoCard(ThemeData theme, String title, List<String> lines) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
  }
}
