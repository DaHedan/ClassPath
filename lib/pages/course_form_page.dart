import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/course.dart';
import '../models/schedule.dart';
import '../services/color_generator.dart';
import '../services/schedule_math.dart';
import '../state/app_state.dart';
import '../widgets/time_dial_picker.dart';

/// 课程表单页：编号、名称、教师、上课周、上课时间（可多组）、
/// 上课地点（总体 + 单节覆盖）、颜色、提醒、考试信息、备注。
class CourseFormPage extends StatefulWidget {
  final Schedule schedule;
  final Course? course; // null 表示新建

  const CourseFormPage({super.key, required this.schedule, this.course});

  @override
  State<CourseFormPage> createState() => _CourseFormPageState();
}

class _CourseFormPageState extends State<CourseFormPage> {
  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _teacherCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _examLocationCtrl = TextEditingController();
  final _examSeatCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late String _courseId;
  late List<ClassTime> _classTimes;
  late int _buildingIndex; // 总体地点楼宇下标，-1 表示不设置
  late int _colorValue;
  int? _remindMinutes;
  DateTime? _examDate;
  TimeOfDay? _examStart;
  TimeOfDay? _examEnd;

  Schedule get schedule => widget.schedule;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _courseId = c?.id ?? _nextCourseId();
    _idCtrl.text = _courseId;
    _nameCtrl.text = c?.name ?? '';
    _teacherCtrl.text = c?.teacher ?? '';
    _classTimes = c == null
        ? <ClassTime>[]
        : c.classTimes.map((t) => t.copy()).toList();
    final overall = c?.location ?? CourseLocation();
    _buildingIndex = _buildingIndexOf(overall.building);
    _roomCtrl.text = overall.room;
    _colorValue = c?.colorValue ?? _generateColor();
    _remindMinutes = c?.remindMinutes;
    _examDate = c?.exam?.date;
    final examTime = _parseExamTime(c?.exam?.timeText);
    _examStart = examTime.$1;
    _examEnd = examTime.$2;
    _examLocationCtrl.text = c?.exam?.location ?? '';
    _examSeatCtrl.text = c?.exam?.seat ?? '';
    _noteCtrl.text = c?.note ?? '';
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _roomCtrl.dispose();
    _examLocationCtrl.dispose();
    _examSeatCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 自动编号：从 1 递增，跳过已被使用（含自定义）的编号。
  String _nextCourseId() {
    final ids = context.read<AppState>().coursesOf(schedule.id).map((c) => c.id).toSet();
    var n = 1;
    while (ids.contains('$n')) {
      n++;
    }
    return '$n';
  }

  /// 自动生成区别于已有课程的颜色。
  int _generateColor() {
    final avoid = context
        .read<AppState>()
        .coursesOf(schedule.id)
        .map((c) => c.colorValue)
        .toList();
    return ColorGenerator.generate(avoid: avoid).toARGB32();
  }

  int _buildingIndexOf(String name) {
    if (name.isEmpty) return -1;
    final i = schedule.buildings.indexWhere((b) => b.name == name);
    return i < 0 ? -1 : i;
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));

  bool _weeksOverlap(List<int> a, List<int> b) {
    final set = b.toSet();
    for (final w in a) {
      if (set.contains(w)) return true;
    }
    return false;
  }

  /// 某个上课时间的上课周集合；null（全部周）展开为 1..totalWeeks。
  List<int> _weeksOf(ClassTime ct) => ct.weeks == null
      ? [for (var i = 1; i <= schedule.totalWeeks; i++) i]
      : ct.weeks!;

  /// 时间冲突检查：同课程表内，同一（星期,节次段）且上课周有交集即冲突。
  List<String> _findConflicts(AppState app) {
    final result = <String>{};
    final myUid = widget.course?.uid;
    final others =
        app.coursesOf(schedule.id).where((c) => c.uid != myUid).toList();
    bool overlaps(ClassTime a, ClassTime b) =>
        a.weekday == b.weekday &&
        a.startPeriod <= b.endPeriod &&
        b.startPeriod <= a.endPeriod;
    for (final ct in _classTimes) {
      for (final other in others) {
        for (final oct in other.classTimes) {
          if (overlaps(ct, oct) &&
              _weeksOverlap(_weeksOf(ct), _weeksOf(oct))) {
            result.add(
                '与「${other.name}」${ct.weekdayLabel}${ct.periodLabel}上课周重叠');
          }
        }
      }
    }
    for (var i = 0; i < _classTimes.length; i++) {
      for (var j = i + 1; j < _classTimes.length; j++) {
        final a = _classTimes[i];
        final b = _classTimes[j];
        if (overlaps(a, b) && _weeksOverlap(_weeksOf(a), _weeksOf(b))) {
          result.add(
              '「${a.weekdayLabel}${a.periodLabel}」与「${b.weekdayLabel}${b.periodLabel}」上课周重叠');
        }
      }
    }
    return result.toList();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请输入课程名称');
      return;
    }
    final idText = _courseId.trim();
    if (idText.isEmpty) {
      _snack('请输入课程编号');
      return;
    }
    final app = context.read<AppState>();
    final dup = app.coursesOf(schedule.id).any(
        (c) => c.uid != widget.course?.uid && c.id == idText);
    if (dup) {
      _snack('编号「$idText」已被其他课程使用');
      return;
    }
    for (final ct in _classTimes) {
      if (ct.weeks != null && ct.weeks!.isEmpty) {
        _snack('「${ct.weekdayLabel}${ct.periodLabel}」请选择上课周');
        return;
      }
    }
    if (_classTimes.isEmpty) {
      _snack('请至少添加一组上课时间');
      return;
    }

    final conflicts = _findConflicts(app);
    if (conflicts.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('时间冲突'),
          content: Text(conflicts.map((e) => '• $e').join('\n'),
              style: const TextStyle(fontSize: 14, height: 1.6)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('返回修改')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('仍然保存')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if ((_examStart == null) != (_examEnd == null)) {
      _snack('请同时设置考试的开始与结束时间');
      return;
    }
    if (_examStart != null &&
        _examEnd != null &&
        _examEnd!.hour * 60 + _examEnd!.minute <=
            _examStart!.hour * 60 + _examStart!.minute) {
      _snack('考试结束时间需晚于开始时间');
      return;
    }

    final location = CourseLocation(
      building: _buildingIndex >= 0 &&
              _buildingIndex < schedule.buildings.length
          ? schedule.buildings[_buildingIndex].name
          : '',
      room: _roomCtrl.text.trim(),
    );
    final exam = ExamInfo(
      date: _examDate,
      timeText: _examStart != null && _examEnd != null
          ? '${_fmtTime(_examStart!)}-${_fmtTime(_examEnd!)}'
          : null,
      location: _examLocationCtrl.text.trim().isEmpty
          ? null
          : _examLocationCtrl.text.trim(),
      seat:
          _examSeatCtrl.text.trim().isEmpty ? null : _examSeatCtrl.text.trim(),
    );
    final course = Course(
      uid: widget.course?.uid,
      scheduleId: schedule.id,
      id: idText,
      name: name,
      teacher:
          _teacherCtrl.text.trim().isEmpty ? null : _teacherCtrl.text.trim(),
      classTimes: _classTimes.map((t) => t.copy()).toList(),
      location: location,
      colorValue: _colorValue,
      remindMinutes: _remindMinutes,
      exam: exam.isEmpty ? null : exam,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );

    if (widget.course == null) {
      await app.addCourse(course);
    } else {
      await app.updateCourse(course);
    }
    if (mounted) {
      // 先等主页网格完成重建与布局再退出，避免新课程格子
      // 在路由退出动画期间首次构建而触发桌面端 mouse_tracker 断言。
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  // ---------- 各字段的编辑交互 ----------

  Future<void> _pickColor() async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _ColorPickerDialog(current: _colorValue),
    );
    if (result != null) setState(() => _colorValue = result);
  }

  Future<void> _addClassTime() async {
    final result = await showDialog<ClassTime>(
      context: context,
      builder: (_) => _ClassTimeDialog(
        schedule: schedule,
        defaultBuildingIndex: _buildingIndex,
      ),
    );
    if (result != null) {
      // 上课周在对话框内设置：新建默认未选择，需手动勾选。
      setState(() => _classTimes.add(result));
    }
  }

  Future<void> _editClassTime(int index) async {
    final result = await showDialog<ClassTime>(
      context: context,
      builder: (_) => _ClassTimeDialog(
        schedule: schedule,
        initial: _classTimes[index],
        defaultBuildingIndex: _buildingIndex,
      ),
    );
    if (result != null) {
      setState(() => _classTimes[index] = result);
    }
  }

  static const _remindPresets = <int?>[5, 10, 15, 30, 60, 120, 1440];

  static String _remindLabel(int m) {
    if (m >= 1440) return '提前1天';
    if (m >= 60) {
      final h = m ~/ 60;
      final rest = m % 60;
      return rest == 0 ? '提前$h小时' : '提前$h小时$rest分';
    }
    return '提前$m分钟';
  }

  /// 提醒下拉项：预设值 + 自定义值（若不在预设中则动态加入）。
  List<DropdownMenuItem<int?>> _remindItems() {
    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem(value: null, child: Text('不提醒')),
      for (final v in _remindPresets)
        DropdownMenuItem(value: v, child: Text(_remindLabel(v!))),
    ];
    final custom = _remindMinutes;
    if (custom != null && !_remindPresets.contains(custom)) {
      items.add(DropdownMenuItem(
          value: custom, child: Text(_remindLabel(custom))));
    }
    items.add(const DropdownMenuItem(value: -1, child: Text('自定义…')));
    return items;
  }

  Future<int?> _customRemind() async {
    final ctrl = TextEditingController(text: _remindMinutes?.toString() ?? '30');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义提醒时间'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '分钟数',
                  hintText: '如 30',
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('分钟'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < 1 || v > 10080) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('请输入 1-10080 之间的分钟数')));
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _pickExamDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _examDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _examDate = ScheduleMath.dateOnly(d));
  }

  /// 解析已有考试时间文本（"HH:mm-HH:mm"），失败则视为未设置。
  (TimeOfDay?, TimeOfDay?) _parseExamTime(String? text) {
    if (text == null) return (null, null);
    final parts = text.split('-');
    if (parts.length != 2) return (null, null);
    TimeOfDay? parse(String s) {
      final p = s.trim().split(':');
      if (p.length != 2) return null;
      final h = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        return null;
      }
      return TimeOfDay(hour: h, minute: m);
    }

    final a = parse(parts[0]);
    final b = parse(parts[1]);
    if (a == null || b == null) return (null, null);
    return (a, b);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickExamStart() async {
    final t = await showClassPathTimePicker(
      context: context,
      initialTime: _examStart ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (t != null) setState(() => _examStart = t);
  }

  Future<void> _pickExamEnd() async {
    final t = await showClassPathTimePicker(
      context: context,
      initialTime: _examEnd ?? const TimeOfDay(hour: 11, minute: 0),
    );
    if (t != null) setState(() => _examEnd = t);
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buildings = schedule.buildings;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? '添加课程' : '编辑课程'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 编号 + 名称
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _idCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _courseId = v.trim(),
                  decoration: const InputDecoration(
                    labelText: '编号',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '课程名称 *',
                    hintText: '如：高等数学',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _teacherCtrl,
            decoration: const InputDecoration(
              labelText: '教师（选填）',
              hintText: '如：张老师',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // 颜色
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('课程颜色'),
            subtitle: const Text('点击自定义颜色'),
            leading: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(_colorValue),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26),
              ),
            ),
            onTap: _pickColor,
          ),
          const Divider(height: 32),
          // 上课地点（总体）
          Text('上课地点（总体）',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (buildings.isEmpty)
            Text('课程表未设置楼宇，请先编辑课程表',
                style: TextStyle(fontSize: 13, color: theme.colorScheme.error))
          else ...[
            DropdownButtonFormField<int>(
              initialValue: _buildingIndex,
              decoration: const InputDecoration(
                labelText: '楼宇',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: -1, child: Text('不设置')),
                for (var i = 0; i < buildings.length; i++)
                  DropdownMenuItem(value: i, child: Text(buildings[i].name)),
              ],
              onChanged: (v) => setState(() => _buildingIndex = v ?? -1),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roomCtrl,
              decoration: const InputDecoration(
                labelText: '房号 / 教室（选填）',
                hintText: '如：A101',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const Divider(height: 32),
          // 上课时间
          Row(
            children: [
              Text('上课时间 *',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addClassTime,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          if (_classTimes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('至少添加一组上课时间',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.outline)),
            ),
          for (var i = 0; i < _classTimes.length; i++)
            _classTimeCard(theme, _classTimes[i], i),
          const SizedBox(height: 16),
          // 提醒
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('提前提醒'),
            subtitle: const Text('上课前多久提醒'),
            trailing: DropdownButton<int?>(
              value: _remindMinutes,
              underline: const SizedBox.shrink(),
              items: _remindItems(),
              onChanged: (v) async {
                if (v == -1) {
                  final m = await _customRemind();
                  if (m != null) setState(() => _remindMinutes = m);
                } else {
                  setState(() => _remindMinutes = v);
                }
              },
            ),
          ),
          const Divider(height: 32),
          // 考试信息
          Text('考试信息（选填）',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('考试日期'),
            subtitle: Text(_examDate == null
                ? '未设置'
                : ScheduleMath.formatFull(_examDate!)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: _pickExamDate,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('考试开始时间'),
                  subtitle: Text(
                    _examStart == null ? '未设置' : _fmtTime(_examStart!),
                    style: TextStyle(
                      fontSize: 16,
                      color: _examStart == null
                          ? theme.colorScheme.outline
                          : null,
                    ),
                  ),
                  onTap: _pickExamStart,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('-'),
              ),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('考试结束时间'),
                  subtitle: Text(
                    _examEnd == null ? '未设置' : _fmtTime(_examEnd!),
                    style: TextStyle(
                      fontSize: 16,
                      color: _examEnd == null ? theme.colorScheme.outline : null,
                    ),
                  ),
                  onTap: _pickExamEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _examLocationCtrl,
            decoration: const InputDecoration(
              labelText: '考试地点（选填）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _examSeatCtrl,
            decoration: const InputDecoration(
              labelText: '座位号（选填）',
              border: OutlineInputBorder(),
            ),
          ),
          if (_examDate != null ||
              _examStart != null ||
              _examEnd != null ||
              _examLocationCtrl.text.isNotEmpty ||
              _examSeatCtrl.text.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  _examDate = null;
                  _examStart = null;
                  _examEnd = null;
                  _examLocationCtrl.clear();
                  _examSeatCtrl.clear();
                }),
                child: const Text('清除考试信息'),
              ),
            ),
          const Divider(height: 32),
          // 备注
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '备注（选填）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: const Text('保存'),
          ),
        ),
      ),
    );
  }

  Widget _classTimeCard(ThemeData theme, ClassTime ct, int index) {
    final loc = ct.location;
    final weekText = ct.weeks == null
        ? '全部周'
        : ct.weeks!.isEmpty
            ? '未选择'
            : ScheduleMath.weeksToText(ct.weeks!);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            title: Text(
              '${ct.weekdayLabel} ${ct.periodLabel}  ${ct.start}-${ct.end}',
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              loc == null || loc.isEmpty ? '使用总体地点' : '地点：${loc.display}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '编辑',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editClassTime(index),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => setState(() => _classTimes.removeAt(index)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.event_repeat_outlined,
                    size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '上课周：$weekText',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================= 上课时间编辑对话框 =================

class _ClassTimeDialog extends StatefulWidget {
  final Schedule schedule;
  final ClassTime? initial;

  /// 课程总体楼宇下标（-1 表示未设置），作为新上课时间的默认楼宇。
  final int defaultBuildingIndex;

  const _ClassTimeDialog({
    required this.schedule,
    this.initial,
    this.defaultBuildingIndex = -1,
  });

  @override
  State<_ClassTimeDialog> createState() => _ClassTimeDialogState();
}

class _ClassTimeDialogState extends State<_ClassTimeDialog> {
  late int _weekday;
  late int _startPeriod;
  late int _endPeriod;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late int _buildingIndex;
  bool _customLocation = false; // 为本节单独设置地点
  final _roomCtrl = TextEditingController();

  /// 上课周（null = 全部周）。
  List<int>? _weeks;

  static const _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _weekday = i?.weekday ?? 1;
    _startPeriod = i?.startPeriod ?? 1;
    _endPeriod = i?.endPeriod ?? 1;
    _start = _parseTime(i?.start ?? '08:00');
    _end = _parseTime(i?.end ?? '09:40');
    // 上课周：编辑时保留原设置；新建默认未选择，由用户手动勾选。
    _weeks = i?.weeks ?? [];
    final loc = i?.location;
    final buildings = widget.schedule.buildings;
    // 楼宇默认顺序：该节课自带地点楼宇 → 课程总体楼宇 → 第一栋楼。
    int? idx;
    if (loc != null && loc.building.isNotEmpty) {
      idx = buildings.indexWhere((b) => b.name == loc.building);
    }
    _buildingIndex = idx ?? widget.defaultBuildingIndex;
    if (_buildingIndex < 0 || _buildingIndex >= buildings.length) {
      _buildingIndex = buildings.isNotEmpty ? 0 : -1;
    }
    _roomCtrl.text = loc?.room ?? '';
    _customLocation = loc != null && !loc.isEmpty;
    // 新建的上课时间：按所选楼宇与节次段带出时间段。
    if (i == null) _applyBuildingRange(notify: false);
  }

  /// 该节节次段的来源楼宇：单独设置地点时用所选楼宇，否则用课程总体楼宇。
  Building? get _sourceBuilding {
    final buildings = widget.schedule.buildings;
    if (_customLocation) {
      if (_buildingIndex >= 0 && _buildingIndex < buildings.length) {
        return buildings[_buildingIndex];
      }
      return null;
    }
    if (widget.defaultBuildingIndex >= 0 &&
        widget.defaultBuildingIndex < buildings.length) {
      return buildings[widget.defaultBuildingIndex];
    }
    return null;
  }

  /// 节次段选项：优先取楼宇配置的时间段；未被覆盖的节次补单节。
  List<PeriodTime> _periodOptions() {
    final b = _sourceBuilding;
    final covered = <int>{};
    final ranges = <PeriodTime>[];
    if (b != null) {
      for (final r in b.periodTimes) {
        ranges.add(r);
        for (var p = r.startPeriod; p <= r.endPeriod; p++) {
          covered.add(p);
        }
      }
    }
    for (var p = 1; p <= widget.schedule.periodsPerDay; p++) {
      if (!covered.contains(p)) {
        ranges.add(PeriodTime(
            startPeriod: p, endPeriod: p, start: '08:00', end: '09:40'));
      }
    }
    ranges.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    return ranges;
  }

  /// 依据楼宇的时间段（所选节次段）自动填充上课/下课时间。
  void _applyBuildingRange({bool notify = true}) {
    final b = _sourceBuilding;
    if (b == null || b.periodTimes.isEmpty) return;
    PeriodTime? target;
    for (final t in b.periodTimes) {
      if (_startPeriod >= t.startPeriod && _startPeriod <= t.endPeriod) {
        target = t;
        break;
      }
    }
    target ??= b.periodTimes.first;
    void apply() {
      _startPeriod = target!.startPeriod;
      _endPeriod = target!.endPeriod;
      _start = _parseTime(target!.start);
      _end = _parseTime(target!.end);
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _selectRange(PeriodTime r) {
    setState(() {
      _startPeriod = r.startPeriod;
      _endPeriod = r.endPeriod;
      _start = _parseTime(r.start);
      _end = _parseTime(r.end);
    });
  }

  @override
  void dispose() {
    _roomCtrl.dispose();
    super.dispose();
  }

  TimeOfDay _parseTime(String s) {
    final p = s.split(':');
    return TimeOfDay(
      hour: int.tryParse(p[0]) ?? 8,
      minute: int.tryParse(p[1]) ?? 0,
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _min(TimeOfDay t) => t.hour * 60 + t.minute;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickTime(bool isStart) async {
    final t = await showClassPathTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (t != null) {
      setState(() {
        if (isStart) {
          _start = t;
        } else {
          _end = t;
        }
      });
    }
  }

  void _save() {
    if (_min(_end) <= _min(_start)) {
      _snack('下课时间必须晚于上课时间');
      return;
    }
    if (_weeks == null || _weeks!.isEmpty) {
      _snack('请选择上课周');
      return;
    }
    final room = _roomCtrl.text.trim();
    final building = _sourceBuilding?.name ?? '';
    CourseLocation? loc;
    // 仅当开启「为本节单独设置地点」时保存本节地点。
    if (_customLocation && (building.isNotEmpty || room.isNotEmpty)) {
      loc = CourseLocation(building: building, room: room);
    }
    Navigator.pop(
      context,
      ClassTime(
        weekday: _weekday,
        startPeriod: _startPeriod,
        endPeriod: _endPeriod,
        start: _fmt(_start),
        end: _fmt(_end),
        location: loc,
        weeks: _weeks,
      ),
    );
  }

  Future<void> _pickWeeks() async {
    // null（全部周）在对话框里展开为全选。
    final result = await showDialog<List<int>>(
      context: context,
      builder: (_) => _WeeksMultiDialog(
        totalWeeks: widget.schedule.totalWeeks,
        current: _weeks ??
            [for (var i = 1; i <= widget.schedule.totalWeeks; i++) i],
      ),
    );
    if (result != null) {
      setState(() {
        // 选满全部周时归一化为 null（全部周），避免冗余数据。
        _weeks = result.length >= widget.schedule.totalWeeks ? null : result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buildings = widget.schedule.buildings;
    if (buildings.isEmpty) {
      return AlertDialog(
        title: const Text('上课时间'),
        content: const Text('课程表未设置楼宇，无法添加上课时间。请先在课程表设置中添加楼宇。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('知道了')),
        ],
      );
    }
    final ranges = _periodOptions();
    var rangeIndex = ranges.indexWhere(
        (r) => r.startPeriod == _startPeriod && r.endPeriod == _endPeriod);
    if (rangeIndex < 0) rangeIndex = 0;
    return AlertDialog(
      title: const Text('上课时间'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 为本节单独设置地点（开关）
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('为本节单独设置地点'),
                subtitle: Text(
                  _customLocation
                      ? '此节的楼宇与房号将单独保存'
                      : '使用课程总体上课地点',
                  style: const TextStyle(fontSize: 11),
                ),
                value: _customLocation,
                onChanged: (v) {
                  setState(() {
                    _customLocation = v;
                    // 开启时若尚无有效楼宇，回退到课程总体楼宇。
                    if (v) {
                      final buildings = widget.schedule.buildings;
                      if (_buildingIndex < 0 ||
                          _buildingIndex >= buildings.length) {
                        _buildingIndex = widget.defaultBuildingIndex;
                        if (_buildingIndex < 0 ||
                            _buildingIndex >= buildings.length) {
                          _buildingIndex = buildings.isNotEmpty ? 0 : -1;
                        }
                      }
                      _applyBuildingRange();
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              // 仅当单独设置地点时才选择楼宇与房号。
              if (_customLocation) ...[
                DropdownButtonFormField<int>(
                  initialValue: _buildingIndex,
                  decoration: const InputDecoration(labelText: '楼宇'),
                  items: [
                    for (var i = 0; i < buildings.length; i++)
                      DropdownMenuItem(value: i, child: Text(buildings[i].name)),
                  ],
                  onChanged: (v) {
                    _buildingIndex = v ?? 0;
                    _applyBuildingRange();
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _roomCtrl,
                  decoration: const InputDecoration(
                    labelText: '房号 / 教室（选填）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(labelText: '星期几'),
                items: [
                  for (var w = 1; w <= 7; w++)
                    DropdownMenuItem(value: w, child: Text(_weekdayNames[w - 1])),
                ],
                onChanged: (v) => setState(() => _weekday = v ?? 1),
              ),
              const SizedBox(height: 12),
              // 节次段：按所选楼宇的时间段提供，可多节（如第1-3节）。
              DropdownButtonFormField<int>(
                initialValue: rangeIndex,
                decoration: const InputDecoration(labelText: '节次'),
                items: [
                  for (var i = 0; i < ranges.length; i++)
                    DropdownMenuItem(
                        value: i,
                        child: Text(ranges[i].startPeriod == ranges[i].endPeriod
                            ? '第${ranges[i].startPeriod}节'
                            : '第${ranges[i].startPeriod}-${ranges[i].endPeriod}节')),
                ],
                onChanged: (v) {
                  if (v != null) _selectRange(ranges[v]);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('上课时间'),
                      subtitle: Text(_fmt(_start),
                          style: const TextStyle(fontSize: 16)),
                      onTap: () => _pickTime(true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('-'),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('下课时间'),
                      subtitle: Text(_fmt(_end),
                          style: const TextStyle(fontSize: 16)),
                      onTap: () => _pickTime(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 上课周：null 表示全部周。
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('上课周'),
                subtitle: Text(
                  _weeks == null
                      ? '全部周'
                      : _weeks!.isEmpty
                          ? '未选择'
                          : ScheduleMath.weeksToText(_weeks!),
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: TextButton(
                  onPressed: _pickWeeks,
                  child: const Text('选择'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '节次段按楼宇时间段自动带出时间：未单独设置地点时用总体楼宇，可再手动微调',
                style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('确定')),
      ],
    );
  }
}

// ================= 上课周多选对话框 =================

class _WeeksMultiDialog extends StatefulWidget {
  final int totalWeeks;
  final List<int> current;

  const _WeeksMultiDialog({required this.totalWeeks, required this.current});

  @override
  State<_WeeksMultiDialog> createState() => _WeeksMultiDialogState();
}

class _WeeksMultiDialogState extends State<_WeeksMultiDialog> {
  late final Set<int> _selected = Set.of(widget.current);
  final ScrollController _scroll = ScrollController();

  static const int _cols = 5;
  static const double _spacing = 6;

  // 拖动多选状态：按下时记录起点格子与统一状态（选/取消），
  // 移动超过点击容差后视为拖动，滑过的格子都应用该状态；点按由 onTap 切换。
  int? _downWeek;
  bool? _dragValue;
  Offset? _downPos;
  bool _dragging = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setAll(Iterable<int> weeks) => setState(() {
        _selected
          ..clear()
          ..addAll(weeks);
      });

  /// 把 Listener 局部坐标换算为周次；无效位置返回 -1。
  int _weekAt(Offset local) {
    // 格子尺寸：5 列撑满 320 宽，每格约 59.2（间距 6）。
    final cell = (320 - _spacing * (_cols - 1)) / _cols;
    final x = local.dx;
    final y = local.dy + _scroll.offset; // 滚动后内容上移，补回偏移量
    if (x < 0 || y < 0) return -1;
    final col = (x / (cell + _spacing)).floor();
    final row = (y / (cell + _spacing)).floor();
    final index = row * _cols + col;
    return (index >= 0 && index < widget.totalWeeks) ? index + 1 : -1;
  }

  void _applyDrag(Offset local) {
    final week = _weekAt(local);
    if (week < 0) return;
    setState(() {
      if (_dragValue == true) {
        _selected.add(week);
      } else {
        _selected.remove(week);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择上课周'),
      content: SizedBox(
        width: 320,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 快捷操作：全选 / 清空 / 单周 / 双周
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton(
                  onPressed: () => _setAll(
                      [for (var i = 1; i <= widget.totalWeeks; i++) i]),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
                TextButton(
                  onPressed: () => _setAll(
                      [for (var i = 1; i <= widget.totalWeeks; i += 2) i]),
                  child: const Text('单周'),
                ),
                TextButton(
                  onPressed: () => _setAll(
                      [for (var i = 2; i <= widget.totalWeeks; i += 2) i]),
                  child: const Text('双周'),
                ),
              ],
            ),
            const Divider(height: 8),
            Expanded(
              // 拖动滑过格子即可连续多选（配合点选使用）。
              child: Listener(
                onPointerDown: (e) {
                  final w = _weekAt(e.localPosition);
                  _downWeek = w < 0 ? null : w;
                  _downPos = e.localPosition;
                  _dragValue = w < 0 ? null : !_selected.contains(w);
                  _dragging = false;
                },
                onPointerMove: (e) {
                  if (_downWeek == null) return;
                  // 未超过点击容差前仍是点按，交给 InkWell 的 onTap。
                  if (!_dragging) {
                    if ((e.localPosition - _downPos!).distance < 18) return;
                    _dragging = true;
                  }
                  _applyDrag(e.localPosition);
                },
                onPointerUp: (_) {
                  _downWeek = null;
                  _dragValue = null;
                  _downPos = null;
                  _dragging = false;
                },
                onPointerCancel: (_) {
                  _downWeek = null;
                  _dragValue = null;
                  _downPos = null;
                  _dragging = false;
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _cols,
                      mainAxisSpacing: _spacing,
                      crossAxisSpacing: _spacing,
                    ),
                    itemCount: widget.totalWeeks,
                    itemBuilder: (context, index) => _cell(index),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, List.of(_selected)..sort()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _cell(int index) {
    final w = index + 1;
    final selected = _selected.contains(w);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        if (selected) {
          _selected.remove(w);
        } else {
          _selected.add(w);
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$w',
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ================= 颜色选择对话框 =================

class _ColorPickerDialog extends StatefulWidget {
  final int current;

  const _ColorPickerDialog({required this.current});
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSLColor _hsl = HSLColor.fromColor(Color(widget.current));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择颜色'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 52,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _hsl.toColor(),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(height: 12),
              // 预设柔和色板
              SizedBox(
                height: 96,
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: ColorGenerator.palette.length,
                  itemBuilder: (context, index) {
                    final v = ColorGenerator.palette[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          setState(() => _hsl = HSLColor.fromColor(Color(v))),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color(v),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _hsl.toColor().toARGB32() == v
                                ? Colors.black
                                : Colors.black12,
                            width: _hsl.toColor().toARGB32() == v ? 2 : 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              _sliderRow('色相', _hsl.hue, 0, 360, (v) =>
                  setState(() => _hsl = _hsl.withHue(v)), (v) => '${v.round()}°'),
              _sliderRow('饱和', _hsl.saturation, 0, 1, (v) => setState(
                  () => _hsl = _hsl.withSaturation(v)), (v) => '${(v * 100).round()}%'),
              _sliderRow('亮度', _hsl.lightness, 0, 1, (v) => setState(
                  () => _hsl = _hsl.withLightness(v)), (v) => '${(v * 100).round()}%'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hsl.toColor().toARGB32()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String Function(double) labelOf) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 44,
          child: Text(labelOf(value),
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

