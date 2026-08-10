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
  late int? _totalWeeks; // null 表示未设置
  late DateTime? _firstMonday; // null 表示未设置
  late int? _periodsPerDay; // null 表示未设置
  late List<Building> _buildings;
  late int _lunchAfter;
  late int _dinnerAfter;
  late List<RescheduleDay> _reschedules; // 调休安排：补班日 -> 使用原本哪天的课

  @override
  void initState() {
    super.initState();
    final s = widget.schedule;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _totalWeeks = s?.totalWeeks;
    _firstMonday = s?.firstMonday;
    _periodsPerDay = s?.periodsPerDay;
    _buildings = (s?.buildings ?? []).map((b) => b.copy()).toList();
    _lunchAfter = s?.lunch.afterPeriod ?? 0;
    _dinnerAfter = s?.dinner.afterPeriod ?? 0;
    _reschedules = (s?.reschedules ?? []).map((r) => r.copy()).toList();
    // 进入表单即后台拉取覆盖年份的节假日（已缓存年份直接跳过），
    // 供下方「调休安排」展示补班日。
    _refreshHolidays();
  }

  /// 按当前第一周周一与总周数覆盖的年份拉取节假日（后台执行，失败静默）。
  /// 新建时两者未设置则跳过。
  void _refreshHolidays() {
    final first = _firstMonday;
    final total = _totalWeeks;
    if (first == null || total == null) return;
    final lastDay = first.add(Duration(days: (total - 1) * 7));
    final years = [
      for (var y = first.year; y <= lastDay.year; y++) y
    ];
    context.read<AppState>().refreshHolidays(years);
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
          maxPeriods: _periodsPerDay ?? 20,
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
          maxPeriods: _periodsPerDay ?? 20,
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
    final totalWeeks = _totalWeeks;
    final firstMonday = _firstMonday;
    final periodsPerDay = _periodsPerDay;
    if (totalWeeks == null) {
      _snack('请选择总周数');
      return;
    }
    if (firstMonday == null) {
      _snack('请选择第一周周一的日期');
      return;
    }
    if (periodsPerDay == null) {
      _snack('请设置一日总节数');
      return;
    }
    final app = context.read<AppState>();
    // 调休安排只保留落在本课程表时间范围内的项（第一周周一起 总周数*7 天内）。
    final reschedules = _reschedules
        .where((r) {
          final diff = ScheduleMath.dateOnly(DateTime.parse(r.date))
              .difference(firstMonday)
              .inDays;
          return diff >= 0 && diff < totalWeeks * 7;
        })
        .map((r) => r.copy())
        .toList();
    if (widget.schedule == null) {
      final s = Schedule(
        name: name,
        totalWeeks: totalWeeks,
        firstMonday: firstMonday,
        periodsPerDay: periodsPerDay,
        buildings: _buildings.map((b) => b.copy()).toList(),
        lunch: MealTime(afterPeriod: _lunchAfter, label: '午餐'),
        dinner: MealTime(afterPeriod: _dinnerAfter, label: '晚餐'),
        reschedules: reschedules,
      );
      await app.addSchedule(s);
    } else {
      final s = widget.schedule!.copy()
        ..name = name
        ..totalWeeks = totalWeeks
        ..firstMonday = firstMonday
        ..periodsPerDay = periodsPerDay
        ..buildings = _buildings.map((b) => b.copy()).toList()
        ..lunch = MealTime(afterPeriod: _lunchAfter, label: '午餐')
        ..dinner = MealTime(afterPeriod: _dinnerAfter, label: '晚餐')
        ..reschedules = reschedules;
      await app.updateSchedule(s);
    }
    // 新建或修改课程表（第一周周一 / 总周数）后，拉取覆盖年份的国务院
    // 节假日调休数据（后台执行；已缓存年份直接跳过，失败静默降级）。
    final lastDay = firstMonday.add(Duration(days: (totalWeeks - 1) * 7));
    final years = [
      for (var y = firstMonday.year; y <= lastDay.year; y++) y
    ];
    app.refreshHolidays(years);
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
    final app = context.watch<AppState>();
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
            '总周数',
            _totalWeeks,
            1,
            53,
            (v) {
              setState(() => _totalWeeks = v);
              _refreshHolidays();
            },
          ),
          _stepperTile(
            theme,
            '一日总节数',
            _periodsPerDay,
            1,
            20,
            (v) => setState(() {
              _periodsPerDay = v;
              // 餐后节数超出新范围时重置为「不设置」。
              if (_lunchAfter > v) _lunchAfter = 0;
              if (_dinnerAfter > v) _dinnerAfter = 0;
            }),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('第一周周一的日期'),
            subtitle: Text(
                _firstMonday == null ? '未设置' : ScheduleMath.formatFull(_firstMonday!)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _firstMonday ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                // 第一周周一只能是周一。
                selectableDayPredicate: (day) => day.weekday == DateTime.monday,
              );
              if (d != null) {
                setState(() => _firstMonday = ScheduleMath.dateOnly(d));
                _refreshHolidays();
              }
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
          const Divider(height: 32),
          _rescheduleSection(theme, app),
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
    int? value,
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
          onPressed:
              value != null && value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 52,
          child: value == null
              ? Text(
                  '未设置',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.outline),
                )
              : Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value != null && value < max
              ? () => onChanged(value + 1)
              : value == null
                  ? () => onChanged(min)
                  : null,
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
        // 固定宽度，避免选中文字长度变化导致选项位置左右移动。
        SizedBox(
          width: 110,
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: 0, child: Text('不设置')),
              for (var i = 1; i <= (_periodsPerDay ?? 0); i++)
                DropdownMenuItem(value: i, child: Text('第$i节后')),
            ],
            onChanged: (v) => onChanged(v ?? 0),
          ),
        ),
      ],
    );
  }

  /// 调休安排区块：列出本课程表时间范围内的周末补班日，
  /// 为每个补班日选择「当天使用原本（无调休时）哪天的课」——
  /// 可选项为该课程表涵盖的所有放假日。
  Widget _rescheduleSection(ThemeData theme, AppState app) {
    final firstMonday = _firstMonday;
    final totalWeeks = _totalWeeks;
    if (firstMonday == null || totalWeeks == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '调休安排',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '请先设置「第一周周一的日期」与「总周数」，'
            '再查看和安排放假停课与补班搬课',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
          ),
        ],
      );
    }
    final lastDay =
        firstMonday.add(Duration(days: (totalWeeks - 1) * 7 + 6));
    final first = ScheduleMath.dateOnly(firstMonday);
    final last = ScheduleMath.dateOnly(lastDay);
    // 课程表范围内的所有放假日，作为每个补班日可搬的「原本那天」选项。
    final restDays = app.holidays.entries
        .where((e) => e.value)
        .map((e) => DateTime.parse(e.key))
        .where((d) => !d.isBefore(first) && !d.isAfter(last))
        .toList()
      ..sort();
    // 补班日（国务院数据中值为 false 的日期）都是周末，工作日无需搬课。
    final weekendDays = app.holidays.entries
        .where((e) => !e.value)
        .map((e) => DateTime.parse(e.key))
        .where((d) => !d.isBefore(first) && !d.isAfter(last) && d.weekday >= 6)
        .toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '调休安排',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '放假日期自动停课；周末补班日可选择沿用本学期任意放假日期的课表上课',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        if (app.holidays.isEmpty)
          Text(
            '正在获取节假日调休数据…（保存课程表后也会自动拉取）',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
          )
        else if (weekendDays.isEmpty || restDays.isEmpty)
          Text(
            '这个学期没有需要安排的补班日',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
          )
        else
          for (final d in weekendDays) _rescheduleTile(theme, d, restDays),
      ],
    );
  }

  /// 单个补班日的「搬课」设置行。[restDays] 为该课程表涵盖的全部
  /// 放假日（可搬的「原本那天」选项）。
  Widget _rescheduleTile(
      ThemeData theme, DateTime d, List<DateTime> restDays) {
    final dateStr = ScheduleMath.dateStr(d);
    // 调用方已保证 _firstMonday 非空（未设置时整个区块都不渲染）。
    final week = d.difference(_firstMonday!).inDays ~/ 7 + 1;
    final optionValues =
        restDays.map((rd) => ScheduleMath.dateStr(rd)).toSet();
    // 当前已选：使用原本那天的日期；不在候选项中时视为未设置。
    var current = '';
    for (final r in _reschedules) {
      if (r.date == dateStr && optionValues.contains(r.source)) {
        current = r.source;
        break;
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${d.month}月${d.day}日 '
                    '${ScheduleMath.weekdayName(d.weekday)}（补班）',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '第$week周',
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: current,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '当天使用原本哪天的课',
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('无')),
                for (final rd in restDays)
                  DropdownMenuItem(
                    value: ScheduleMath.dateStr(rd),
                    child: Text(
                      '${ScheduleMath.weekdayName(rd.weekday)}'
                      '（${ScheduleMath.formatMd(rd)}）',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                final sel = v ?? '';
                _reschedules.removeWhere((r) => r.date == dateStr);
                if (sel.isNotEmpty) {
                  _reschedules.add(RescheduleDay(date: dateStr, source: sel));
                }
              }),
            ),
          ],
        ),
      ),
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
