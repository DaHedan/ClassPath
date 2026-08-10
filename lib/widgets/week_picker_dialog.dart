import 'package:flutter/material.dart';

/// 周次选择对话框：从 1..totalWeeks 中选择一周。
Future<int?> showWeekPicker(
  BuildContext context, {
  required int totalWeeks,
  required int current,

  /// 今天实际所在的周（用于「回到本周」）。
  required int todayWeek,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _WeekPickerDialog(
      totalWeeks: totalWeeks,
      current: current,
      todayWeek: todayWeek,
    ),
  );
}

class _WeekPickerDialog extends StatefulWidget {
  final int totalWeeks;
  final int current;
  final int todayWeek;

  const _WeekPickerDialog({
    required this.totalWeeks,
    required this.current,
    required this.todayWeek,
  });

  @override
  State<_WeekPickerDialog> createState() => _WeekPickerDialogState();
}

class _WeekPickerDialogState extends State<_WeekPickerDialog> {
  late int _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择周次'),
      content: SizedBox(
        width: 320,
        height: 380,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: widget.totalWeeks,
          // 自定义格子：撑满网格单元，所有格子统一为方形，
          // 选中只用颜色区分、不改变形状（避免 ChoiceChip 选中加
          // 对勾导致一位数/两位数/选中态宽度不一致、数字显示不全）。
          itemBuilder: (context, index) {
            final week = index + 1;
            final selected = week == _selected;
            final isToday = week == widget.todayWeek;
            final scheme = Theme.of(context).colorScheme;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _selected = week),
              child: Container(
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  // 本周用主色描边做小高亮。
                  border: isToday
                      ? Border.all(color: scheme.primary, width: 1.4)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$week',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, widget.todayWeek),
          child: const Text('回到本周'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
