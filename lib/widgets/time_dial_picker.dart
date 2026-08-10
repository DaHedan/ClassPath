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

class _TimeDialPickerState extends State<_TimeDialPicker> {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;
  bool _pickingHour = true;

  String get _hh => _hour.toString().padLeft(2, '0');
  String get _mm => _minute.toString().padLeft(2, '0');

  /// 根据点击/拖动位置选择小时或分钟。
  /// [center] 为表盘中心（相对手势局部坐标）。
  void _onDial(Offset local, {required Offset center}) {
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final r = math.sqrt(dx * dx + dy * dy);
    if (r < 28) return; // 中心留白区不选择
    var angle = math.atan2(dy, dx) + math.pi / 2; // 顶部为 0
    if (angle < 0) angle += 2 * math.pi;
    if (angle >= 2 * math.pi) angle -= 2 * math.pi;
    final index = (angle / (2 * math.pi / 12)).round() % 12; // 顶部起 0..11
    setState(() {
      if (_pickingHour) {
        // 内圈 1-12，顶部为 12；外圈 13-24，顶部为 24（即 0 点）。
        final inner = r < (_innerR + _outerR) / 2;
        if (inner) {
          _hour = ((index + 11) % 12) + 1;
        } else {
          _hour = index == 0 ? 0 : index + 12;
        }
      } else {
        _minute = index * 5;
      }
    });
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
                  setState(() => _pickingHour = true);
                }),
                const SizedBox(width: 24),
                Text(
                  '$_hh:$_mm',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 24),
                _modeButton(theme, '分', !_pickingHour, () {
                  setState(() => _pickingHour = false);
                }),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: _dialSize,
              height: _dialSize,
              child: GestureDetector(
                onTapDown: (d) => _onDial(d.localPosition,
                    center: const Offset(_dialSize / 2, _dialSize / 2)),
                onPanUpdate: (d) => _onDial(d.localPosition,
                    center: const Offset(_dialSize / 2, _dialSize / 2)),
                child: CustomPaint(
                  size: const Size(_dialSize, _dialSize),
                  painter: _DialPainter(
                    hourMode: _pickingHour,
                    hour: _hour,
                    minute: _minute,
                    scheme: theme.colorScheme,
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

  const _DialPainter({
    required this.hourMode,
    required this.hour,
    required this.minute,
    required this.scheme,
  });

  double _angleOf(int index) => index * (2 * math.pi / 12) - math.pi / 2;

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
      // 选中指针：内圈选中到内圈半径，外圈选中到外圈半径。
      final value = hour;
      final inner = value >= 1 && value <= 12;
      final index = inner ? value % 12 : (value == 0 ? 0 : value - 12);
      _drawHand(canvas, center, _angleOf(index), inner ? _innerR : _outerR);
    } else {
      // 分钟：一圈 12 个刻度（0,5,10,...55），顶部为 0。
      for (var m = 0; m < 60; m += 5) {
        final index = m ~/ 5;
        _drawNumber(canvas, '$m',
            center +
                Offset(math.cos(_angleOf(index)), math.sin(_angleOf(index))) *
                    _outerR,
            selected: minute == m);
      }
      _drawHand(canvas, center, _angleOf(minute ~/ 5), _outerR);
    }
  }

  void _drawNumber(
      Canvas canvas, String text, Offset pos, {required bool selected}) {
    if (selected) {
      canvas.drawCircle(pos, _dotR, Paint()..color = scheme.primary);
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

  void _drawHand(Canvas canvas, Offset center, double angle, double radius) {
    final end = center +
        Offset(math.cos(angle), math.sin(angle)) * (radius - _dotR + 4);
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

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.hourMode != hourMode ||
      old.hour != hour ||
      old.minute != minute ||
      old.scheme != scheme;
}
