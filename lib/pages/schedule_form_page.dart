import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextEditingValue, TextInputFormatter;
import 'package:provider/provider.dart';

import '../models/schedule.dart';
import '../services/schedule_math.dart';
import '../state/app_state.dart';
import 'building_edit_page.dart';
import 'buildings_share_page.dart';

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

  /// 是否有未保存的修改：退出时（返回/手势/ESC）弹出确认。
  bool _dirty = false;

  /// 楼宇多选删除模式：长按（桌面端右键）某个楼宇进入。
  bool _selectingBuildings = false;
  final Set<Building> _selectedBuildings = {};

  @override
  void initState() {
    super.initState();
    final s = widget.schedule;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    // 名称被编辑即视为有未保存修改（初始值写入后才挂监听）。
    _nameCtrl.addListener(_markDirty);
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

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// 返回确认：有未保存修改时弹出，确认后才真正退出。
  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.schedule == null ? '课程表尚未保存' : '修改尚未保存'),
        content: const Text('确定要放弃并退出吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续编辑')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('放弃修改')),
        ],
      ),
    );
    return leave == true;
  }

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
        _dirty = true;
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
    if (result != null) {
      setState(() {
        _buildings.add(result);
        _dirty = true;
      });
    }
  }

  void _setBuildingSelecting(bool on) => setState(() {
        _selectingBuildings = on;
        _selectedBuildings.clear();
      });

  /// 长按 / 右键某个楼宇：进入多选并勾上它。
  void _enterBuildingSelecting(Building b) => setState(() {
        _selectingBuildings = true;
        _selectedBuildings
          ..clear()
          ..add(b);
      });

  void _toggleBuilding(Building b) => setState(() {
        if (!_selectedBuildings.remove(b)) _selectedBuildings.add(b);
      });

  Future<void> _deleteSelectedBuildings() async {
    final count = _selectedBuildings.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除所选楼宇'),
        content: Text('确定删除所选的 $count 栋楼宇吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _buildings.removeWhere(_selectedBuildings.contains);
      _selectedBuildings.clear();
      _selectingBuildings = false;
      _dirty = true;
    });
    _snack('已删除 $count 栋楼宇');
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
      // 同时清除未保存标记，让 PopScope 放行退出。
      setState(() => _dirty = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = context.watch<AppState>();
    final allBuildingsSelected =
        _buildings.isNotEmpty && _selectedBuildings.length == _buildings.length;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _confirmDiscard();
        if (leave && mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.schedule == null ? '新建课程表' : '编辑课程表')),
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
          _NumberStepperTile(
            label: '总周数',
            value: _totalWeeks,
            min: 1,
            max: 53,
            onChanged: (v) {
              setState(() {
                _totalWeeks = v;
                _dirty = true;
              });
              _refreshHolidays();
            },
          ),
          _NumberStepperTile(
            label: '一日总节数',
            value: _periodsPerDay,
            min: 1,
            max: 20,
            onChanged: (v) => setState(() {
              _periodsPerDay = v;
              _dirty = true;
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
              // showDatePicker 要求 initialDate 必须满足 selectableDayPredicate，
              // 这里只允许选周一：未设置（或旧数据不是周一）时就近取该周的周一，
              // 否则直接抛断言异常。
              final base = _firstMonday ?? DateTime.now();
              final initial = DateTime(
                base.year,
                base.month,
                base.day - (base.weekday - DateTime.monday),
              );
              final d = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                // 第一周周一只能是周一。
                selectableDayPredicate: (day) => day.weekday == DateTime.monday,
              );
              if (d != null) {
                setState(() {
                  _firstMonday = ScheduleMath.dateOnly(d);
                  _dirty = true;
                });
                _refreshHolidays();
              }
            },
          ),
          const Divider(height: 32),
          Row(
            children: [
              Text(
                _selectingBuildings
                    ? '已选 ${_selectedBuildings.length} 栋'
                    : '学校楼宇',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_selectingBuildings) ...[
                TextButton(
                  onPressed: allBuildingsSelected
                      ? () => setState(_selectedBuildings.clear)
                      : () => setState(
                          () => _selectedBuildings.addAll(_buildings)),
                  child: Text(allBuildingsSelected ? '取消全选' : '全选'),
                ),
                IconButton(
                  tooltip: '删除所选',
                  icon: const Icon(Icons.delete_outline),
                  onPressed:
                      _selectedBuildings.isEmpty ? null : _deleteSelectedBuildings,
                ),
                IconButton(
                  tooltip: '退出多选',
                  icon: const Icon(Icons.close),
                  onPressed: () => _setBuildingSelecting(false),
                ),
              ] else ...[
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
                PopupMenuButton<String>(
                  tooltip: '导入 / 导出楼宇',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (v) =>
                      v == 'export' ? _exportBuildings() : _importBuildings(),
                  itemBuilder: (ctx) => [
                    if (_buildings.isNotEmpty)
                      const PopupMenuItem(
                        value: 'export',
                        child: Text('导出楼宇配置'),
                      ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Text('导入楼宇配置'),
                    ),
                  ],
                ),
              ],
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
              child: GestureDetector(
                // 桌面端右键等同长按，进入多选。
                onSecondaryTap: _selectingBuildings
                    ? null
                    : () => _enterBuildingSelecting(b),
                child: ListTile(
                  leading: _selectingBuildings
                      ? Checkbox(
                          value: _selectedBuildings.contains(b),
                          onChanged: (_) => _toggleBuilding(b),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        )
                      : null,
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
                  onTap: _selectingBuildings
                      ? () => _toggleBuilding(b)
                      : () => _editBuilding(b),
                  onLongPress: _selectingBuildings
                      ? null
                      : () => _enterBuildingSelecting(b),
                  trailing: _selectingBuildings
                      ? null
                      : TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => _copyRangesFromBuilding(b),
                          child: const Text('从其他楼宇复制',
                              style: TextStyle(fontSize: 12)),
                        ),
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
            (v) => setState(() {
              _lunchAfter = v;
              _dirty = true;
            }),
          ),
          _mealDropdown(
            theme,
            '晚餐',
            _dinnerAfter,
            (v) => setState(() {
              _dinnerAfter = v;
              _dirty = true;
            }),
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
      ),
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
                _dirty = true;
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
        _dirty = true;
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
      _dirty = true;
    });
  }

  /// 打开分享页导出楼宇：二维码与数据文件两种方案。
  Future<void> _exportBuildings() async {
    if (_buildings.isEmpty) {
      _snack('还没有楼宇可导出');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuildingsSharePage(
          buildings: _buildings.map((b) => b.copy()).toList(),
          title: _nameCtrl.text.trim(),
        ),
      ),
    );
  }

  /// 打开分享页导入楼宇：扫码 / 识别图片 / 选择文件任选一种，
  /// 拿到楼宇后再让用户决定「替换」还是「追加」。
  Future<void> _importBuildings() async {
    final imported = await Navigator.push<List<Building>>(
      context,
      MaterialPageRoute(
        builder: (_) => const BuildingsSharePage(importMode: true),
      ),
    );
    if (imported == null || imported.isEmpty || !mounted) return;
    var mode = 'replace';
    if (_buildings.isNotEmpty) {
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入楼宇'),
          content: Text(
            '导入内容有 ${imported.length} 栋楼宇，当前已有 ${_buildings.length} 栋。',
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'append'),
                child: const Text('追加')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'replace'),
                child: const Text('替换')),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      mode = picked;
    }
    var added = 0;
    var skipped = 0;
    setState(() {
      if (mode == 'replace') {
        _buildings = imported.map((b) => b.copy()).toList();
        added = imported.length;
      } else {
        // 追加：同名的跳过，避免出现两栋「第一教学楼」。
        final names = {for (final b in _buildings) b.name};
        for (final b in imported) {
          if (names.add(b.name)) {
            _buildings.add(b.copy());
            added++;
          } else {
            skipped++;
          }
        }
      }
      _dirty = true;
    });
    _snack(
      skipped == 0
          ? '已导入 $added 栋楼宇'
          : '已导入 $added 栋楼宇（跳过 $skipped 栋重名）',
    );
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

/// 数字步进器：两侧按钮加减，中间的输入框可直接键盘输入。
///
/// [value] 为 null 表示「未设置」，此时输入框留空显示占位文字，
/// 输入合法数字后即视为已设置。
class _NumberStepperTile extends StatefulWidget {
  const _NumberStepperTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberStepperTile> createState() => _NumberStepperTileState();
}

class _NumberStepperTileState extends State<_NumberStepperTile> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.value?.toString() ?? '',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 失焦时把输入框内容规整回合法值（清空 / 前导零等）。
    _focus.addListener(() {
      if (!_focus.hasFocus) _normalize();
    });
  }

  @override
  void didUpdateWidget(covariant _NumberStepperTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.value?.toString() ?? '';
    if (_ctrl.text == text) return;
    // 正在输入、且框里的内容本来就代表当前值（打字引起的重建）时不打断光标；
    // 值是被加减按钮改掉的才同步回来，并全选，方便接着用键盘覆盖输入。
    if (_focus.hasFocus && int.tryParse(_ctrl.text) == widget.value) return;
    _ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 失焦/回车后把显示规整成当前值（清空或前导零会还原）。
  void _normalize() {
    final text = widget.value?.toString() ?? '';
    if (_ctrl.text == text) return;
    _ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onChanged(String text) {
    final n = int.tryParse(text);
    if (n == null) return; // 输入框清空：保留原值，失焦时再还原显示
    if (n != widget.value) widget.onChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = widget.value;
    return Row(
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value != null && value > widget.min
              ? () => widget.onChanged(value - 1)
              : null,
        ),
        SizedBox(
          width: 56,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _RangeIntFormatter(min: widget.min, max: widget.max),
            ],
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              hintText: '未设置',
              hintStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: theme.colorScheme.outline,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _normalize(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value != null && value < widget.max
              ? () => widget.onChanged(value + 1)
              : value == null
                  ? () => widget.onChanged(widget.min)
                  : null,
        ),
      ],
    );
  }
}

/// 只放行空串或 [min, max] 范围内的整数，越界/非数字的输入直接丢弃。
class _RangeIntFormatter extends TextInputFormatter {
  _RangeIntFormatter({required this.min, required this.max});

  final int min;
  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.trim();
    if (text.isEmpty) return newValue;
    final n = int.tryParse(text);
    if (n == null || n < min || n > max) return oldValue;
    return newValue;
  }
}
