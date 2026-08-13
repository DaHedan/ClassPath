import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
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
      (json['schedule'] as Map).cast<String, dynamic>(),
    );
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
      if (map['type'] != 'classpath_schedule' || map['schedule'] is! Map) {
        return null;
      }
      return ScheduleSharePackage.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// QR 可承载的最大字节数：version 40 + errorCorrectionLevel L（byte 模式
  /// 数据位约 2956 字节），再预留模式/长度等头部开销，取 2950。
  static const int _qrMaxBytes = 2950;

  /// 生成二维码内容：优先使用紧凑 JSON（短键名、省略本地用不到的
  /// id/uid）；超出容量则 gzip 压缩后 base64 编码并加前缀；
  /// 仍超出容量则返回 null。
  static String? qrPayload(Schedule schedule, List<Course> courses) {
    final compact = jsonEncode(_compact(schedule, courses));
    if (utf8.encode(compact).length <= _qrMaxBytes) return compact;
    final gz = GZipEncoder().encodeBytes(
      Uint8List.fromList(utf8.encode(compact)),
      level: 9,
    );
    final compressed = '$compressedMagic${base64Encode(gz)}';
    if (compressed.length <= _qrMaxBytes) return compressed;
    return null;
  }

  /// 二维码专用紧凑格式（版本号 2），键名短、结构扁平。
  /// 文件导入仍用完整 [encode]，两者互不影响。
  static Map<String, dynamic> _compact(
      Schedule s, List<Course> courses) {
    return {
      't': 2,
      's': {
        'n': s.name,
        'tw': s.totalWeeks,
        'fm': s.firstMonday.millisecondsSinceEpoch,
        'pp': s.periodsPerDay,
        'b': [
          for (final b in s.buildings)
            {
              'n': b.name,
              'pt': [
                for (final p in b.periodTimes)
                  [p.startPeriod, p.endPeriod, p.start, p.end],
              ],
            },
        ],
        'l': [s.lunch.afterPeriod, s.lunch.label],
        'd': [s.dinner.afterPeriod, s.dinner.label],
        'r': [
          for (final r in s.reschedules) [r.date, r.source],
        ],
      },
      'c': [
        for (final c in courses)
          {
            'id': c.id,
            'n': c.name,
            't': c.teacher,
            'ct': [
              for (final ct in c.classTimes)
                {
                  'wk': ct.weekday,
                  'sp': ct.startPeriod,
                  'ep': ct.endPeriod,
                  's': ct.start,
                  'e': ct.end,
                  'l': ct.location == null || ct.location!.isEmpty
                      ? null
                      : [ct.location!.building, ct.location!.room],
                  'w': ct.weeks,
                },
            ],
            'l': [c.location.building, c.location.room],
            'c': c.colorValue,
            'r': c.remindMinutes,
            'e': c.exam == null || c.exam!.isEmpty
                ? null
                : [
                    c.exam!.date?.millisecondsSinceEpoch,
                    c.exam!.timeText,
                    c.exam!.location,
                    c.exam!.seat,
                  ],
            'nt': c.note,
          },
      ],
    };
  }

  /// 解析二维码内容：可能是紧凑格式（t:2）、旧版完整 JSON
  /// （type: classpath_schedule）或 gzip 压缩的数据，失败返回 null。
  static ScheduleSharePackage? decodeQrPayload(String payload) {
    String text;
    if (payload.startsWith(compressedMagic)) {
      try {
        final bytes = base64Decode(payload.substring(compressedMagic.length));
        text = utf8.decode(GZipDecoder().decodeBytes(bytes));
      } catch (_) {
        return null;
      }
    } else {
      text = payload;
    }
    try {
      final obj = jsonDecode(text);
      if (obj is! Map) return null;
      if (obj['type'] == 'classpath_schedule') {
        return decode(text); // 旧版完整 JSON
      }
      if (obj['t'] == 2) {
        return _decompact(obj.cast<String, dynamic>());
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// 把紧凑格式还原为课程表数据包。
  static ScheduleSharePackage? _decompact(Map<String, dynamic> json) {
    try {
      final s = (json['s'] as Map).cast<String, dynamic>();
      final lunch = (s['l'] as List? ?? []);
      final dinner = (s['d'] as List? ?? []);
      final schedule = Schedule(
        name: s['n'] as String,
        totalWeeks: s['tw'] as int,
        firstMonday: DateTime.fromMillisecondsSinceEpoch(s['fm'] as int),
        periodsPerDay: s['pp'] as int,
        buildings: [
          for (final b in (s['b'] as List? ?? []))
            Building(
              name: (b as Map)['n'] as String,
              periodTimes: [
                for (final p in ((b as Map)['pt'] as List? ?? []))
                  PeriodTime(
                    startPeriod: (p as List)[0] as int,
                    endPeriod: p[1] as int,
                    start: p[2] as String,
                    end: p[3] as String,
                  ),
              ],
            ),
        ],
        lunch: MealTime(
          afterPeriod: lunch.isEmpty ? 0 : lunch[0] as int,
          label: lunch.length < 2 ? '午餐' : lunch[1] as String,
        ),
        dinner: MealTime(
          afterPeriod: dinner.isEmpty ? 0 : dinner[0] as int,
          label: dinner.length < 2 ? '晚餐' : dinner[1] as String,
        ),
        reschedules: [
          for (final r in (s['r'] as List? ?? []))
            RescheduleDay(date: (r as List)[0] as String, source: r[1] as String),
        ],
      );
      final courses = [
        for (final c in (json['c'] as List? ?? []))
          Course(
            scheduleId: schedule.id,
            id: (c as Map)['id'] as String? ?? '',
            name: c['n'] as String,
            teacher: c['t'] as String?,
            classTimes: [
              for (final ct in (c['ct'] as List? ?? []))
                ClassTime(
                  weekday: (ct as Map)['wk'] as int,
                  startPeriod: ct['sp'] as int,
                  endPeriod: ct['ep'] as int,
                  start: ct['s'] as String,
                  end: ct['e'] as String,
                  location: ct['l'] == null
                      ? null
                      : CourseLocation(
                          building: (ct['l'] as List)[0] as String,
                          room: (ct['l'] as List)[1] as String,
                        ),
                  weeks: ct['w'] == null
                      ? null
                      : (ct['w'] as List).cast<int>(),
                ),
            ],
            location: CourseLocation(
              building: (c['l'] as List)[0] as String,
              room: (c['l'] as List)[1] as String,
            ),
            colorValue: c['c'] as int? ?? 0xFF7FA8E0,
            remindMinutes: c['r'] as int?,
            exam: c['e'] == null
                ? null
                : ExamInfo(
                    date: (c['e'] as List)[0] == null
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(
                            (c['e'] as List)[0] as int),
                    timeText: (c['e'] as List)[1] as String?,
                    location: (c['e'] as List)[2] as String?,
                    seat: (c['e'] as List)[3] as String?,
                  ),
            note: c['nt'] as String?,
          ),
      ];
      return ScheduleSharePackage(schedule: schedule, courses: courses);
    } catch (_) {
      return null;
    }
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
    return img.copyResize(
      image,
      width: (w * scale).round(),
      height: (h * scale).round(),
    );
  }
}
