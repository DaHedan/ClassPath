import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/schedule.dart';
import '../services/schedule_math.dart';
import '../state/app_state.dart';
import '../widgets/timetable_grid.dart';
import '../widgets/week_picker_dialog.dart';
import 'course_detail_page.dart';
import 'course_form_page.dart';
import 'schedule_form_page.dart';
import 'schedule_import_page.dart';
import 'schedule_list_page.dart';
import 'settings_page.dart';

/// 主页：课程表网格。
///
/// - 无课程表时显示「添加课程表」按钮；
/// - 标题为课程表名称（点击切换课程表）；
/// - 网格上方为单周 / 本学期模式切换，单周模式下可选择周次（默认当前周）；
/// - 网格下方为考试安排卡片区；
/// - 右上角菜单进入课程表管理与设置，另有添加快捷入口。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _week;
  final _gridController = TimetableGridController();

  bool get _semesterMode =>
      context.read<AppState>().settings.mode == TimetableMode.semester;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().activeSchedule;
    _week = s == null ? 1 : ScheduleMath.currentWeekOfNow(s);
  }

  @override
  void dispose() {
    _gridController.hScroll.dispose();
    super.dispose();
  }

  // ---------- 交互 ----------

  Future<void> _switchSchedule() async {
    final app = context.read<AppState>();
    if (app.schedules.isEmpty) return;
    final active = app.activeSchedule!;
    final picked = await showDialog<Schedule>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('切换课程表'),
        children: [
          for (final s in app.schedules)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Row(
                children: [
                  Icon(
                    s.id == active.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 18,
                    color: s.id == active.id
                        ? Theme.of(ctx).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(s.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _createSchedule();
            },
            child: Row(
              children: [
                Icon(Icons.add,
                    size: 18, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 10),
                const Text('新建课程表',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _importSchedule();
            },
            child: Row(
              children: [
                Icon(Icons.file_download_outlined,
                    size: 18, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 10),
                const Text('导入课程表',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null && picked.id != active.id) {
      await app.setActiveSchedule(picked.id);
      if (mounted) {
        setState(() => _week = ScheduleMath.currentWeekOfNow(picked));
      }
    }
  }

  Future<void> _createSchedule() async {
    final app = context.read<AppState>();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScheduleFormPage()),
    );
    if (mounted) {
      final s = app.activeSchedule;
      setState(() => _week = s == null ? 1 : ScheduleMath.currentWeekOfNow(s));
    }
  }

  /// 从主页弹窗进入导入页，导入后刷新当前周。
  Future<void> _importSchedule() async {
    final app = context.read<AppState>();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScheduleImportPage()),
    );
    if (mounted) {
      final s = app.activeSchedule;
      setState(() => _week = s == null ? 1 : ScheduleMath.currentWeekOfNow(s));
    }
  }

  Future<void> _switchWeek() async {
    final app = context.read<AppState>();
    final s = app.activeSchedule;
    if (s == null) return;
    final w = await showWeekPicker(
      context,
      totalWeeks: s.totalWeeks,
      current: _week,
      todayWeek: ScheduleMath.currentWeekOfNow(s),
    );
    if (w != null && mounted) setState(() => _week = w);
  }

  void _addCourse() {
    final app = context.read<AppState>();
    final s = app.activeSchedule;
    if (s == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourseFormPage(schedule: s)),
    );
  }

  void _openCourse(Course course, ClassTime time) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourseDetailPage(course: course)),
    );
  }

  void _openCourseDetail(Course course) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourseDetailPage(course: course)),
    );
  }

  void _openList() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const ScheduleListPage()));

  void _openSettings() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const SettingsPage()));

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final schedule = app.activeSchedule;
    if (schedule == null) return _buildEmpty(context);
    return _buildTimetable(context, app, schedule);
  }

  /// 空状态：还没有课程表。
  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('课途'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'manage') _openList();
              if (v == 'settings') _openSettings();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'manage', child: Text('课程表管理')),
              PopupMenuItem(value: 'settings', child: Text('设置')),
            ],
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_view_week_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('还没有课程表',
                style: TextStyle(
                    fontSize: 16, color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('创建课程表后即可开始排课',
                style:
                    TextStyle(fontSize: 13, color: theme.colorScheme.outline)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScheduleFormPage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('添加课程表'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _importSchedule,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导入课程表'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetable(
      BuildContext context, AppState app, Schedule schedule) {
    final theme = Theme.of(context);
    final courses = app.coursesOf(schedule.id);

    // 考试列表：单周模式只显示所选周的考试，本学期模式显示全部，按日期排序。
    final examCourses = courses.where((c) {
      final e = c.exam;
      if (e == null || e.isEmpty || e.date == null) return false;
      if (_semesterMode) return true;
      return ScheduleMath.weekNumberOf(schedule, e.date!) == _week;
    }).toList()
      // 考试安排按时间排序：先日期，同一天的再按考试开始时间，早的在上。
      ..sort((a, b) {
        final c = a.exam!.date!.compareTo(b.exam!.date!);
        if (c != 0) return c;
        return _examStartMinutes(a.exam!)
            .compareTo(_examStartMinutes(b.exam!));
      });

    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(schedule),
        actions: [
          IconButton(
            tooltip: '添加课程',
            icon: const Icon(Icons.add),
            onPressed: _addCourse,
          ),
          PopupMenuButton<String>(
            tooltip: '菜单',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'manage') _openList();
              if (v == 'settings') _openSettings();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'manage', child: Text('课程表管理')),
              PopupMenuItem(value: 'settings', child: Text('设置')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildModeBar(theme, schedule),
          Expanded(
            child: TimetableGrid(
              schedule: schedule,
              courses: courses,
              week: _week,
              semesterMode: _semesterMode,
              controller: _gridController,
              onCourseTap: _openCourse,
              holidays: app.holidays,
            ),
          ),
          _ExamSection(
            courses: examCourses,
            onCourseTap: _openCourseDetail,
          ),
        ],
      ),
    );
  }

  /// 标题：课程表名称（点击切换）。
  Widget _buildTitle(Schedule schedule) {
    return InkWell(
      onTap: _switchSchedule,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              schedule.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }

  /// 网格上方的模式切换条：单周 / 本学期，单周模式下显示周次选择。
  Widget _buildModeBar(ThemeData theme, Schedule schedule) {
    final app = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          SegmentedButton<TimetableMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: TimetableMode.currentWeek,
                label: Text('单周模式'),
                icon: Icon(Icons.view_week_outlined, size: 16),
              ),
              ButtonSegment(
                value: TimetableMode.semester,
                label: Text('本学期模式'),
                icon: Icon(Icons.calendar_month_outlined, size: 16),
              ),
            ],
            selected: {app.settings.mode},
            onSelectionChanged: (v) =>
                app.updateSettings(app.settings.copyWith(mode: v.first)),
          ),
          if (!_semesterMode) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: _switchWeek,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.today_outlined,
                        size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '第$_week周 · ${ScheduleMath.weekRangeText(schedule, _week)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        size: 18, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 解析考试时间文本（"HH:mm-HH:mm"）的开始分钟数；无法解析返回 0，
/// 用于同日考试再按开始时间排序。
int _examStartMinutes(ExamInfo e) {
  final t = e.timeText;
  if (t == null || t.isEmpty) return 0;
  final parts = t.split('-').first.trim().split(':');
  if (parts.length != 2) return 0;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return 0;
  return h * 60 + m;
}

/// 主页底部的考试安排卡片区：单周模式下已按所选周过滤。
class _ExamSection extends StatelessWidget {
  final List<Course> courses;
  final ValueChanged<Course> onCourseTap;

  const _ExamSection({required this.courses, required this.onCourseTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_outlined,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '考试安排',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (courses.isEmpty)
            Text(
              '暂无考试安排',
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.outline),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final c in courses) _examCard(theme, c),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _examCard(ThemeData theme, Course c) {
    final e = c.exam!;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onCourseTap(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (e.date != null) ScheduleMath.formatFull(e.date!),
                        if (e.timeText != null && e.timeText!.isNotEmpty)
                          e.timeText!,
                        if (e.location != null && e.location!.isNotEmpty)
                          e.location!,
                        if (e.seat != null && e.seat!.isNotEmpty)
                          '座位号 ${e.seat!}',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
