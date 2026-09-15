import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'timetable_image_parser.dart';

/// 图片课程表的文字识别：把图片转成 [OcrLine] 列表。
///
/// 用 ML Kit 的中文识别，离线在本机完成；ML Kit 仅支持 Android / iOS，
/// 所以桌面端与网页端不提供该入口（[supported] 为 false）。
/// 识别结果交给 [TimetableImageParser] 做纯算法的表格解析。
class TimetableOcr {
  TimetableOcr._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 识别图片文件，返回按位置排布的文字行。
  static Future<List<OcrLine>> recognizeFile(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      if (kDebugMode) _dumpBoxes(result);
      final lines = <OcrLine>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          // ML Kit 会把同一水平线、跨列的文字并成一个「行」，
          // 所以这里下沉到词框粒度输出，由解析器按间距重拼成段再判列。
          final elements = line.elements;
          if (elements.isEmpty) {
            final text = line.text.trim();
            if (text.isNotEmpty) lines.add(OcrLine(text, _box(line.boundingBox)));
            continue;
          }
          for (final element in elements) {
            final text = element.text.trim();
            if (text.isNotEmpty) {
              lines.add(OcrLine(text, _box(element.boundingBox)));
            }
          }
        }
      }
      return lines;
    } finally {
      await recognizer.close();
    }
  }

  static Rect _box(Rect b) => Rect.fromLTRB(
        b.left.toDouble(),
        b.top.toDouble(),
        b.right.toDouble(),
        b.bottom.toDouble(),
      );

  /// 临时诊断：打印 ML Kit 识别出的行框（L）与词框（E），
  /// 用于排查表格解析错位。仅 debug 构建输出。
  static void _dumpBoxes(RecognizedText result) {
    final all = <Rect>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        all.add(line.boundingBox);
        for (final el in line.elements) {
          all.add(el.boundingBox);
        }
      }
    }
    if (all.isEmpty) return;
    final w = all.map((r) => r.right).reduce((a, b) => a > b ? a : b);
    final h = all.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);
    debugPrint('[OCRDUMP] SIZE ${w.round()}x${h.round()}');
    for (final block in result.blocks) {
      for (final line in block.lines) {
        debugPrint('[OCRDUMP] L ${_boxText(line.boundingBox)} ${line.text}');
        for (final el in line.elements) {
          debugPrint('[OCRDUMP] E ${_boxText(el.boundingBox)} ${el.text}');
        }
      }
    }
  }

  static String _boxText(Rect r) =>
      '${r.left.round()},${r.top.round()},${r.right.round()},${r.bottom.round()}';
}
