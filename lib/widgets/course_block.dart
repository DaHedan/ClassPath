import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/schedule_math.dart';

/// 课程表中的单个课程方块：显示课程名、教师、上课时间、上课周与地点。
///
/// [times] 为本学期模式下同格内合并的同一门课的各时段（如不同上课周、
/// 不同地点），每条显示一行「上课周+地点」；单周模式只有一个时段，
/// 只显示地点、不显示上课周。
class CourseBlock extends StatelessWidget {
  final Course course;
  final VoidCallback onTap;

  /// 该方块包含的上课时段（至少一个）。
  final List<ClassTime> times;

  /// 是否显示上课周（本学期模式为 true，单周模式为 false）。
  final bool showWeeks;

  /// 网格缩放倍率：随缩放等比例放大字号与内边距。
  final double scale;

  const CourseBlock({
    super.key,
    required this.course,
    required this.times,
    required this.onTap,
    this.showWeeks = false,
    this.scale = 1.0,
  });

  /// 单节课地点文本：单节覆盖优先，否则用课程总体地点；
  /// 楼宇与房号之间不加空格（如「第一教学楼A101」）。
  String _locOf(ClassTime ct) {
    final loc = (ct.location?.isEmpty ?? true) ? course.location : ct.location!;
    final b = loc.building.trim();
    final r = loc.room.trim();
    return b.isEmpty ? r : (r.isEmpty ? b : '$b$r');
  }

  /// 上课周文本：null（全部周）显示「全部周」，否则压缩为「第x-x周」。
  String _weeksOf(ClassTime ct) =>
      ct.weeks == null ? '全部周' : ScheduleMath.weeksToText(ct.weeks!);

  @override
  Widget build(BuildContext context) {
    final color = Color(course.colorValue);
    final textColor =
        color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final teacher = (course.teacher ?? '').trim();

    // 时间行：取合并时段中最早的开始到最晚的结束（单时段即其本身）。
    var minStart = times.first.start;
    var maxEnd = times.first.end;
    for (final ct in times) {
      if (ScheduleMath.timeToMinutes(ct.start) <
          ScheduleMath.timeToMinutes(minStart)) {
        minStart = ct.start;
      }
      if (ScheduleMath.timeToMinutes(ct.end) >
          ScheduleMath.timeToMinutes(maxEnd)) {
        maxEnd = ct.end;
      }
    }
    final timeText = '$minStart-$maxEnd';

    // 底部信息行：单周模式只显示地点；本学期模式每条时段显示「上课周+地点」。
    final infoLines = <String>[];
    if (showWeeks) {
      for (final ct in times) {
        final w = _weeksOf(ct);
        final l = _locOf(ct);
        infoLines.add(l.isEmpty ? w : '$w$l');
      }
    } else {
      final l = _locOf(times.first);
      if (l.isNotEmpty) infoLines.add(l);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.all(1.5 * scale),
        padding: EdgeInsets.symmetric(
            horizontal: 2 * scale, vertical: 3 * scale),
        decoration: BoxDecoration(
          // 立体感：上亮下暗的纵向渐变 + 顶部高光边 + 底部柔投影。
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(color, Colors.white, 0.18)!,
              color,
              Color.lerp(color, Colors.black, 0.16)!,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(6 * scale),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 3 * scale,
              offset: Offset(0, 2 * scale),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              course.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5 * scale,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: textColor,
              ),
            ),
            if (teacher.isNotEmpty)
              Text(
                teacher,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 8.5 * scale, height: 1.2, color: textColor),
              ),
            Text(
              timeText,
              style: TextStyle(fontSize: 8 * scale, height: 1.2, color: textColor),
            ),
            for (final line in infoLines)
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 8 * scale, height: 1.2, color: textColor),
              ),
          ],
        ),
      ),
    );
  }
}
