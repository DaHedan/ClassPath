import 'dart:math' as math;

import 'package:flutter/material.dart';

// 表盘尺寸常量（顶层可见，供状态类与绘制器共用）。
const double _dialSize = 260; // 表盘直径
const double _outerR = 118; // 外圈数字中心半径
const double _innerR = 74; // 内圈数字中心半径
const double _dotR = 20; // 数字背景圆半径
const double _centerR = 34; // 中心留白圆半径

/// 自定义时间选择对话框。
///
/// 小时表盘为两圈（内圈 1-12、外圈 13-24），内外圈底色用略有差异的
/// 颜色区分，比 Flutter 自带 M3 时间盘的“两圈字”更易辨认。
Future<TimeOfDay?> showClassPathTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _TimeDialPicker(initial: initialTime),
  );
}

class _TimeDialPicker extends StatefulWidget {
  final TimeOfDay initial;

  const _TimeDialPicker({required this.initial});

  @override
  State<_TimeDialPicker> createState() => _TimeDialPickerState();
}

class _TimeDialPickerState extends State<_TimeDialPicker>
    with SingleTickerProviderStateMixin {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;
  bool _pickingHour = true;

  // 动画：值变化时指针平滑滑动、选中数字脉冲放大。
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late int _lastHour = _hour;
  late int _lastMinute = _minute;
  late bool _lastHourMode = _pickingHour;

  // 拖动状态：按下时记录起点、移动超过容差进入拖动。
  Offset? _downPos;
  bool _dragging = false;
  // 本次按下是否选中了有效值（中心留白区按下不算，抬起时不切模式）。
  bool _selectedThisPress = false;

  String get _hh => _hour.toString().padLeft(2, '0');
  String get _mm => _minute.toString().padLeft(2, '0');

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// 记录旧值、应用修改并重放过渡动画。
  /// [animate] 为 false（拖动）时直接跳转到新值，避免指针滞后。
  void _setValue(VoidCallback change, {bool animate = true}) {
    setState(() {
      if (animate) {
        _lastHour = _hour;
        _lastMinute = _minute;
        _lastHourMode = _pickingHour;
      }
      change();
      if (animate) {
        _anim.forward(from: 0);
      } else {
        _lastHour = _hour;
        _lastMinute = _minute;
        _lastHourMode = _pickingHour;
        _anim.value = 1;
      }
    });
  }

  /// 根据点击/拖动位置选择小时或分钟。
  /// [center] 为表盘中心（相对手势局部坐标）。
  /// [animate] 为 false（拖动）时直接跟随，不做过渡动画。
  /// 返回是否选中了有效值（中心留白区返回 false）。
  bool _onDial(Offset local, {required Offset center, bool animate = true}) {
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final r = math.sqrt(dx * dx + dy * dy);
    if (r < 28) return false; // 中心留白区不选择
    var angle = math.atan2(dy, dx) + math.pi / 2; // 顶部为 0
    if (angle < 0) angle += 2 * math.pi;
    if (angle >= 2 * math.pi) angle -= 2 * math.pi;
    _setValue(() {
      if (_pickingHour) {
        final index = (angle / (2 * math.pi / 12)).round() % 12; // 顶部起 0..11
        // 内圈 1-12，顶部为 12；外圈 13-24，顶部为 24（即 0 点）。
        final inner = r < (_innerR + _outerR) / 2;
        if (inner) {
          _hour = ((index + 11) % 12) + 1;
        } else {
          _hour = index == 0 ? 0 : index + 12;
        }
      } else {
        // 分钟：一圈 60 个刻度，支持任意非 5 倍数。
        final index = (angle / (2 * math.pi / 60)).round() % 60;
        _minute = index;
      }
    }, animate: animate);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('选择时间'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _modeButton(theme, '时', _pickingHour, () {
                  _setValue(() => _pickingHour = true);
                }),
                const SizedBox(width: 24),
                Text(
                  '$_hh:$_mm',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 24),
                _modeButton(theme, '分', !_pickingHour, () {
                  _setValue(() => _pickingHour = false);
                }),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: _dialSize,
              height: _dialSize,
              // 用 Listener 自己管理按下/拖动/抬起，避免 onTapDown 与
              // onPanUpdate 手势竞争导致点选偶尔丢失、拖动跳到别处。
              child: Listener(
                onPointerDown: (e) {
                  _downPos = e.localPosition;
                  _dragging = false;
                  // 按下位置立即选中（点哪选哪），不用等手势竞技场裁决。
                  _selectedThisPress = _onDial(e.localPosition,
                      center: const Offset(_dialSize / 2, _dialSize / 2));
                },
                onPointerMove: (e) {
                  if (_downPos == null) return;
                  if (!_dragging) {
                    // 未超过点击容差前仍是点按，交给抬起时的切换逻辑。
                    if ((e.localPosition - _downPos!).distance < 18) return;
                    _dragging = true;
                  }
                  final ok = _onDial(e.localPosition,
                      center: const Offset(_dialSize / 2, _dialSize / 2),
                      animate: false);
                  if (ok) _selectedThisPress = true;
                },
                onPointerUp: (_) {
                  _downPos = null;
                  _dragging = false;
                  // 选中过有效值才从小时切到分钟，中心留白区的点按不算。
                  if (_pickingHour && _selectedThisPress) {
                    setState(() => _pickingHour = false);
                  }
                  _selectedThisPress = false;
                },
                onPointerCancel: (_) {
                  _downPos = null;
                  _dragging = false;
                  if (_pickingHour && _selectedThisPress) {
                    setState(() => _pickingHour = false);
                  }
                  _selectedThisPress = false;
                },
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) => CustomPaint(
                    size: const Size(_dialSize, _dialSize),
                    painter: _DialPainter(
                      hourMode: _pickingHour,
                      hour: _hour,
                      minute: _minute,
                      scheme: theme.colorScheme,
                      anim: Curves.easeOutCubic.transform(_anim.value),
                      lastHour: _lastHour,
                      lastMinute: _lastMinute,
                      lastHourMode: _lastHourMode,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute)),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _modeButton(
      ThemeData theme, String label, bool active, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: active
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        foregroundColor: active
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
        minimumSize: const Size(40, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }
}

/// 表盘绘制：内外圈底色 + 数字 + 选中指针。
class _DialPainter extends CustomPainter {
  final bool hourMode;
  final int hour; // 0-23
  final int minute;
  final ColorScheme scheme;

  /// 过渡动画进度 0-1（值变化后指针滑动、数字脉冲）。
  final double anim;
  final int lastHour;
  final int lastMinute;
  final bool lastHourMode;

  const _DialPainter({
    required this.hourMode,
    required this.hour,
    required this.minute,
    required this.scheme,
    required this.anim,
    required this.lastHour,
    required this.lastMinute,
    required this.lastHourMode,
  });

  double _angleOf(int index) => index * (2 * math.pi / 12) - math.pi / 2;

  /// 指针端点位置（不含中心小圆）。
  Offset _handEnd(Offset center, bool mode, int h, int m) {
    if (mode) {
      final inner = h >= 1 && h <= 12;
      final index = inner ? h % 12 : (h == 0 ? 0 : h - 12);
      return center +
          Offset(math.cos(_angleOf(index)), math.sin(_angleOf(index))) *
              (inner ? _innerR : _outerR);
    }
    final angle = m * (2 * math.pi / 60) - math.pi / 2;
    return center +
        Offset(math.cos(angle), math.sin(angle)) * _outerR;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 底色：外圈一层、内圈一层、中心留白一层。
    // 内外圈用同一色相、不同明度（内圈向 surface 混合），
    // 使浅色/深色模式下差异程度保持一致。
    final innerColor =
        Color.lerp(scheme.primaryContainer, scheme.surface, 0.4)!;
    canvas.drawCircle(
        center, _outerR + _dotR, Paint()..color = scheme.primaryContainer);
    canvas.drawCircle(center, _innerR + _dotR, Paint()..color = innerColor);
    canvas.drawCircle(
        center, _centerR, Paint()..color = scheme.surfaceContainerHighest);

    if (hourMode) {
      // 小时：内圈 1-12，外圈 13-24（顶部为 24）。
      for (var h = 1; h <= 12; h++) {
        final index = h % 12;
        final selected = hour == h;
        _drawNumber(canvas, '$h',
            center +
                Offset(math.cos(_angleOf(index)), math.sin(_angleOf(index))) *
                    _innerR,
            selected: selected);
      }
      for (var h = 13; h <= 24; h++) {
        final index = h % 12;
        final value = h == 24 ? 0 : h;
        final selected = hour == value;
        _drawNumber(canvas, '$h',
            center +
                Offset(math.cos(_angleOf(index)), math.sin(_angleOf(index))) *
                    _outerR,
            selected: selected);
      }
    } else {
      // 分钟：一圈 60 个刻度，每 5 的倍数显示数字（0,5,...,55），
      // 其余为小刻度点；选中任意分钟都有高亮。
      for (var m = 0; m < 60; m++) {
        final angle = m * (2 * math.pi / 60) - math.pi / 2;
        final pos = center +
            Offset(math.cos(angle), math.sin(angle)) * _outerR;
        final selected = minute == m;
        if (m % 5 == 0) {
          _drawNumber(canvas, '$m', pos, selected: selected);
        } else {
          canvas.drawCircle(
            pos,
            selected ? 4.5 : 2.5,
            Paint()
              ..color = selected
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.45),
          );
        }
      }
    }

    // 指针：从旧位置平滑滑动到新位置（跨模式也平滑过渡）。
    final from = _handEnd(center, lastHourMode, lastHour, lastMinute);
    final to = _handEnd(center, hourMode, hour, minute);
    final end = Offset.lerp(from, to, anim)!;
    canvas.drawLine(
      center,
      end,
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 5, Paint()..color = scheme.primary);
  }

  void _drawNumber(
      Canvas canvas, String text, Offset pos, {required bool selected}) {
    if (selected) {
      // 选中圆：动画期间轻微放大，形成“按下”脉冲。
      final r = _dotR * (1 + 0.25 * (1 - anim));
      canvas.drawCircle(pos, r, Paint()..color = scheme.primary);
    }
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.hourMode != hourMode ||
      old.hour != hour ||
      old.minute != minute ||
      old.anim != anim ||
      old.lastHour != lastHour ||
      old.lastMinute != lastMinute ||
      old.lastHourMode != lastHourMode ||
      old.scheme != scheme;
}
