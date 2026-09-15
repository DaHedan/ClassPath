import 'dart:ui';

import 'package:classpath/services/timetable_image_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一行 OCR 文本（以中心点定位，贴近 ML Kit 给出的 boundingBox 语义）。
OcrLine _line(String text, double cx, double cy,
        {double w = 90, double h = 16}) =>
    OcrLine(text, Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));

/// 模拟一张「星期一~星期五、1~15 节」的教务系统课程表图片。
List<OcrLine> _sampleTable() {
  final lines = <OcrLine>[
    // 表头
    for (var i = 0; i < 5; i++)
      _line(['星期一', '星期二', '星期三', '星期四', '星期五'][i], 130 + i * 238.0, 18),
    _line('节次', 22, 18, w: 30),
    // 左侧节次列
    for (var p = 1; p <= 15; p++) _line('$p', 20, 63 + (p - 1) * 42.0, w: 14),
    // 星期三：大学物理A（下）第 1-2 节
    _line('大学物理A（下）', 607, 48, w: 140),
    _line('0444', 545, 66, w: 40),
    _line('(1-3,5~12周)(1-2节) J301多 陈莉', 620, 84, w: 220),
    // 星期一：大学物理A（下）第 6-7 节
    _line('大学物理A（下）', 130, 266, w: 140),
    _line('0444', 68, 284, w: 40),
    _line('(1~12周)(6-7节) J301多 陈莉', 145, 302, w: 200),
    // 星期二：体育（二）一节里有两组「周次+节次+地点」
    _line('体育（二）', 369, 350, w: 100),
    _line('0780', 300, 368, w: 40),
    _line('(2~3,5~16周)(8-9节) 西看台2楼 武军', 380, 386, w: 210),
    _line('(1周)(8-9节) 风雨操场篮球场 武军', 380, 404, w: 210),
    // 星期四：地点带括号、无教师
    _line('电工实习', 846, 434, w: 70),
    _line('1742', 790, 452, w: 40),
    _line('(5周)(10-14节)（电工实验室）训1353', 860, 470, w: 220),
  ];
  // 电工实习在周一~周五都有（同名课程，应合并为一门、5 个上课时间）
  for (var i = 0; i < 5; i++) {
    if (i == 3) continue;
    final cx = 130 + i * 238.0;
    lines
      ..add(_line('电工实习', cx, 434, w: 70))
      ..add(_line('1742', cx - 56, 452, w: 40))
      ..add(_line('(5周)(10-14节)（电工实验室）训1353', cx + 14, 470, w: 220));
  }
  return lines;
}

void main() {
  test('识别列头与节次列，按同名课程合并', () {
    final r = TimetableImageParser.parse(_sampleTable());
    expect(r.error, isNull);
    expect(r.weekdays, ['周一', '周二', '周三', '周四', '周五']);
    expect(r.periodRows, 15);

    // 电工实习：5 天各一次，合并成一门课
    final practice = r.courses.firstWhere((c) => c.name == '电工实习');
    expect(practice.id, '1742');
    expect(practice.classTimes.length, 5);
    expect(practice.classTimes.first.weekday, 1);
    expect(practice.classTimes.first.startPeriod, 10);
    expect(practice.classTimes.first.endPeriod, 14);
    expect(practice.classTimes.first.weeks, [5]);
    expect(practice.classTimes.first.location, '（电工实验室）训1353');
    expect(practice.teacher, isNull);

    // 大学物理A（下）：周一 6-7 节 + 周三 1-2 节
    final physics = r.courses.firstWhere((c) => c.name == '大学物理A（下）');
    expect(physics.id, '0444');
    expect(physics.teacher, '陈莉');
    expect(physics.location, 'J301多');
    expect(physics.classTimes.length, 2);
    expect(physics.classTimes[0].weekday, 1);
    expect(physics.classTimes[0].startPeriod, 6);
    expect(physics.classTimes[0].weeks, List.generate(12, (i) => i + 1));
    expect(physics.classTimes[1].weekday, 3);
    expect(physics.classTimes[1].startPeriod, 1);
    expect(physics.classTimes[1].endPeriod, 2);
    expect(physics.classTimes[1].weeks, [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12]);
  });

  test('一个单元格里的多组周次/节次会拆成多次上课时间', () {
    final r = TimetableImageParser.parse(_sampleTable());
    final pe = r.courses.firstWhere((c) => c.name == '体育（二）');
    expect(pe.id, '0780');
    expect(pe.teacher, '武军');
    expect(pe.classTimes.length, 2);
    expect(pe.classTimes[0].weeks,
        [2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
    expect(pe.classTimes[0].location, '西看台2楼');
    expect(pe.classTimes[1].weeks, [1]);
    expect(pe.classTimes[1].location, '风雨操场篮球场');
  });

  test('同一水平线跨列的文字（ML Kit 常见行为）不会串列', () {
    final lines = <OcrLine>[
      _line('星期一', 130, 18),
      _line('星期二', 368, 18),
      _line('星期三', 606, 18),
      for (var p = 1; p <= 15; p++) _line('$p', 20, 63 + (p - 1) * 42.0, w: 14),
      // 星期一 3-4 节
      _line('复变函数与积分变换', 130, 147, w: 140),
      _line('1728', 68, 165, w: 40),
      _line('(1~12周)(3-4节) C306多 卞之豪', 145, 183, w: 200),
      // 星期二 3-4 节：与上面同一条水平线
      _line('劳动教育（二）', 368, 147, w: 100),
      _line('1749', 306, 165, w: 40),
      _line('(8周)(3-4节) C219多 刘欣迪', 383, 183, w: 200),
    ];
    final r = TimetableImageParser.parse(lines);
    expect(r.error, isNull);
    expect(r.weekdays, ['周一', '周二', '周三']);

    final complex = r.courses.firstWhere((c) => c.name == '复变函数与积分变换');
    expect(complex.id, '1728');
    expect(complex.classTimes.single.weekday, 1);
    expect(complex.classTimes.single.startPeriod, 3);
    expect(complex.classTimes.single.endPeriod, 4);
    expect(complex.classTimes.single.location, 'C306多');
    expect(complex.teacher, '卞之豪');

    final labour = r.courses.firstWhere((c) => c.name == '劳动教育（二）');
    expect(labour.id, '1749');
    expect(labour.classTimes.single.weekday, 2);
    expect(labour.classTimes.single.weeks, [8]);
    expect(labour.classTimes.single.location, 'C219多');
    expect(labour.teacher, '刘欣迪');
  });

  test('仍被并成一个词框的跨列文字，按列边界切开', () {
    final lines = <OcrLine>[
      _line('星期一', 130, 18),
      _line('星期二', 368, 18),
      for (var p = 1; p <= 15; p++) _line('$p', 20, 63 + (p - 1) * 42.0, w: 14),
      // 周一、周二的课程名被 OCR 并进了同一个词框
      _line('复变函数与积分变换 劳动教育（二）', 250, 147, w: 420),
      _line('1728', 68, 165, w: 40),
      _line('(1~12周)(3-4节) C306多 卞之豪', 145, 183, w: 200),
      _line('1749', 306, 165, w: 40),
      _line('(8周)(3-4节) C219多 刘欣迪', 383, 183, w: 200),
    ];
    final r = TimetableImageParser.parse(lines);
    expect(r.error, isNull);

    final complex = r.courses.firstWhere((c) => c.name == '复变函数与积分变换');
    expect(complex.classTimes.single.weekday, 1);
    final labour = r.courses.firstWhere((c) => c.name == '劳动教育（二）');
    expect(labour.classTimes.single.weekday, 2);
  });

  test('真机 OCR 数据：跨列并框 + 节次列识别不全时仍按格解析', () {
    OcrLine e(double l, double t, double r, double b, String text) =>
        OcrLine(text, Rect.fromLTRB(l, t, r, b));
    final lines = <OcrLine>[
      // 表头
      e(134, 602, 187, 619, '星期一'),
      e(365, 602, 416, 619, '星期二'),
      e(595, 602, 648, 619, '星期三'),
      e(825, 602, 877, 619, '星期四'),
      e(1056, 602, 1108, 619, '星期五'),
      // 左侧节次列：真机上只有这几个是独立数字，其余行号被粘进了课程名
      e(25, 1115, 32, 1127, '8'),
      e(22, 1347, 43, 1366, '11'),
      e(22, 1408, 37, 1420, '12'),
      e(22, 1467, 37, 1479, '13'),
      e(22, 1527, 38, 1539, '14'),
      e(22, 1586, 37, 1598, '15'),
      // 星期一 3-4 节
      e(57, 767, 223, 784, '|复变函数与积分变换'),
      e(58, 795, 92, 807, '1728'),
      e(49, 815, 121, 834, '|(1~12周)'),
      e(126, 815, 323, 834, '(3-4节)C306多卞(8周)'),
      e(327, 815, 384, 834, '(3-4节)'),
      e(392, 815, 487, 834, 'C219多刘欣'),
      e(58, 842, 87, 856, '之豪'),
      // 星期二 3-4 节
      e(287, 765, 404, 784, '|劳动教育(二)'),
      e(288, 794, 322, 808, '1749'),
      e(288, 841, 302, 855, '迪'),
      // 星期一 6-7 节
      e(25, 966, 186, 991, '6大学物理A(下)'),
      e(57, 999, 93, 1011, '0444'),
      e(49, 1017, 121, 1038, '[(1~12周)'),
      e(127, 1017, 264, 1038, '(6-7节)J301多陈'),
      e(46, 1041, 80, 1065, '|莉'),
      // 星期一 8-9 节
      e(57, 1087, 204, 1104, '概率论与数理统计'),
      e(58, 1115, 92, 1127, '1758'),
      e(49, 1133, 241, 1154, '(1~12周)(8-9节)A510多'),
      e(252, 1136, 327, 1156, '吴0780'),
      e(58, 1161, 87, 1176, '隋超'),
      // 星期一 10-14 节
      e(22, 1274, 127, 1302, '10|电工实习'),
      e(59, 1306, 93, 1319, '1742'),
      e(50, 1327, 93, 1345, '|(5周)'),
      e(99, 1327, 259, 1345, '(10-14节)(电工实验'),
      e(78, 1350, 83, 1368, ')'),
      e(88, 1350, 140, 1371, '|1353'),
    ];
    final r = TimetableImageParser.parse(lines);
    expect(r.error, isNull);
    expect(r.weekdays, ['周一', '周二', '周三', '周四', '周五']);

    // 周一 3-4 节：跨列并框被切开，教师名跨行也被拼回
    final complex = r.courses.firstWhere((c) => c.name == '复变函数与积分变换');
    expect(complex.id, '1728');
    expect(complex.teacher, '卞之豪');
    expect(complex.classTimes.single.weekday, 1);
    expect(complex.classTimes.single.startPeriod, 3);
    expect(complex.classTimes.single.endPeriod, 4);
    expect(complex.classTimes.single.weeks, List.generate(12, (i) => i + 1));
    expect(complex.classTimes.single.location, 'C306多');

    // 周二 3-4 节：只拿到自己的那一半，没串到周一
    final labour = r.courses.firstWhere((c) => c.name == '劳动教育(二)');
    expect(labour.id, '1749');
    expect(labour.teacher, '刘欣迪');
    expect(labour.classTimes.single.weekday, 2);
    expect(labour.classTimes.single.startPeriod, 3);
    expect(labour.classTimes.single.endPeriod, 4);
    expect(labour.classTimes.single.weeks, [8]);
    expect(labour.classTimes.single.location, 'C219多');

    // 课名前的行号「6」被清掉
    final physics = r.courses.firstWhere((c) => c.name == '大学物理A(下)');
    expect(physics.id, '0444');
    expect(physics.teacher, '陈莉');
    expect(physics.classTimes.single.startPeriod, 6);
    expect(physics.classTimes.single.endPeriod, 7);
    expect(physics.classTimes.single.location, 'J301多');

    final practice = r.courses.firstWhere((c) => c.name == '电工实习');
    expect(practice.id, '1742');
    expect(practice.classTimes.single.startPeriod, 10);
    expect(practice.classTimes.single.endPeriod, 14);
    expect(practice.classTimes.single.weeks, [5]);

    expect(r.courses.map((c) => c.name), contains('概率论与数理统计'));
  });

  test('没有列头时给出明确错误', () {
    final r = TimetableImageParser.parse([_line('随便一段文字', 100, 100)]);
    expect(r.error, isNotNull);
    expect(r.courses, isEmpty);
  });

  test('单双周与逗号分隔的周次', () {
    final r = TimetableImageParser.parse([
      _line('星期一', 100, 20),
      _line('星期二', 300, 20),
      _line('1', 20, 60, w: 14),
      _line('2', 20, 120, w: 14),
      _line('高等数学', 100, 50, w: 80),
      _line('0001', 60, 68, w: 40),
      _line('(1-16周（单）)(1-2节) A101 张三', 110, 86, w: 200),
      _line('大学英语', 300, 110, w: 80),
      _line('0002', 260, 128, w: 40),
      _line('(1,3,5周)(2节) B202 李四', 310, 146, w: 200),
    ]);
    final math = r.courses.firstWhere((c) => c.name == '高等数学');
    expect(math.classTimes.single.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    final english = r.courses.firstWhere((c) => c.name == '大学英语');
    expect(english.classTimes.single.weeks, [1, 3, 5]);
    expect(english.classTimes.single.startPeriod, 2);
    expect(english.classTimes.single.endPeriod, 2);
  });
}
