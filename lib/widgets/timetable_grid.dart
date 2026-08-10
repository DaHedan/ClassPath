import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/schedule.dart';
import '../services/holiday_service.dart';
import '../services/schedule_math.dart';
import 'course_block.dart';

/// 课程表网格的横向滚动控制：用于把某一天的列滚动到屏幕中央。
class TimetableGridController {
  final ScrollController hScroll = ScrollController();
  double labelW = 0;
  double colW = 0;

  /// 把某一天的列滚动到屏幕中央。滚动视图未就绪时返回 false。
  bool scrollToDay(int day, {bool animate = true}) {
    if (!hScroll.hasClients) return false;
    final viewport = hScroll.position.viewportDimension;
    final offset = labelW + (day - 1) * colW + colW / 2 - viewport / 2;
    final clamped = offset.clamp(0.0, hScroll.position.maxScrollExtent);
    if (animate) {
      hScroll.animateTo(clamped,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      hScroll.jumpTo(clamped);
    }
    return true;
  }
}

class _CellEntry {
  final Course course;
  final ClassTime time;

  _CellEntry(this.course, this.time);
}

/// 课程表网格。
///
/// - 横向可左右滑动，默认当天那列位于屏幕中央；
/// - 纵向滚动浏览全部节次；
/// - 单周模式按所选周过滤课程；本学期模式不分周，同一格子内多门课程左右分列；
/// - 单周模式下按日期应用节假日调休：放假停课；调休补班日按课程表的
///   调休安排（RescheduleDay）搬入「原本日期」那天的课。
class TimetableGrid extends StatefulWidget {
  final Schedule schedule;
  final List<Course> courses;
  final int week;
  final bool semesterMode;
  final TimetableGridController controller;
  final void Function(Course course, ClassTime time) onCourseTap;

  /// 国务院节假日调休缓存：date("YYYY-MM-DD") -> 是否放假。
  final Map<String, bool> holidays;

  const TimetableGrid({
    super.key,
    required this.schedule,
    required this.courses,
    required this.week,
    required this.semesterMode,
    required this.controller,
    required this.onCourseTap,
    required this.holidays,
  });

  @override
  State<TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<TimetableGrid> {
  static const double labelW = 54;
  static const double colW = 68;
  static const double rowH = 72;
  static const double headerH = 46;

  @override
  void initState() {
    super.initState();
    _centerTodayAfterFrame();
  }

  @override
  void didUpdateWidget(TimetableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换课程表或切换周次后，都重新把当天列定位到中央。
    // 注意：不要按“所选周课程最集中的列”定位——课程集中在周一时居中偏移为负，
    // 被 clamp 到 0 会导致视图贴左（用户反馈的“跑左边”问题）。
    if (oldWidget.schedule.id != widget.schedule.id ||
        (!widget.semesterMode && oldWidget.week != widget.week)) {
      _centerTodayAfterFrame();
    }
  }

  /// 首帧布局完成后把当天列滚动到屏幕中央。
  void _centerTodayAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerToday(remaining: 2));
  }

  /// 居中到当天列；连续几帧重复确认，兜底滚动位置被后续布局（如
  /// 底部考试面板高度变化）重置、或首帧尚未就绪的情况。
  void _centerToday({required int remaining}) {
    if (!mounted) return;
    widget.controller.labelW = labelW;
    widget.controller.colW = colW;
    widget.controller.scrollToDay(DateTime.now().weekday, animate: false);
    if (remaining > 0) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _centerToday(remaining: remaining - 1));
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerWeek = widget.semesterMode
        ? ScheduleMath.currentWeekOfNow(widget.schedule)
        : widget.week;
    const totalW = labelW + colW * 7;

    // 统计每个「星期x + 第y节」格子里的课程（挂在节次段的起始节下）。
    final cellMap = <String, List<_CellEntry>>{};
    // 单周模式下按调休安排搬课：原本星期几 -> 搬到补班日所在星期几
    // （仅当补班日落在所选周才生效）。
    final movedWeekday = <int, int>{};
    if (!widget.semesterMode) {
      for (final r in widget.schedule.reschedules) {
        final target = DateTime.parse(r.date);
        if (ScheduleMath.weekNumberOf(widget.schedule, target) !=
            widget.week) {
          continue;
        }
        final src = DateTime.parse(r.source);
        movedWeekday[src.weekday] = target.weekday;
      }
    }
    for (final course in widget.courses) {
      if (course.scheduleId != widget.schedule.id) continue;
      for (final ct in course.classTimes) {
        // 每组上课时间独立控制上课周：null 表示全部周，否则仅所选周显示。
        if (!widget.semesterMode &&
            ct.weeks != null &&
            !ct.weeks!.contains(widget.week)) {
          continue;
        }
        if (!widget.semesterMode) {
          // 调休搬课：该星期的课整体挪到补班日所在列，原列不再渲染。
          final movedTo = movedWeekday[ct.weekday];
          if (movedTo != null) {
            cellMap
                .putIfAbsent('${movedTo}_${ct.startPeriod}', () => [])
                .add(_CellEntry(course, ct));
            continue;
          }
          // 放假日的课停上（隐藏，不占位）。
          final date =
              ScheduleMath.dateOf(widget.week, ct.weekday, widget.schedule);
          if (HolidayService.isRest(widget.holidays,
              ScheduleMath.dateStr(date))) {
            continue;
          }
        }
        final key = '${ct.weekday}_${ct.startPeriod}';
        cellMap.putIfAbsent(key, () => []).add(_CellEntry(course, ct));
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: widget.controller.hScroll,
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SizedBox(
              width: totalW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeaderRow(headerWeek, theme),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabelColumn(theme),
                      for (var w = 1; w <= 7; w++)
                        _buildDayColumn(w, cellMap, theme),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(int headerWeek, ThemeData theme) {
    return Row(
      // 不要使用 stretch：该行位于纵向滚动视图（无界高度）内，
      // stretch 会把子项高度强制为无穷大并导致布局异常。
      children: [
        SizedBox(
          width: labelW,
          height: headerH,
          child: Center(
            child: Text('节次',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.outline)),
          ),
        ),
        for (var w = 1; w <= 7; w++)
          SizedBox(
            width: colW,
            height: headerH,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ScheduleMath.weekdayName(w),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    if (!widget.semesterMode)
                      _holidayBadge(theme, headerWeek, w),
                  ],
                ),
                Text(
                  ScheduleMath.formatMd(
                      ScheduleMath.dateOf(headerWeek, w, widget.schedule)),
                  style: TextStyle(
                      fontSize: 9, color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // 单周模式下表头的调休徽标：放假日标「休」，调休补班日标「班」。
  Widget _holidayBadge(ThemeData theme, int week, int weekday) {
    final date = ScheduleMath.dateOf(week, weekday, widget.schedule);
    final v = widget.holidays[ScheduleMath.dateStr(date)];
    if (v == null) return const SizedBox.shrink();
    final isRest = v;
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
      decoration: BoxDecoration(
        color: isRest
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isRest ? '休' : '班',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: isRest
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }

  // 左侧节次标签列：每节一行 + 对应餐条占位，与右侧各列保持垂直对齐。
  Widget _buildLabelColumn(ThemeData theme) {
    final children = <Widget>[];
    for (var p = 1; p <= widget.schedule.periodsPerDay; p++) {
      children.add(SizedBox(
        width: labelW,
        height: rowH,
        child: Center(
          child: Text('$p',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ));
      children.addAll(_mealCells(p, labelW, theme, showText: true));
    }
    return SizedBox(
      width: labelW,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  // 单列（某星期）内容：空节占位 + 课程跨行块 + 餐条占位。
  Widget _buildDayColumn(
    int w,
    Map<String, List<_CellEntry>> cellMap,
    ThemeData theme,
  ) {
    final children = <Widget>[];
    var p = 1;
    while (p <= widget.schedule.periodsPerDay) {
      final entries = cellMap['${w}_$p'];
      if (entries != null && entries.isNotEmpty) {
        var maxEnd = p;
        for (final e in entries) {
          if (e.time.endPeriod > maxEnd) maxEnd = e.time.endPeriod;
        }
        // 跨行块高度：覆盖的节次行高 + 期间各餐条高度。
        var h = (maxEnd - p + 1) * rowH;
        for (var x = p; x < maxEnd; x++) {
          h += _mealHeight(x);
        }
        children.add(_spanBlock(entries, h, theme));
        // 块覆盖第 p..maxEnd 节；第 maxEnd 节之后的餐条补在块下方，
        // 否则该列少一段高度、与其它列错位（如课在饭前格子时餐条消失）。
        children.addAll(_mealCells(maxEnd, colW, theme, showText: false));
        p = maxEnd + 1;
      } else {
        children.add(SizedBox(
          width: colW,
          height: rowH,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.45),
                  width: 0.6),
            ),
          ),
        ));
        children.addAll(_mealCells(p, colW, theme, showText: false));
        p++;
      }
    }
    return SizedBox(
      width: colW,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  // 课程跨行块：一节或多节课并排，整体高度跨多个节次。
  Widget _spanBlock(
      List<_CellEntry> entries, double height, ThemeData theme) {
    return SizedBox(
      width: colW,
      height: height,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.45), width: 0.6),
        ),
        child: Row(
          children: [
            for (final e in entries)
              Expanded(
                child: CourseBlock(
                  course: e.course,
                  time: e.time,
                  onTap: () => widget.onCourseTap(e.course, e.time),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 第 [period] 节后的餐条总高度。
  double _mealHeight(int period) {
    var h = 0.0;
    if (widget.schedule.lunch.enabled &&
        widget.schedule.lunch.afterPeriod == period) {
      h += 24;
    }
    if (widget.schedule.dinner.enabled &&
        widget.schedule.dinner.afterPeriod == period) {
      h += 24;
    }
    return h;
  }

  // 第 [period] 节后的餐条条（一条午餐/一条晚餐，高度各 24）。
  List<Widget> _mealCells(
      int period, double width, ThemeData theme,
      {required bool showText}) {
    final cells = <Widget>[];
    if (widget.schedule.lunch.enabled &&
        widget.schedule.lunch.afterPeriod == period) {
      cells.add(
          _mealBar(theme, width, showText ? widget.schedule.lunch.label : null));
    }
    if (widget.schedule.dinner.enabled &&
        widget.schedule.dinner.afterPeriod == period) {
      cells.add(_mealBar(
          theme, width, showText ? widget.schedule.dinner.label : null));
    }
    return cells;
  }

  Widget _mealBar(ThemeData theme, double width, String? text) {
    return Container(
      width: width,
      height: 24,
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: text == null
          ? null
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
            ),
    );
  }
}
