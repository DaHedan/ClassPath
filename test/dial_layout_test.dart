import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classpath/widgets/time_dial_picker.dart';

void main() {
  Future<void> openDial(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                await showClassPathTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 8, minute: 0),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final size in const <Size>[
    Size(320, 480), // 小屏手机
    Size(360, 640), // 常见手机
    Size(393, 851), // Pixel 5
    Size(414, 896), // iPhone 11
    Size(500, 400), // 矮宽窗口（Windows 小窗口）
    Size(1280, 720), // 桌面
  ]) {
    testWidgets('表盘在 $size 无布局错误', (tester) async {
      await openDial(tester, size);
      expect(find.text('选择时间'), findsOneWidget);
    });
  }

  testWidgets('表盘拖动选择不抛异常', (tester) async {
    await openDial(tester, const Size(393, 851));
    final dial = find.byType(CustomPaint);
    // 模拟在表盘上点按/拖动。
    final center = tester.getCenter(dial.last);
    await tester.tapAt(center + const Offset(60, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('选择时间'), findsNothing);
  });

  testWidgets('表盘在大字体（无障碍缩放 1.3x）下无布局错误', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                await showClassPathTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 8, minute: 0),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('选择时间'), findsOneWidget);
  });
}
