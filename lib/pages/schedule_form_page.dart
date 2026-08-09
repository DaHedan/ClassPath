import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/schedule.dart';
import '../services/schedule_math.dart';
import '../state/app_state.dart';
import 'building_edit_page.dart';

/// 课程表表单页：名称、总周数、第一周周一日期、一日总节数、
/// 学校楼宇（至少一个，可复制时间段/楼宇）、用餐时间。
class ScheduleFormPage extends StatefulWidget {
  final Schedule? schedule; // null 表示新建

  const ScheduleFormPage({super.key, this.schedule});

  @override
  State<ScheduleFormPage> createState() => _ScheduleFormPageState();
}

class _ScheduleFormPageState extends State<ScheduleFormPage> {
  late final TextEditingController _nameCtrl;
  late int _totalWeeks;
  late DateTime _firstMonday;
  late int _periodsPerDay;
  late List<Building> _buildings;
  late int _lunchAfter;
  late int _dinnerAfter;

  @override
  void initState() {
    super.initState();
    final s = widget.schedule;
    final now = DateTime.now();
    final thisMonday = now.subtract(Duration(days: now.weekday - 1));
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _totalWeeks = s?.totalWeeks ?? 20;
    _firstMonday = s?.firstMonday ?? ScheduleMath.dateOnly(thisMonday);
    _periodsPerDay = s?.periodsPerDay ?? 8;
    _buildings = (s?.buildings ?? []).map((b) => b.copy()).toList();
    _lunchAfter = s?.lunch.afterPeriod ?? 0;
    _dinnerAfter = s?.dinner.afterPeriod ?? 0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _editBuilding(Building building) async {
    final result = await Navigator.push<Building>(
      context,
      MaterialPageRoute(
        builder: (_) => BuildingEditPage(
          building: building,
          otherBuildings: _buildings,
          maxPeriods: _periodsPerDay,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        final i = _buildings.indexOf(building);
        if (i >= 0) _buildings[i] = result;
      });
    }
  }

  Future<void> _addBuilding() async {
    final result = await Navigator.push<Building>(
      context,
      MaterialPageRoute(
        builder: (_) => BuildingEditPage(
          building: Building(name: ''),
          otherBuildings: _buildings,
          maxPeriods: _periodsPerDay,
        ),
      ),
    );
    if (result != null) setState(() => _buildings.add(result));
  }

  void _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请输入课程表名称');
      return;
    }
    if (_buildings.isEmpty) {
      _snack('请至少添加一个楼宇');
      return;
    }
    for (final b in _buildings) {
      if (b.name.trim().isEmpty) {
        _snack('楼宇名称不能为空');
        return;
      }
    }
    final app = context.read<AppState>();
    if (widget.schedule == null) {
      final s = Schedule(
        name: name,
        totalWeeks: _totalWeeks,
        firstMonday: _firstMonday,
        periodsPerDay: _periodsPerDay,
        buildings: _buildings.map((b) => b.copy()).toList(),
        lunch: MealTime(afterPeriod: _lunchAfter, label: '午餐'),
        dinner: MealTime(afterPeriod: _dinnerAfter, label: '晚餐'),
      );
      await app.addSchedule(s);
    } else {
      final s = widget.schedule!.copy()
        ..name = name
        ..totalWeeks = _totalWeeks
        ..firstMonday = _firstMonday
        ..periodsPerDay = _periodsPerDay
        ..buildings = _buildings.map((b) => b.copy()).toList()
        ..lunch = MealTime(afterPeriod: _lunchAfter, label: '午餐')
        ..dinner = MealTime(afterPeriod: _dinnerAfter, label: '晚餐');
      await app.updateSchedule(s);
    }
    if (mounted) {
      // 先等主页完成重建与布局，再退出表单页：
      // 若课程表网格在路由退出动画期间才首次构建/滚动定位，
      // 会与桌面端鼠标事件处理竞争，触发框架的 mouse_tracker 断言。
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.schedule == null ? '新建课程表' : '编辑课程表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '课程表名称 *',
              hintText: '如：2026年春季学期',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _stepperTile(
            theme,
            '总周数（1-53）',
            _totalWeeks,
            1,
            53,
            (v) => setState(() => _totalWeeks = v),
          ),
          _stepperTile(
            theme,
            '一日总节数',
            _periodsPerDay,
            1,
            20,
            (v) => setState(() => _periodsPerDay = v),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('第一周周一的日期'),
            subtitle: Text(ScheduleMath.formatFull(_firstMonday)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _firstMonday,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null)
                setState(() => _firstMonday = ScheduleMath.dateOnly(d));
            },
          ),
          const Divider(height: 32),
          Row(
            children: [
              Text(
                '学校楼宇',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Tooltip(
                message: '把其他课程表的全部楼宇复制过来',
                child: TextButton.icon(
                  onPressed: _copyBuildingsFromSchedule,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('复制楼宇'),
                ),
              ),
              TextButton.icon(
                onPressed: _addBuilding,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加楼宇'),
              ),
            ],
          ),
          if (_buildings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '至少添加一个楼宇，如第一教学楼',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          for (final b in _buildings)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  b.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  b.periodTimes.isEmpty
                      ? '未设置节次时间段'
                      : '${b.periodTimes.length}个时间段 · ${b.periodTimes.first.display}',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => _editBuilding(b),
                trailing: TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => _copyRangesFromBuilding(b),
                  child: const Text('从其他楼宇复制',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
          const Divider(height: 32),
          Text(
            '用餐时间',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _mealDropdown(
            theme,
            '午餐',
            _lunchAfter,
            (v) => setState(() => _lunchAfter = v),
          ),
          _mealDropdown(
            theme,
            '晚餐',
            _dinnerAfter,
            (v) => setState(() => _dinnerAfter = v),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('保存'),
          ),
        ),
      ),
    );
  }

  Widget _stepperTile(
    ThemeData theme,
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  Widget _mealDropdown(
    ThemeData theme,
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        Text(label),
        const Spacer(),
        DropdownButton<int>(
          value: value,
          items: [
            const DropdownMenuItem(value: 0, child: Text('不设置')),
            for (var i = 1; i <= _periodsPerDay; i++)
              DropdownMenuItem(value: i, child: Text('第$i节后')),
          ],
          onChanged: (v) => onChanged(v ?? 0),
        ),
      ],
    );
  }

  Future<void> _copyRangesFromBuilding(Building target) async {
    final others = _buildings.where((b) => b != target).toList();
    if (others.isEmpty) {
      _snack('没有其他楼宇可复制');
      return;
    }
    final picked = await _pickBuilding(others, '选择要复制时间段的楼宇');
    if (picked != null) {
      setState(() {
        target.periodTimes
          ..clear()
          ..addAll(picked.periodTimes.map((e) => e.copy()));
      });
    }
  }

  /// 从其他课程表复制全部楼宇（覆盖当前列表）。
  Future<void> _copyBuildingsFromSchedule() async {
    final schedules = context
        .read<AppState>()
        .schedules
        .where((s) => s.id != widget.schedule?.id)
        .toList();
    if (schedules.isEmpty) {
      _snack('没有其他课程表可复制');
      return;
    }
    final schedule = await _pickFromList<Schedule>(
      context,
      schedules,
      (s) => s.name,
      '选择要复制楼宇的课程表',
    );
    if (schedule == null) return;
    if (schedule.buildings.isEmpty) {
      _snack('该课程表没有楼宇');
      return;
    }
    if (_buildings.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认覆盖'),
          content: Text(
            '将用「${schedule.name}」的 ${schedule.buildings.length} 栋楼宇'
            '替换当前的 ${_buildings.length} 栋楼宇，继续吗？',
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('覆盖')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _buildings = schedule.buildings.map((b) => b.copy()).toList();
    });
  }

  Future<Building?> _pickBuilding(List<Building> list, String title) =>
      _pickFromList<Building>(context, list, (b) => b.name, title);
}

/// 从列表中选取一项的通用对话框。
Future<T?> _pickFromList<T>(
  BuildContext context,
  List<T> items,
  String Function(T) labelOf,
  String title,
) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final item in items)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, item),
            child: Text(labelOf(item)),
          ),
      ],
    ),
  );
}
