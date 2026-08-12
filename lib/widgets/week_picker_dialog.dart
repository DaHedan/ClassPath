import 'package:flutter/material.dart';

/// 周次选择对话框：从 1..totalWeeks 中选择一周，点击哪个就切换哪个。
Future<int?> showWeekPicker(
  BuildContext context, {
  required int totalWeeks,

  /// 今天实际所在的周（用于高亮「本周」）。
  required int todayWeek,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _WeekPickerDialog(
      totalWeeks: totalWeeks,
      todayWeek: todayWeek,
    ),
  );
}

class _WeekPickerDialog extends StatelessWidget {
  final int totalWeeks;
  final int todayWeek;

  const _WeekPickerDialog({
    required this.totalWeeks,
    required this.todayWeek,
  });

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
          itemCount: totalWeeks,
          // 自定义格子：撑满网格单元，所有格子统一为方形；
          // 点击哪个周就直接切换并关闭，没有确定/回到本周按钮。
          itemBuilder: (context, index) {
            final week = index + 1;
            final isToday = week == todayWeek;
            final scheme = Theme.of(context).colorScheme;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pop(context, week),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
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
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
