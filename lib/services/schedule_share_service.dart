import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zxing2/qrcode.dart' as zxing;

import '../models/course.dart';
import '../models/schedule.dart';

/// 分享包：一张课程表 + 其全部课程。
///
/// 多端数据结构一致（均为本地 JSON 模型），因此导出文件 / 二维码
/// 可以在 Windows / Android / iOS / Web 之间互相导入。
class ScheduleSharePackage {
  final Schedule schedule;
  final List<Course> courses;

  ScheduleSharePackage({required this.schedule, required this.courses});

  Map<String, dynamic> toJson() => {
        'type': 'classpath_schedule',
        'version': 1,
        'schedule': schedule.toJson(),
        'courses': courses.map((c) => c.toJson()).toList(),
      };

  factory ScheduleSharePackage.fromJson(Map<String, dynamic> json) {
    final s = Schedule.fromJson(
        (json['schedule'] as Map).cast<String, dynamic>());
    final cs = (json['courses'] as List? ?? [])
        .map((e) => Course.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return ScheduleSharePackage(schedule: s, courses: cs);
  }
}

/// 压缩载荷的前缀，用于解码时区分「原始 JSON」与「gzip 压缩的数据」。
const String compressedMagic = 'classpath:gz:';

/// 课程表分享：编码 / 解码 / 二维码载荷压缩 / 从图片解码二维码。
class ScheduleShareService {
  ScheduleShareService._();

  /// 编码为紧凑 JSON 字符串（用于导出文件）。
  static String encode(Schedule schedule, List<Course> courses) =>
      jsonEncode(ScheduleSharePackage(schedule: schedule, courses: courses));

  /// 解析分享 JSON（文件导入），失败返回 null。
  static ScheduleSharePackage? decode(String text) {
    try {
      final obj = jsonDecode(text);
      if (obj is! Map) return null;
      final map = obj.cast<String, dynamic>();
      if (map['type'] != 'classpath_schedule' ||
          map['schedule'] is! Map) {
        return null;
      }
      return ScheduleSharePackage.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// 生成二维码内容：优先使用原始 JSON；若超出二维码容量则 gzip 压缩
  /// 后 base64 编码，并加上固定前缀以便解码时识别。
  static String qrPayload(Schedule schedule, List<Course> courses) {
    final raw = encode(schedule, courses);
    try {
      // 校验容量：超长会抛 InputTooLongException。
      QrCode.fromData(data: raw, errorCorrectLevel: QrErrorCorrectLevel.L);
      return raw;
    } on InputTooLongException {
      final bytes = Uint8List.fromList(utf8.encode(raw));
      final gz = GZipEncoder().encodeBytes(bytes, level: 9);
      return '$compressedMagic${base64Encode(gz)}';
    }
  }

  /// 解析二维码内容（可能是原始 JSON 或 gzip 压缩的 base64），失败返回 null。
  static ScheduleSharePackage? decodeQrPayload(String payload) {
    String json;
    if (payload.startsWith(compressedMagic)) {
      try {
        final bytes = base64Decode(payload.substring(compressedMagic.length));
        json = utf8.decode(GZipDecoder().decodeBytes(bytes));
      } catch (_) {
        return null;
      }
    } else {
      json = payload;
    }
    return decode(json);
  }

  /// 从图片字节解码二维码，返回二维码原始内容；失败返回 null。
  static Future<String?> qrContentFromImageBytes(Uint8List bytes) async {
    try {
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      // 过大的图片先等比缩小，加快灰度转换与解码速度。
      decoded = _downscale(decoded, 1600);
      final w = decoded.width;
      final h = decoded.height;
      final pixels = Int32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = decoded.getPixel(x, y);
          final a = p.a.toInt();
          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();
          pixels[y * w + x] = (a << 24) | (r << 16) | (g << 8) | b;
        }
      }
      final source = zxing.RGBLuminanceSource(w, h, pixels);
      final bitmap = zxing.BinaryBitmap(zxing.HybridBinarizer(source));
      final result = zxing.QRCodeReader().decode(bitmap);
      return result.text;
    } catch (_) {
      return null;
    }
  }

  /// 等比缩小图片，使长边不超过 [maxSide]。
  static img.Image _downscale(img.Image image, int maxSide) {
    final w = image.width;
    final h = image.height;
    final longest = w > h ? w : h;
    if (longest <= maxSide) return image;
    final scale = maxSide / longest;
    return img.copyResize(image,
        width: (w * scale).round(), height: (h * scale).round());
  }
}
