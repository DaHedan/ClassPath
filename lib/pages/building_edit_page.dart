import 'package:flutter/material.dart';

import '../models/schedule.dart';
import '../widgets/time_dial_picker.dart';

/// 楼宇编辑页：设置楼宇名称与节次时间段，支持从其他楼宇复制时间段。
class BuildingEditPage extends StatefulWidget {
  /// 待编辑楼宇的副本。
  final Building building;

  /// 同课程表下的其他楼宇（用于复制时间段）。
  final List<Building> otherBuildings;

  /// 节次数量上限。
  final int maxPeriods;

  const BuildingEditPage({
    super.key,
    required this.building,
    required this.otherBuildings,
    required this.maxPeriods,
  });

  @override
  State<BuildingEditPage> createState() => _BuildingEditPageState();
}

class _BuildingEditPageState extends State<BuildingEditPage> {
  late final TextEditingController _nameCtrl;
  late List<PeriodTime> _ranges;

  /// 多选删除模式：长按（桌面端右键）某段时间进入。
  bool _selecting = false;
  final Set<PeriodTime> _selected = {};

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.building.name);
    _ranges = widget.building.periodTimes.map((e) => e.copy()).toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));

  void _setSelecting(bool on) => setState(() {
        _selecting = on;
        _selected.clear();
      });

  /// 长按 / 右键某段时间：进入多选并勾上它。
  void _enterSelecting(PeriodTime r) => setState(() {
        _selecting = true;
        _selected
          ..clear()
          ..add(r);
      });

  void _toggle(PeriodTime r) => setState(() {
        if (!_selected.remove(r)) _selected.add(r);
      });

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除所选时间段'),
        content: Text('确定删除所选的 $count 段时间吗？'),
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
      _ranges.removeWhere(_selected.contains);
      _selecting = false;
      _selected.clear();
    });
    _snack('已删除 $count 段时间');
  }

  Future<void> _copyRangesFromOtherBuilding() async {
    final others = widget.otherBuildings.toList();
    if (others.isEmpty) {
      _snack('没有其他楼宇可复制');
      return;
    }
    final picked = await _pickFromList<Building>(
        context, others, (b) => b.name, '选择要复制时间段的楼宇');
    if (picked != null) {
      setState(() => _ranges = picked.periodTimes.map((e) => e.copy()).toList());
    }
  }

  Future<void> _addRange() async {
    final r = await showDialog<PeriodTime>(
      context: context,
      builder: (_) => _PeriodTimeDialog(maxPeriods: widget.maxPeriods),
    );
    if (r != null) setState(() => _ranges.add(r));
  }

  Future<void> _editRange(PeriodTime target) async {
    final r = await showDialog<PeriodTime>(
      context: context,
      builder: (_) =>
          _PeriodTimeDialog(maxPeriods: widget.maxPeriods, initial: target),
    );
    if (r != null) {
      setState(() {
        final i = _ranges.indexOf(target);
        if (i >= 0) _ranges[i] = r;
      });
    }
  }

  void _save() {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('请输入楼宇名称');
      return;
    }
    Navigator.pop(
      context,
      Building(name: _nameCtrl.text.trim(), periodTimes: _ranges),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected =
        _ranges.isNotEmpty && _selected.length == _ranges.length;
    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                tooltip: '退出多选',
                icon: const Icon(Icons.close),
                onPressed: () => _setSelecting(false),
              )
            : null,
        title: Text(_selecting ? '已选 ${_selected.length} 段' : '编辑楼宇'),
        actions: _selecting
            ? [
                TextButton(
                  onPressed: allSelected
                      ? () => setState(_selected.clear)
                      : () => setState(() => _selected.addAll(_ranges)),
                  child: Text(allSelected ? '取消全选' : '全选'),
                ),
                IconButton(
                  tooltip: '删除所选',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                ),
              ]
            : [
                TextButton.icon(
                  onPressed: _copyRangesFromOtherBuilding,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('从其他楼宇复制'),
                ),
                IconButton(
                  tooltip: '保存',
                  icon: const Icon(Icons.check),
                  onPressed: _save,
                ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '楼宇名称',
              hintText: '如：第一教学楼',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('节次时间段',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addRange,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加时间段'),
              ),
            ],
          ),
          if (_ranges.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('还没有设置时间段，如 1-2节 对应 08:15-09:35。',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.outline)),
            ),
          for (final r in _ranges)
            GestureDetector(
              // 桌面端右键等同长按，进入多选。
              onSecondaryTap: _selecting ? null : () => _enterSelecting(r),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _selecting
                    ? Checkbox(
                        value: _selected.contains(r),
                        onChanged: (_) => _toggle(r),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      )
                    : null,
                title: Text(r.display),
                // 多选模式下点整行即勾选，长按进入多选。
                onTap: _selecting ? () => _toggle(r) : null,
                onLongPress: _selecting ? null : () => _enterSelecting(r),
                trailing: _selecting
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _editRange(r),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 20, color: Colors.red),
                            onPressed: () =>
                                setState(() => _ranges.remove(r)),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
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

/// 时间段编辑对话框：起始节次、结束节次、开始/结束时间。
class _PeriodTimeDialog extends StatefulWidget {
  final int maxPeriods;
  final PeriodTime? initial;

  const _PeriodTimeDialog({required this.maxPeriods, this.initial});

  @override
  State<_PeriodTimeDialog> createState() => _PeriodTimeDialogState();
}

class _PeriodTimeDialogState extends State<_PeriodTimeDialog> {
  // 新建时间段时各项均无默认值，需用户选择/填写。
  late int? _from = widget.initial?.startPeriod;
  late int? _to = widget.initial?.endPeriod;
  late TimeOfDay? _start =
      widget.initial == null ? null : _toTime(widget.initial!.start);
  late TimeOfDay? _end =
      widget.initial == null ? null : _toTime(widget.initial!.end);

  static TimeOfDay _toTime(String s) {
    final p = s.split(':');
    return TimeOfDay(
        hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('时间段'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: _from,
                hint: const Text('第X节'),
                items: [
                  for (var i = 1; i <= widget.maxPeriods; i++)
                    DropdownMenuItem(value: i, child: Text('第$i节')),
                ],
                onChanged: (v) => setState(() => _from = v),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('至'),
              ),
              DropdownButton<int>(
                value: _to,
                hint: const Text('第X节'),
                items: [
                  for (var i = 1; i <= widget.maxPeriods; i++)
                    DropdownMenuItem(value: i, child: Text('第$i节')),
                ],
                onChanged: (v) => setState(() => _to = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开始时间'),
            trailing: Text(_start == null ? '选择时间' : _fmt(_start!)),
            onTap: () async {
              final t = await showClassPathTimePicker(
                  context: context, initialTime: _start ?? const TimeOfDay(hour: 8, minute: 0));
              if (t != null) setState(() => _start = t);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('结束时间'),
            trailing: Text(_end == null ? '选择时间' : _fmt(_end!)),
            onTap: () async {
              final t = await showClassPathTimePicker(
                  context: context, initialTime: _end ?? const TimeOfDay(hour: 9, minute: 0));
              if (t != null) setState(() => _end = t);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final from = _from;
            final to = _to;
            final start = _start;
            final end = _end;
            if (from == null || to == null) {
              _snack('请选择起始与结束节次');
              return;
            }
            if (to < from) {
              _snack('结束节次不能小于起始节次');
              return;
            }
            if (start == null || end == null) {
              _snack('请设置开始与结束时间');
              return;
            }
            final startMin = start.hour * 60 + start.minute;
            final endMin = end.hour * 60 + end.minute;
            if (endMin <= startMin) {
              _snack('结束时间需晚于开始时间');
              return;
            }
            Navigator.pop(
                context,
                PeriodTime(
                  startPeriod: from,
                  endPeriod: to,
                  start: _fmt(start),
                  end: _fmt(end),
                ));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
