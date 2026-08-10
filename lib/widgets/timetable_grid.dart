import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/course.dart';
import '../models/schedule.dart';
import '../services/holiday_service.dart';
import '../services/schedule_math.dart';
import 'course_block.dart';

/// 课程表网格的横向滚动控制：用于把某一天的列滚动到屏幕中央。
class TimetableGridController {
  final ScrollController hScroll = ScrollController();
  double labelW = 0;

  /// 7 个星期的列宽（本学期模式下含并排课的列更宽）。
  List<double> dayWidths = const [];

  /// 把某一天的列滚动到屏幕中央。滚动视图未就绪时返回 false。
  bool scrollToDay(int day, {bool animate = true}) {
    if (!hScroll.hasClients || dayWidths.length != 7) return false;
    final viewport = hScroll.position.viewportDimension;
    var x = labelW;
    for (var d = 1; d < day; d++) {
      x += dayWidths[d - 1];
    }
    final offset = x + dayWidths[day - 1] / 2 - viewport / 2;
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
  // 基础尺寸：随缩放倍率 _scale 整体放大（列宽、行高、字号）。
  static const double baseLabelW = 54;
  static const double baseColW = 100; // 每列（星期）宽度，内容较多时横向滚动
  static const double baseRowH = 72;
  static const double baseHeaderH = 46;

  /// 运行时缩放倍率：Ctrl/Cmd+滚轮、触控板双指捏合调节。
  /// 不持久化，每次启动都是默认 1.0。
  double _scale = 1.0;
  static const double _minScale = 0.6;
  static const double _maxScale = 2.5;

  /// 本学期模式：同一格内并排多门课时，该列加宽的比例。
  static const double _sharedColFactor = 1.5;

  /// 触控板双指缩放基准（PointerPanZoom 的 scale 是相对手势起点的累计值）。
  double _panZoomBase = 1.0;

  /// 最近一次 build 计算的各列宽度（供滚动居中与缩放锚定使用）。
  List<double> _dayWidths = const [];

  double get _labelW => baseLabelW * _scale;
  double get _colW => baseColW * _scale;
  double get _rowH => baseRowH * _scale;
  double get _headerH => baseHeaderH * _scale;

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
    widget.controller.labelW = _labelW;
    widget.controller.dayWidths = _dayWidths;
    widget.controller.scrollToDay(DateTime.now().weekday, animate: false);
    if (remaining > 0) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _centerToday(remaining: remaining - 1));
    }
  }

  /// 缩放一档（Ctrl/Cmd+滚轮）：delta 为正放大、负缩小。
  void _zoomBy(double delta) => _applyScale(_scale + delta);

  /// 应用新缩放倍率，并保持视口中央的内容位置不变。
  void _applyScale(double v) {
    final next = v.clamp(_minScale, _maxScale);
    if (next == _scale) return;
    final ctrl = widget.controller;
    // 记录缩放前视口中央在内容中的相对位置。
    final oldTotal = _labelW + _dayWidths.fold(0.0, (a, b) => a + b);
    double? centerFrac;
    if (ctrl.hScroll.hasClients) {
      final viewport = ctrl.hScroll.position.viewportDimension;
      centerFrac = (ctrl.hScroll.offset + viewport / 2) / oldTotal;
    }
    setState(() => _scale = next);
    if (centerFrac != null) {
      // 闭包内捕获的非空副本：避免可空提升问题。
      final double frac = centerFrac;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !ctrl.hScroll.hasClients) return;
        final viewport = ctrl.hScroll.position.viewportDimension;
        final newTotal = _labelW + _dayWidths.fold(0.0, (a, b) => a + b);
        final newCenter = newTotal * frac;
        ctrl.hScroll.jumpTo((newCenter - viewport / 2)
            .clamp(0.0, ctrl.hScroll.position.maxScrollExtent));
      });
    }
  }

  /// 指针滚轮信号：按住 Ctrl/Cmd 时缩放，否则交给默认滚动。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _zoomBy(event.scrollDelta.dy < 0 ? 0.12 : -0.12);
    }
  }

  /// 触控板双指捏合开始：记录手势起点时的缩放倍率。
  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomBase = _scale;
  }

  /// 触控板双指捏合：scale 是相对手势起点的累计倍率。
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _applyScale(_panZoomBase * event.scale);
  }

  /// 各列宽度：本学期模式下，含并排多门课的列按 _sharedColFactor 加宽；
  /// 单周模式各列等宽。
  List<double> _dayWidthsOf(Map<String, List<_CellEntry>> cellMap) {
    if (!widget.semesterMode) {
      return [for (var i = 0; i < 7; i++) _colW];
    }
    final shared = <int>{};
    for (var w = 1; w <= 7; w++) {
      for (var p = 1; p <= widget.schedule.periodsPerDay; p++) {
        final entries = cellMap['${w}_$p'];
        if (entries == null ||
            entries.length < 2 ||
            entries.map((e) => e.course.uid).toSet().length < 2) {
          continue;
        }
        shared.add(w);
        break;
      }
    }
    return [
      for (var w = 1; w <= 7; w++)
        shared.contains(w) ? _colW * _sharedColFactor : _colW,
    ];
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

    // 计算各列宽度（本学期模式下含并排课的列加宽），供布局与滚动居中使用。
    _dayWidths = _dayWidthsOf(cellMap);
    // 同步到控制器，保证缩放后“跳转到某一天”仍用最新尺寸定位。
    widget.controller.labelW = _labelW;
    widget.controller.dayWidths = _dayWidths;
    final totalW = _labelW + _dayWidths.fold(0.0, (a, b) => a + b);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 外层 Listener 拦截 Ctrl/Cmd+滚轮与触控板双指手势做缩放；
        // 此时内层 Scrollable 通过 _ZoomWheelPhysics 拒绝消费指针信号，
        // 让事件冒泡到这里。普通滚轮与拖动滚动不受影响。
        return Listener(
          onPointerSignal: _onPointerSignal,
          onPointerPanZoomStart: _onPanZoomStart,
          onPointerPanZoomUpdate: _onPanZoomUpdate,
          child: SingleChildScrollView(
            controller: widget.controller.hScroll,
            scrollDirection: Axis.horizontal,
            physics: const _ZoomWheelPhysics(),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              physics: const _ZoomWheelPhysics(),
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
          width: _labelW,
          height: _headerH,
          child: Center(
            child: Text('节次',
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.outline)),
          ),
        ),
        for (var w = 1; w <= 7; w++)
          SizedBox(
            width: _dayWidths[w - 1],
            height: _headerH,
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
        width: _labelW,
        height: _rowH,
        child: Center(
          child: Text('$p',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ));
      children.addAll(_mealCells(p, _labelW, theme, showText: true));
    }
    return SizedBox(
      width: _labelW,
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
    final width = _dayWidths[w - 1];
    var p = 1;
    while (p <= widget.schedule.periodsPerDay) {
      final entries = cellMap['${w}_$p'];
      if (entries != null && entries.isNotEmpty) {
        var maxEnd = p;
        for (final e in entries) {
          if (e.time.endPeriod > maxEnd) maxEnd = e.time.endPeriod;
        }
        // 跨行块高度：覆盖的节次行高 + 期间各餐条高度。
        var h = (maxEnd - p + 1) * _rowH;
        for (var x = p; x < maxEnd; x++) {
          h += _mealHeight(x);
        }
        children.add(_spanBlock(entries, h, width, theme));
        // 块覆盖第 p..maxEnd 节；第 maxEnd 节之后的餐条补在块下方，
        // 否则该列少一段高度、与其它列错位（如课在饭前格子时餐条消失）。
        children.addAll(_mealCells(maxEnd, width, theme, showText: false));
        p = maxEnd + 1;
      } else {
        children.add(SizedBox(
          width: width,
          height: _rowH,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.45),
                  width: 0.6),
            ),
          ),
        ));
        children.addAll(_mealCells(p, width, theme, showText: false));
        p++;
      }
    }
    return SizedBox(
      width: width,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  // 课程跨行块：一节或多节课并排，整体高度跨多个节次。
  Widget _spanBlock(
      List<_CellEntry> entries, double height, double width, ThemeData theme) {
    // 本学期模式：同一门课在同格内的多条上课时间合并为一个方块
    // （如不同上课周/地点，块内每时段一行）；不同课程仍并排。
    // 单周模式：每条上课时间独立方块并排。
    final groups = <List<_CellEntry>>[];
    if (widget.semesterMode) {
      final byCourse = <String, List<_CellEntry>>{};
      for (final e in entries) {
        byCourse.putIfAbsent(e.course.uid, () => []).add(e);
      }
      groups.addAll(byCourse.values);
    } else {
      for (final e in entries) {
        groups.add([e]);
      }
    }
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        padding: EdgeInsets.all(2 * _scale),
        decoration: BoxDecoration(
          border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.45), width: 0.6),
        ),
        child: Row(
          children: [
            for (final group in groups)
              Expanded(
                child: CourseBlock(
                  course: group.first.course,
                  times: [for (final e in group) e.time],
                  showWeeks: widget.semesterMode,
                  scale: _scale,
                  onTap: () =>
                      widget.onCourseTap(group.first.course, group.first.time),
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

/// 网格缩放用的滚动物理：按住 Ctrl/Cmd 时拒绝消费指针滚轮事件，
/// 让事件冒泡到外层 Listener 的 [_onPointerSignal] 做缩放；
/// 普通滚轮（垂直滚动）与拖动滚动不受影响。
class _ZoomWheelPhysics extends ScrollPhysics {
  const _ZoomWheelPhysics({super.parent});

  @override
  _ZoomWheelPhysics applyTo(ScrollPhysics? ancestor) {
    return _ZoomWheelPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }
    return super.shouldAcceptUserOffset(position);
  }
}
