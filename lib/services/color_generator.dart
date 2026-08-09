import 'dart:math';
import 'package:flutter/material.dart';

/// 课程颜色生成：自动生成柔和、与已有颜色有区别的颜色。
class ColorGenerator {
  ColorGenerator._();

  /// 内置柔和调色板（供用户自定义颜色时选择）。
  static const palette = <int>[
    0xFFF2A6A6, 0xFFF5B7A0, 0xFFF7D18C, 0xFFD5E58B, 0xFFA9DEA6,
    0xFF8FD6C5, 0xFF9FC9F0, 0xFFA9B4F0, 0xFFC0A9F0, 0xFFE2A9E8,
    0xFFF2A6C9, 0xFFE8C6A0, 0xFF9FE0A8, 0xFFA6D2F2, 0xFFC8A8F2,
    0xFFF2A8B8, 0xFFA8E8D8, 0xFFD8E8A8, 0xFFF2D8A8, 0xFFB0C4F2,
  ];

  /// 生成一个柔和且与 [avoid] 中颜色尽量不同的颜色。
  static Color generate({List<int> avoid = const [], int? seed}) {
    final rnd = Random(seed);
    final avoidHues = <double>[];
    for (final v in avoid) {
      try {
        avoidHues.add(HSLColor.fromColor(Color(v)).hue);
      } catch (_) {}
    }
    var hue = rnd.nextDouble() * 360;
    for (var attempt = 0; attempt < 40; attempt++) {
      final candidate = rnd.nextDouble() * 360;
      var ok = true;
      for (final h in avoidHues) {
        var diff = (candidate - h).abs();
        if (diff > 180) diff = 360 - diff;
        if (diff < 40) {
          ok = false;
          break;
        }
      }
      if (ok) {
        hue = candidate;
        break;
      }
    }
    final s = 0.38 + rnd.nextDouble() * 0.24; // 饱和度 0.38-0.62
    final l = 0.74 + rnd.nextDouble() * 0.14; // 亮度 0.74-0.88
    return HSLColor.fromAHSL(1, hue, s, l).toColor();
  }
}
