import 'package:flutter/material.dart';

import '../models/course.dart';

/// 课程表中的单个课程方块：显示课程名、教师、上下课时间、地点。
class CourseBlock extends StatelessWidget {
  final Course course;
  final ClassTime time;
  final VoidCallback onTap;

  const CourseBlock({
    super.key,
    required this.course,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(course.colorValue);
    final textColor =
        color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final teacher = (course.teacher ?? '').trim();
    // 地点：单节覆盖优先，否则用课程总体地点。
    // 楼宇与房号之间不加空格（格子空间有限，如「第一教学楼A101」）。
    final loc =
        (time.location?.isEmpty ?? true) ? course.location : time.location!;
    final b = loc.building.trim();
    final r = loc.room.trim();
    final location = b.isEmpty ? r : (r.isEmpty ? b : '$b$r');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
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
                fontSize: 10.5,
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
                style: TextStyle(fontSize: 8.5, height: 1.2, color: textColor),
              ),
            Text(
              '${time.start}-${time.end}',
              style: TextStyle(fontSize: 8, height: 1.2, color: textColor),
            ),
            if (location.isNotEmpty)
              Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 8, height: 1.2, color: textColor),
              ),
          ],
        ),
      ),
    );
  }
}
