import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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

class _TimetableGridState extends State<TimetableGrid>
    with SingleTickerProviderStateMixin {
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

  /// 移动端触摸捏合：当前按下的指针位置（pointer -> 位置）。
  final Map<int, Offset> _touchPointers = {};

  /// 触摸捏合起点：两指初始间距与当时的缩放倍率。
  double? _pinchBaseDist;
  double? _pinchBaseScale;

  /// 最近一次 build 计算的各列宽度（供滚动居中与缩放锚定使用）。
  List<double> _dayWidths = const [];

  /// 单周模式「聚焦当天」：当前居中显示第几天（0 基，0=周一 … 6=周日）。
  /// 用拖动手势 + 动画驱动，而非 PageView —— 自定义 Stack 才能控制
  /// 「当天遮挡邻天」的图层叠放顺序（中心最后画、盖在最上层）。
  double _pageValue = DateTime.now().weekday - 1;

  /// 翻页动画：把 _pageValue 从 _pageFrom 平滑过渡到 _pageAnimTarget。
  late final AnimationController _pageAnim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
        ..addListener(_onPageAnimTick);
  double _pageFrom = 0;
  double _pageAnimTarget = 0;

  /// 水平拖动的起始页（拖动过程中连续更新 _pageValue）。
  double? _dragStartPage;

  /// 相邻卡片中心的间距（由布局阶段确定，拖动回调复用）。
  double _cardSpacing = 300;

  /// 单周模式聚焦视图共用的纵向滚动控制器：上下滑动时 7 张卡片一起动，
  /// 左右翻页时纵向位置保持一致、不会突然跳变。
  final ScrollController _dayVScroll = ScrollController();

  /// 当天卡片是否已按当前时间定位过纵向位置（切换课程表/周次/进入聚焦视图后重置）。
  bool _focusPositionsApplied = false;

  double get _labelW => baseLabelW * _scale;
  double get _colW => baseColW * _scale;
  double get _rowH => baseRowH * _scale;
  double get _headerH => baseHeaderH * _scale;

  /// 单周模式聚焦视图：卡片顶部日期标题的高度。
  double get _focusHeaderH => 44 * _scale;

  /// 聚焦视图左侧节次标签列宽度：只显示节次编号，比学期视图的标签列更窄。
  double get _focusLabelW => 34 * _scale;

  /// 聚焦视图单日卡片内容的总高度：标题 + 各节次行 + 餐条高度之和。
  double _focusContentHeight() {
    var h = _focusHeaderH;
    for (var p = 1; p <= widget.schedule.periodsPerDay; p++) {
      h += _rowH + _mealHeight(p);
    }
    return h;
  }

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
        (!widget.semesterMode && oldWidget.week != widget.week) ||
        (oldWidget.semesterMode && !widget.semesterMode)) {
      _focusPositionsApplied = false;
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
    if (!widget.semesterMode) {
      // 聚焦视图：直接切到「今天」那一页。
      final today = DateTime.now().weekday - 1;
      if (_pageValue != today) {
        setState(() => _pageValue = today.toDouble());
      }
    } else {
      widget.controller.labelW = _labelW;
      widget.controller.dayWidths = _dayWidths;
      widget.controller.scrollToDay(DateTime.now().weekday, animate: false);
    }
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

  /// 移动端触摸双指捏合：按两指间距相对起点的变化驱动缩放。
  /// 单指时不动（长度不足 2），因此不会与网格的拖动滚动抢手势。
  void _updatePinch() {
    if (_touchPointers.length != 2) return;
    final pts = _touchPointers.values.toList();
    final dist = (pts[0] - pts[1]).distance;
    if (_pinchBaseDist == null || _pinchBaseDist! <= 0) {
      _pinchBaseDist = dist;
      _pinchBaseScale = _scale;
      return;
    }
    _applyScale(_pinchBaseScale! * (dist / _pinchBaseDist!));
  }

  void _onTouchPointerDown(PointerDownEvent e) {
    _touchPointers[e.pointer] = e.localPosition;
    _updatePinch();
  }

  void _onTouchPointerMove(PointerMoveEvent e) {
    if (_touchPointers.containsKey(e.pointer)) {
      _touchPointers[e.pointer] = e.localPosition;
      _updatePinch();
    }
  }

  void _onTouchPointerEnd(PointerEvent e) {
    if (_touchPointers.remove(e.pointer) != null) {
      _pinchBaseDist = null;
      _pinchBaseScale = null;
    }
  }

  void _onTouchPointerCancel(PointerCancelEvent e) => _onTouchPointerEnd(e);

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
    _pageAnim.dispose();
    _dayVScroll.dispose();
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
          // 移动端触摸双指捏合缩放（桌面触控板走上面的 PanZoom 事件）。
          onPointerDown: _onTouchPointerDown,
          onPointerMove: _onTouchPointerMove,
          onPointerUp: _onTouchPointerEnd,
          onPointerCancel: _onTouchPointerCancel,
          child: widget.semesterMode
              ? _buildSemesterView(theme, headerWeek, cellMap, totalW)
              : _buildFocusView(theme, headerWeek, cellMap),
        );
      },
    );
  }

  /// 本学期模式的整张网格：左侧节次列 + 7 天列，外层横向滚动、内层纵向滚动。
  Widget _buildSemesterView(ThemeData theme, int headerWeek,
      Map<String, List<_CellEntry>> cellMap, double totalW) {
    return SingleChildScrollView(
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
    );
  }

  /// 单周模式「聚焦当天」视图：
  /// - 当天卡片居中、最宽、最清晰，左右两天缩小、虚化、被当天遮挡一点；
  /// - 左右滑动切换日期；
  /// - 外层共用一个纵向滚动，上下滑动时 7 张卡片整体一起动；
  /// - 首帧按当前时间定位当天纵向位置（正在上/下一节/当天最后一节）。
  Widget _buildFocusView(
      ThemeData theme, int headerWeek, Map<String, List<_CellEntry>> cellMap) {
    return LayoutBuilder(builder: (context, constraints) {
      final vw = constraints.maxWidth;
      // 左侧节次标签列占 _focusLabelW，卡片区为剩余宽度。
      final labelW = _focusLabelW;
      final areaW = math.max(vw - labelW, 1.0);
      // 桌面端也保持手机般的居中比例：按最小宽度排版并居中显示。
      final effW = math.min(areaW, 520.0);
      _cardSpacing = effW * 0.74;
      final cardW = effW * 0.88;
      final contentH = _focusContentHeight();
      final page = _pageValue;
      final cards = <(double, Widget)>[];
      for (var w = 1; w <= 7; w++) {
        // 星期序号越大越靠右（周一在最左、周日在最右）。
        final d = (w - 1) - page;
        if (d.abs() > 1.15) continue; // 只构建可见的卡片
        final t = d.abs().clamp(0.0, 1.0);
        cards.add((
          d.abs(),
          _buildDayCard(w, d, t, areaW, cardW, theme, headerWeek, cellMap),
        ));
      }
      // 距离中心越远越先画，最后画的「当天」盖在邻天之上形成遮挡。
      cards.sort((a, b) => b.$1.compareTo(a.$1));
      if (!_focusPositionsApplied) {
        _focusPositionsApplied = true;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _applyFocusPositions(cellMap));
      }
      return ClipRect(
        // 整个聚焦视图共用一条纵向滚动：上下滑动卡片与左侧标签列一起动，
        // 左右翻页时纵向位置保持一致、不会突然跳变。
        child: SingleChildScrollView(
          controller: _dayVScroll,
          physics: const _ZoomWheelPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧节次编号列：顶部留出卡片标题高度，与各卡片的行对齐，
              // 并随卡片一起纵向滚动；餐条位置留空不写字、不上色。
              Column(
                children: [
                  SizedBox(height: _focusHeaderH),
                  _buildLabelColumn(theme,
                      width: _focusLabelW, showMealText: false),
                ],
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: _onPageDragStart,
                  onHorizontalDragUpdate: _onPageDragUpdate,
                  onHorizontalDragEnd: _onPageDragEnd,
                  onHorizontalDragCancel: _onPageDragCancel,
                  child: ClipRect(
                    // 把卡片裁切在卡片区内：邻天卡片不会溢到左侧标签列上
                    // （否则半透明的卡片会盖住节次编号，看起来像“透明的”）。
                    child: SizedBox(
                      width: areaW,
                      height: contentH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [for (final c in cards) c.$2],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 一张「当天卡片」：按与中心页的偏移 [d] 平移，按距离 [t] 缩小、虚化、变暗。
  Widget _buildDayCard(int w, double d, double t, double vw, double cardW,
      ThemeData theme, int headerWeek, Map<String, List<_CellEntry>> cellMap) {
    final dx = d * _cardSpacing;
    final scale = 1 - 0.1 * t;
    final blur = 1.8 * t;
    final opacity = 1 - 0.3 * t;
    Widget body = _buildDayCardBody(w, cardW, theme, headerWeek, cellMap);
    if (blur > 0) {
      body = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: body,
      );
    }
    return Positioned(
      left: vw / 2 + dx - cardW / 2,
      top: 0,
      bottom: 0,
      width: cardW,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Opacity(opacity: opacity, child: body),
      ),
    );
  }

  /// 卡片主体：顶部日期标题 + 单日课程列。
  /// 卡片本身不独立滚动——整个聚焦视图共用一个外层纵向滚动
  /// （[_buildFocusView] 里的 `_dayVScroll`），上下滑动时 7 张卡片一起动。
  Widget _buildDayCardBody(int w, double cardW, ThemeData theme, int headerWeek,
      Map<String, List<_CellEntry>> cellMap) {
    final isToday = _isToday(w, headerWeek);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 5 * _scale),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16 * _scale),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isToday ? 0.2 : 0.12),
            blurRadius: 14 * _scale,
            offset: Offset(0, 4 * _scale),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildFocusDayHeader(w, headerWeek, theme, isToday),
          Expanded(
            child: _buildDayColumn(w, cellMap, theme,
                overriddenWidth: cardW - 10 * _scale, showMealText: true),
          ),
        ],
      ),
    );
  }

  /// 第 [week] 周、星期 [w] 那天是否就是今天（按实际日期比较，
  /// 而不是只看周几——否则切到其它周后同周几会被误标为「今天」）。
  bool _isToday(int w, int week) {
    final now = DateTime.now();
    final day = ScheduleMath.dateOf(week, w, widget.schedule);
    return day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
  }

  /// 当天卡片顶部的日期标题：星期 + 日期 + 调休徽标；今天高亮。
  Widget _buildFocusDayHeader(
      int w, int headerWeek, ThemeData theme, bool isToday) {
    final primary = theme.colorScheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8 * _scale),
      decoration: BoxDecoration(
        color: isToday
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : null,
        border: Border(
            bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.4))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isToday) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('今天',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            ScheduleMath.weekdayName(w),
            style: TextStyle(
              fontSize: 16 * _scale,
              fontWeight: FontWeight.w700,
              color: isToday ? primary : theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            ScheduleMath.formatMd(
                ScheduleMath.dateOf(headerWeek, w, widget.schedule)),
            style: TextStyle(
                fontSize: 12 * _scale, color: theme.colorScheme.outline),
          ),
          _holidayBadge(theme, headerWeek, w),
        ],
      ),
    );
  }

  // ---- 聚焦视图：横向翻页（拖动 + 动画） ----

  void _onPageDragStart(DragStartDetails d) => _dragStartPage = _pageValue;

  void _onPageDragUpdate(DragUpdateDetails d) {
    final start = _dragStartPage;
    if (start == null) return;
    setState(() {
      _pageValue = (start - d.delta.dx / _cardSpacing).clamp(0.0, 6.0);
    });
  }

  void _onPageDragEnd(DragEndDetails d) {
    final start = _dragStartPage ?? _pageValue;
    _dragStartPage = null;
    var target = _pageValue.round().clamp(0, 6);
    final v = d.velocity.pixelsPerSecond.dx;
    // 快速滑动时额外多翻一页，方向与滑动方向一致。
    if (v.abs() > 500 && start.round() == target) {
      target = (v < 0 ? target + 1 : target - 1).clamp(0, 6);
    }
    _animatePageTo(target.toDouble());
  }

  void _onPageDragCancel() {
    _dragStartPage = null;
    _animatePageTo(_pageValue.round().clamp(0, 6).toDouble());
  }

  void _animatePageTo(double target) {
    if (target == _pageValue) {
      setState(() => _pageValue = target);
      return;
    }
    _pageFrom = _pageValue;
    _pageAnimTarget = target;
    _pageAnim.forward(from: 0);
  }

  void _onPageAnimTick() {
    if (!mounted) return;
    final t = Curves.easeOutCubic.transform(_pageAnim.value);
    setState(() {
      _pageValue = _pageFrom + (_pageAnimTarget - _pageFrom) * t;
    });
  }

  // ---- 聚焦视图：按时间的纵向定位 ----

  /// 首帧后把所有卡片共用的纵向滚动定位好：按当前时间定位到当天
  /// 「正在上的课 / 下一节 / 当天最后一节」。7 张卡片同用一个滚动，
  /// 翻页时纵向位置保持一致、不会突然跳变。
  void _applyFocusPositions(Map<String, List<_CellEntry>> cellMap) {
    if (!mounted || !_dayVScroll.hasClients) return;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final target = _targetPeriodForNow(now.weekday, nowMin, cellMap);
    if (target == null) return;
    // 目标节次顶部的纵向偏移 = 之前各节的行高 + 期间餐条高度之和。
    var offset = 0.0;
    for (var p = 1; p < target; p++) {
      offset += _rowH + _mealHeight(p);
    }
    _dayVScroll.jumpTo(
        offset.clamp(0.0, _dayVScroll.position.maxScrollExtent));
  }

  /// 按当前时间选择定位目标节次：正在上的课 > 下一节 > 当天最后一节。
  int? _targetPeriodForNow(
      int w, int nowMin, Map<String, List<_CellEntry>> cellMap) {
    final periods = <int>[];
    for (var p = 1; p <= widget.schedule.periodsPerDay; p++) {
      final entries = cellMap['${w}_$p'];
      if (entries != null && entries.isNotEmpty) periods.add(p);
    }
    if (periods.isEmpty) return null;
    final building = widget.schedule.firstBuilding;
    if (building != null) {
      // 正在上：当前时间落在某节课的 [开始, 结束) 内。
      for (final p in periods) {
        final pt = building.timeOf(p);
        if (pt == null) continue;
        final s = ScheduleMath.timeToMinutes(pt.start);
        final e = ScheduleMath.timeToMinutes(pt.end);
        if (nowMin >= s && nowMin < e) return p;
      }
      // 下一节：开始时间晚于当前的最早一节。
      for (final p in periods) {
        final pt = building.timeOf(p);
        if (pt == null) continue;
        if (ScheduleMath.timeToMinutes(pt.start) > nowMin) return p;
      }
    }
    // 都已下课（或没有楼宇时间）：定位到当天最后一节。
    return periods.last;
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
  // [width] 非空时使用该宽度（聚焦视图的窄标签列）；
  // [showMealText] 为 false 时餐条位置只留空（不写字、不上背景色）。
  Widget _buildLabelColumn(ThemeData theme,
      {double? width, bool showMealText = true}) {
    final w = width ?? _labelW;
    final children = <Widget>[];
    for (var p = 1; p <= widget.schedule.periodsPerDay; p++) {
      children.add(SizedBox(
        width: w,
        height: _rowH,
        child: Center(
          child: Text('$p',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ));
      if (showMealText) {
        children.addAll(_mealCells(p, w, theme, showText: true));
      } else {
        children.add(SizedBox(width: w, height: _mealHeight(p)));
      }
    }
    return SizedBox(
      width: w,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  // 单列（某星期）内容：空节占位 + 课程跨行块 + 餐条占位。
  // [overriddenWidth] 非空时用该宽度（单周模式聚焦视图的宽卡片）；
  // [showMealText] 为真时餐条上写「午餐/晚餐」文字（单周模式聚焦卡片）。
  Widget _buildDayColumn(
    int w,
    Map<String, List<_CellEntry>> cellMap,
    ThemeData theme, {
    double? overriddenWidth,
    bool showMealText = false,
  }) {
    final children = <Widget>[];
    final width = overriddenWidth ?? _dayWidths[w - 1];
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
        children.addAll(_mealCells(maxEnd, width, theme, showText: showMealText));
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
        children.addAll(_mealCells(p, width, theme, showText: showMealText));
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
                  // 单周模式显示课程编号；卡片更宽，字号略放大提升可读性。
                  showId: !widget.semesterMode,
                  scale: widget.semesterMode ? _scale : _scale * 1.2,
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
