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
          itemBuilder: (context, index) {
            final week = index + 1;
            final selected = week == _selected;
            final isToday = week == widget.todayWeek;
            final scheme = Theme.of(context).colorScheme;
            return ChoiceChip(
              label: Text('$week'),
              selected: selected,
              selectedColor: scheme.primaryContainer,
              // 所有格子统一形状，仅用主色描边给本周做小高亮。
              side: isToday
                  ? BorderSide(color: scheme.primary, width: 1.4)
                  : null,
              onSelected: (_) => setState(() => _selected = week),
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
