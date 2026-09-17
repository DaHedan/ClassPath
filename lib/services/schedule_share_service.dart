import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart' show QrCode, QrErrorCorrectLevel, QrImage;
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

/// 楼宇配置分享包：把「学校楼宇」（名称 + 各楼节次时间段）单独导出/导入，
/// 便于同一学校的不同课程表之间复用，或分享给同学。
class BuildingsSharePackage {
  /// 文件类型标识（与课程表分享包区分）。
  static const String typeName = 'classpath_buildings';

  final List<Building> buildings;

  BuildingsSharePackage(this.buildings);

  Map<String, dynamic> toJson() => {
    'type': typeName,
    'version': 1,
    'buildings': buildings.map((b) => b.toJson()).toList(),
  };

  factory BuildingsSharePackage.fromJson(Map<String, dynamic> json) =>
      BuildingsSharePackage(
        (json['buildings'] as List? ?? [])
            .map((e) => Building.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  /// 从任意课途文件里取出楼宇：既接受「仅楼宇」文件，也接受完整的
  /// 课程表分享包（取其中的楼宇）。两种都不是则抛 [FormatException]。
  static List<Building> parseBuildings(Map<String, dynamic> json) {
    switch (json['type']) {
      case BuildingsSharePackage.typeName:
        return BuildingsSharePackage.fromJson(json).buildings;
      case 'classpath_schedule':
        return ScheduleSharePackage.fromJson(json).schedule.buildings;
      default:
        throw const FormatException('不是课途的楼宇或课程表文件');
    }
  }
}

/// 分享内容选项：控制哪些可选内容随课程表一起分享。
///
/// 未列出的内容（课程表名称、周数、第一周周一、节次时间、上课时间与地点、
/// 课程编号与颜色等）固定分享。
class ShareOptions {
  /// 用餐时间（午/晚餐）。
  final bool meals;

  /// 调休安排。
  final bool reschedules;

  /// 课程（含上课时间、地点、编号、颜色等）。
  final bool courses;

  /// 教师。
  final bool teacher;

  /// 提前提醒。
  final bool remind;

  /// 考试信息。
  final bool exam;

  /// 备注。
  final bool note;

  /// 不参与分享的课程（按 [Course.uid]）。
  final Set<String> excludedCourses;

  const ShareOptions({
    this.meals = true,
    this.reschedules = true,
    this.courses = true,
    this.teacher = true,
    this.remind = false,
    this.exam = true,
    this.note = false,
    this.excludedCourses = const <String>{},
  });

  ShareOptions copyWith({
    bool? meals,
    bool? reschedules,
    bool? courses,
    bool? teacher,
    bool? remind,
    bool? exam,
    bool? note,
    Set<String>? excludedCourses,
  }) =>
      ShareOptions(
        meals: meals ?? this.meals,
        reschedules: reschedules ?? this.reschedules,
        courses: courses ?? this.courses,
        teacher: teacher ?? this.teacher,
        remind: remind ?? this.remind,
        exam: exam ?? this.exam,
        note: note ?? this.note,
        excludedCourses: excludedCourses ?? this.excludedCourses,
      );
}

/// 课程表分享：编码 / 解码 / 二维码载荷压缩 / 从图片解码二维码。
class ScheduleShareService {
  ScheduleShareService._();

  /// 按 [options] 过滤出实际分享的数据包：
  /// 未勾选的用餐时间 / 调休安排 / 课程会整体置空，
  /// 未勾选的教师 / 提前提醒 / 考试信息 / 备注按课程逐条清空。
  static ScheduleSharePackage filtered(
    Schedule schedule,
    List<Course> courses,
    ShareOptions options,
  ) {
    final s = Schedule(
      id: schedule.id,
      name: schedule.name,
      totalWeeks: schedule.totalWeeks,
      firstMonday: schedule.firstMonday,
      periodsPerDay: schedule.periodsPerDay,
      buildings: schedule.buildings.map((b) => b.copy()).toList(),
      lunch: options.meals
          ? schedule.lunch.copy()
          : MealTime(afterPeriod: 0, label: schedule.lunch.label),
      dinner: options.meals
          ? schedule.dinner.copy()
          : MealTime(afterPeriod: 0, label: schedule.dinner.label),
      reschedules: options.reschedules
          ? schedule.reschedules.map((r) => r.copy()).toList()
          : [],
    );
    final cs = options.courses
        ? [
            for (final c in courses)
              if (!options.excludedCourses.contains(c.uid))
                _filterCourse(c, options),
          ]
        : <Course>[];
    return ScheduleSharePackage(schedule: s, courses: cs);
  }

  static Course _filterCourse(Course c, ShareOptions o) {
    final n = c.copy();
    if (!o.teacher) n.teacher = null;
    if (!o.remind) n.remindMinutes = null;
    if (!o.exam) n.exam = null;
    if (!o.note) n.note = null;
    return n;
  }

  /// 编码为紧凑 JSON 字符串（用于导出文件）。
  static String encode(Schedule schedule, List<Course> courses) =>
      encodeJson(ScheduleSharePackage(schedule: schedule, courses: courses).toJson());

  /// 编码任意课途 JSON（文件导出用）。
  static String encodeJson(Map<String, dynamic> json) => jsonEncode(json);

  /// 解析任意课途 JSON 文本（文件导入用），失败返回 null。
  static Map<String, dynamic>? decodeJson(String text) {
    try {
      final obj = jsonDecode(text);
      return obj is Map ? obj.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  /// 解析分享 JSON（文件导入），失败返回 null。
  static ScheduleSharePackage? decode(String text) {
    final map = decodeJson(text);
    if (map == null) return null;
    if (map['type'] != 'classpath_schedule' || map['schedule'] is! Map) {
      return null;
    }
    try {
      return ScheduleSharePackage.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// QR 可承载的最大字节数：version 40 + errorCorrectionLevel L（byte 模式
  /// 数据位约 2956 字节），再预留模式/长度等头部开销，取 2950。
  static const int _qrMaxBytes = 2950;

  /// 生成二维码内容：紧凑 JSON 与 gzip 压缩后 base64 取较短者，
  /// 尽量降低二维码版本密度、提高静态识别成功率；超出容量返回 null。
  static String? qrPayload(Schedule schedule, List<Course> courses) =>
      qrPayloadOf(_compact(schedule, courses));

  /// 生成任意课途 JSON 的二维码内容。
  ///
  /// 一律输出 gzip + base64（纯 ASCII）：扫码读取端（zxing）在没有 ECI 时
  /// 会自己猜字符集，直接放 UTF-8 原文会让中文被猜错、读成乱码，
  /// 因此不做「与原文取短」的优化。超出二维码容量返回 null。
  static String? qrPayloadOf(Map<String, dynamic> json) {
    final rawBytes = utf8.encode(jsonEncode(json));
    final compressed =
        '$compressedMagic${base64Encode(GZipEncoder().encodeBytes(Uint8List.fromList(rawBytes), level: 9))}';
    return compressed.length <= _qrMaxBytes ? compressed : null;
  }

  /// 把二维码内容还原为 JSON（自动处理 gzip 压缩），失败返回 null。
  static Map<String, dynamic>? decodePayloadToJson(String payload) {
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
    return decodeJson(text);
  }

  /// 二维码专用紧凑格式（版本号 2），键名短、结构扁平。
  /// 文件导入仍用完整 [encode]，两者互不影响。
  static Map<String, dynamic> _compact(Schedule s, List<Course> courses) {
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
    final obj = decodePayloadToJson(payload);
    if (obj == null) return null;
    if (obj['type'] == 'classpath_schedule') {
      return decode(jsonEncode(obj)); // 旧版完整 JSON
    }
    if (obj['t'] == 2) {
      try {
        return _decompact(obj);
      } catch (_) {
        return null;
      }
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
            RescheduleDay(
              date: (r as List)[0] as String,
              source: r[1] as String,
            ),
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
                  weeks: ct['w'] == null ? null : (ct['w'] as List).cast<int>(),
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
                            (c['e'] as List)[0] as int,
                          ),
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
  ///
  /// 依次尝试多种预处理 / 二值化组合（放大、反色、全局/混合二值化），
  /// 任一组合成功即返回，尽量兼容不同来源的二维码图片。
  static Future<String?> qrContentFromImageBytes(Uint8List bytes) async {
    try {
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      // 过大的图片先等比缩小，加快灰度转换与解码速度。
      decoded = _downscale(decoded, 1600);

      final variants = <img.Image>[decoded];
      // 码点偏小 / 密集时放大重试，通常能显著提高识别率。
      if (decoded.width < 1600 && decoded.height < 1600) {
        variants.add(
          img.copyResize(
            decoded,
            width: decoded.width * 2,
            height: decoded.height * 2,
            interpolation: img.Interpolation.nearest,
          ),
        );
      }
      for (final im in variants) {
        final normal = _decodeQr(im, hybrid: true, invert: false);
        if (normal != null) return normal;
        final inverted = _decodeQr(im, hybrid: true, invert: true);
        if (inverted != null) return inverted;
        final global = _decodeQr(im, hybrid: false, invert: false);
        if (global != null) return global;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 对单张图片做一次二维码解码；[invert] 表示是否反色（白码黑底）。
  static String? _decodeQr(
    img.Image im, {
    required bool hybrid,
    required bool invert,
  }) {
    try {
      final w = im.width;
      final h = im.height;
      final pixels = Int32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = im.getPixel(x, y);
          var v =
              (p.a.toInt() << 24) |
              (p.r.toInt() << 16) |
              (p.g.toInt() << 8) |
              p.b.toInt();
          if (invert) v = 0xFFFFFFFF & ~v; // 保留 alpha，翻转 RGB
          pixels[y * w + x] = v;
        }
      }
      final source = zxing.RGBLuminanceSource(w, h, pixels);
      final bitmap = zxing.BinaryBitmap(
        hybrid
            ? zxing.HybridBinarizer(source)
            : zxing.GlobalHistogramBinarizer(source),
      );
      final result = zxing.QRCodeReader().decode(bitmap);
      return result.text;
    } catch (e) {
      debugPrint(
        'zxing 解码失败(hybrid=$hybrid, invert=$invert, '
        '${im.width}x${im.height}): $e',
      );
      return null;
    }
  }

  /// 用 image 库直接绘制二维码 PNG（白底 + 静区 + 整数像素模块）。
  ///
  /// 与 Flutter Canvas 离屏渲染相比，模块边界为整数像素、无浮点模糊，
  /// zxing 等解码器更容易识别。优先使用高纠错级别，数据过长时自动降级。
  /// [size] 二维码逻辑尺寸（不含静区），[quiet] 静区宽度，
  /// [scale] 输出分辨率倍数。无法容纳内容时返回 null。
  static Uint8List? renderQrPng(
    String payload, {
    double size = 260,
    double quiet = 20,
    int scale = 3,
  }) {
    QrCode? code;
    for (final ecl in const [
      QrErrorCorrectLevel.L,
      QrErrorCorrectLevel.M,
      QrErrorCorrectLevel.Q,
      QrErrorCorrectLevel.H,
    ]) {
      try {
        code = QrCode.fromData(data: payload, errorCorrectLevel: ecl);
        break;
      } catch (_) {}
    }
    if (code == null) return null;
    final qrImage = QrImage(code);
    final n = qrImage.moduleCount;
    final qpx = (quiet * scale).round();
    final modulePx = ((size * scale) / n).floor();
    if (modulePx < 2) return null;
    final side = n * modulePx + qpx * 2;
    final im = img.Image(width: side, height: side);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (qrImage.isDark(y, x)) {
          img.fillRect(
            im,
            x1: qpx + x * modulePx,
            y1: qpx + y * modulePx,
            x2: qpx + (x + 1) * modulePx - 1,
            y2: qpx + (y + 1) * modulePx - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }
    return img.encodePng(im);
  }

  /// 分享卡片与二维码的统一渲染参数：二维码逻辑尺寸 [qrRenderSize]、
  /// 静区 [qrQuiet]，均以 [qrScale] 倍分辨率输出。
  static const double qrRenderSize = 260;
  static const double qrQuiet = 20;
  static const int qrScale = 3;

  /// 离屏绘制「分享卡片」PNG：顶部课途图标 + 名称，中部二维码，底部提示。
  ///
  /// [qrPng] 必须是 [renderQrPng] 在 `size: qrRenderSize, quiet: qrQuiet,
  /// scale: qrScale` 下的输出（页面展示与导出共用同一张图）。
  /// 文字 / 图标用 Flutter Canvas 绘制、按 [qrScale] 倍输出，
  /// 二维码用 image 库绘制后原像素合成，保证图片里的二维码能被 zxing 解码。
  /// 绘制失败返回 null。
  static Future<Uint8List?> renderShareCardPng({
    required Uint8List qrPng,
    required String title,
    required String subtitle,
    required String tip,
  }) async {
    final qrDecoded = img.decodeImage(qrPng);
    if (qrDecoded == null) return null;

    final scale = qrScale.toDouble();
    const w = 380.0;
    const pad = 16.0;
    const iconSize = 18.0;

    // 软件图标
    final iconData = await rootBundle.load('assets/ClassPath_1024.png');
    final iconImage = await decodeImageFromList(iconData.buffer.asUint8List());
    final iconSrc = Rect.fromLTWH(
      0,
      0,
      iconImage.width.toDouble(),
      iconImage.height.toDouble(),
    );

    // 预排版各段文字，拿到真实尺寸。
    final nameTp = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF222222),
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: w - pad * 2);
    final subTp = TextPainter(
      text: TextSpan(
        text: subtitle,
        style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tipTp = TextPainter(
      text: TextSpan(
        text: tip,
        style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final brandTp = TextPainter(
      text: const TextSpan(
        text: '课途',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF333333),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 卡片总高。
    final qrArea = qrRenderSize + qrQuiet * 2;
    final h = pad +
        iconSize +
        10 +
        nameTp.height +
        4 +
        subTp.height +
        12 +
        qrArea +
        12 +
        tipTp.height +
        pad;

    // 离屏绘制文字层（放大 scale 倍保证导出清晰），二维码区域留白。
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(16),
      ),
      Paint()..color = Colors.white,
    );

    // 顶部：软件图标 + 课途
    final brandTotal = iconSize + 6 + brandTp.width;
    var y = pad;
    final iconX = (w - brandTotal) / 2;
    canvas.drawImageRect(
      iconImage,
      iconSrc,
      Rect.fromLTWH(iconX, y, iconSize, iconSize),
      Paint()..filterQuality = FilterQuality.high,
    );
    brandTp.paint(
      canvas,
      Offset(iconX + iconSize + 6, y + (iconSize - brandTp.height) / 2),
    );
    y += iconSize + 10;

    // 名称
    nameTp.paint(canvas, Offset((w - nameTp.width) / 2, y));
    y += nameTp.height + 4;

    // 副标题（如「共 16 周」）
    subTp.paint(canvas, Offset((w - subTp.width) / 2, y));
    y += subTp.height + 12;

    // 二维码区域留白（二维码 PNG 稍后合成）。
    final qrX = (w - qrArea) / 2;
    final qrY = y;
    canvas.drawRect(
      Rect.fromLTWH(qrX, y, qrArea, qrArea),
      Paint()..color = Colors.white,
    );
    y += qrArea + 12;

    // 提示文字
    tipTp.paint(canvas, Offset((w - tipTp.width) / 2, y));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (w * scale).toInt(),
      (h * scale).toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    iconImage.dispose();
    final cardPng = data?.buffer.asUint8List();
    if (cardPng == null) return null;

    // 把二维码 PNG（含静区）合成到预留区域。
    final base = img.decodeImage(cardPng);
    if (base == null) return null;
    img.compositeImage(
      base,
      qrDecoded,
      dstX: (qrX * scale).round(),
      dstY: (qrY * scale).round(),
    );
    return img.encodePng(base);
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
