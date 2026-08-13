import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../models/schedule.dart';
import '../services/schedule_share_service.dart';
import '../widgets/share_sheet.dart';

/// 导出课程表：展示二维码。
///
/// - 手机端：通过系统分享面板把 .json 课程表 / 二维码图片发送到其它应用；
/// - 桌面端：保存为 .json 文件，二维码图片也可保存为 PNG。
///
/// 二维码内容与文件格式均为统一的 JSON（结构在各端一致），
/// 内容过长时二维码会自动压缩编码。
class ScheduleExportPage extends StatefulWidget {
  final Schedule schedule;
  final List<Course> courses;

  const ScheduleExportPage({
    super.key,
    required this.schedule,
    required this.courses,
  });

  @override
  State<ScheduleExportPage> createState() => _ScheduleExportPageState();
}

class _ScheduleExportPageState extends State<ScheduleExportPage> {
  late final String? _payload = ScheduleShareService.qrPayload(
    widget.schedule,
    widget.courses,
  );
  late final String _json = ScheduleShareService.encode(
    widget.schedule,
    widget.courses,
  );
  late final bool _compressed = _payload?.startsWith(compressedMagic) ?? false;

  String get _fileName => '${widget.schedule.name}_课表.json';

  /// 手机端走系统分享面板；桌面端保持保存文件。
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 二维码 payload 长度上限。内容过长时强行编码会得到超高密度二维码，
  /// 相册等静态识别困难，渲染也可能出错，此时只提供文件导出。
  static const int _qrMaxLen = 2400;

  /// 当前课程表是否适合用二维码承载。
  bool get _qrUsable => _payload != null && _payload!.length <= _qrMaxLen;

  /// 导出二维码的渲染参数（逻辑像素，最终以 _qrScale 倍分辨率输出）。
  static const double _qrRenderSize = 220;
  static const double _qrQuiet = 20;
  static const int _qrScale = 3;

  /// 在 [canvas] 的 [offset]（二维码左上角，静区之外）绘制二维码。
  /// 优先高纠错级别，数据过长时自动降级，全部失败返回 false。
  bool _paintQr(Canvas canvas, Offset offset, String payload) {
    for (final ecl in const [QrErrorCorrectLevel.M, QrErrorCorrectLevel.L]) {
      try {
        canvas.save();
        canvas.translate(offset.dx, offset.dy);
        QrPainter(
          data: payload,
          version: QrVersions.auto,
          errorCorrectionLevel: ecl,
          color: const Color(0xFF000000),
          gapless: true,
        ).paint(canvas, const Size(_qrRenderSize, _qrRenderSize));
        canvas.restore();
        return true;
      } catch (e) {
        canvas.restore();
        debugPrint('二维码绘制失败($ecl): $e');
      }
    }
    return false;
  }

  /// 渲染一张纯二维码图（白底 + 静区），用于生成自检解码，避免卡片上的
  /// 文字/图标干扰 zxing 整图识别。
  Future<Uint8List?> _renderQrPng(String payload) async {
    const qrArea = _qrRenderSize + _qrQuiet * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_qrScale.toDouble());
    canvas.drawRect(
      Rect.fromLTWH(0, 0, qrArea, qrArea),
      Paint()..color = Colors.white,
    );
    if (!_paintQr(canvas, const Offset(_qrQuiet, _qrQuiet), payload)) {
      return null;
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (qrArea * _qrScale).toInt(),
      (qrArea * _qrScale).toInt(),
    );
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _saveFile() async {
    final bytes = Uint8List.fromList(utf8.encode(_json));
    final path = await FilePicker.saveFile(
      dialogTitle: '保存课程表',
      fileName: _fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    if (path != null && mounted) {
      _showSnack('已保存到 $path');
    }
  }

  /// 手机端：把 .json 写入内存文件后调起系统分享面板，可选择应用发送。
  Future<void> _shareJson() async {
    final bytes = Uint8List.fromList(utf8.encode(_json));
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: '课途课程表：${widget.schedule.name}',
        files: [
          XFile.fromData(bytes, mimeType: 'application/json', name: _fileName),
        ],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  /// 离屏绘制完整分享卡片（软件图标 + 软件名 + 课程表名称 + 二维码 + 提示），
  /// 以 3 倍分辨率绘制后输出 PNG 字节，不依赖 widget 渲染。
  Future<Uint8List?> _renderShareCardPng() async {
    final payload = _payload;
    if (payload == null) return null;
    final scale = _qrScale.toDouble();
    const w = 340.0;
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
        text: widget.schedule.name,
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
    final weeksTp = TextPainter(
      text: TextSpan(
        text: '共 ${widget.schedule.totalWeeks} 周',
        style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tipTp = TextPainter(
      text: const TextSpan(
        text: '扫一扫，导入课程表',
        style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
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
    final h =
        pad +
        iconSize +
        10 +
        nameTp.height +
        4 +
        weeksTp.height +
        12 +
        (_qrRenderSize + _qrQuiet * 2) +
        12 +
        tipTp.height +
        pad;

    // 离屏绘制（放大 scale 倍保证导出清晰）。
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    // 先整体铺白：PNG 若带透明区，zxing 会把透明像素当黑色，干扰识别。
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

    // 课程表名称
    nameTp.paint(canvas, Offset(pad, y));
    y += nameTp.height + 4;

    // 共 N 周
    weeksTp.paint(canvas, Offset((w - weeksTp.width) / 2, y));
    y += weeksTp.height + 12;

    // 二维码（四周留白静区；优先高纠错级别，数据过长时自动降级）
    final qrArea = _qrRenderSize + _qrQuiet * 2;
    final qrX = (w - qrArea) / 2;
    canvas.drawRect(
      Rect.fromLTWH(qrX, y, qrArea, qrArea),
      Paint()..color = Colors.white,
    );
    final qrPainted = _paintQr(
      canvas,
      Offset(qrX + _qrQuiet, y + _qrQuiet),
      payload,
    );
    if (!qrPainted) {
      final errTp = TextPainter(
        text: const TextSpan(
          text: '二维码生成失败',
          style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      errTp.paint(canvas, Offset((w - errTp.width) / 2, y + qrArea / 2));
    }
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
    final png = data?.buffer.asUint8List();
    return png;
  }

  Future<void> _saveImage() async {
    final bytes = await _renderShareCardPng();
    if (bytes == null) return;
    final path = await FilePicker.saveFile(
      dialogTitle: '保存二维码图片',
      fileName: '${widget.schedule.name}_课表二维码.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
      bytes: bytes,
    );
    if (path != null && mounted) _showSnack('已保存到 $path');
  }

  /// 手机端：弹出分享面板分享课程表数据文件（json）。
  Future<void> _openShareSheet() async {
    await showShareSheet(
      context,
      title: widget.schedule.name,
      type: ShareContentType.dataFile,
      bytes: Uint8List.fromList(utf8.encode(_json)),
      fileName: _fileName,
      mimeType: 'application/json',
      onMore: _shareJson,
      onSave: _saveFile,
    );
  }

  /// 手机端：弹出分享面板分享二维码图片。
  Future<void> _openShareImageSheet() async {
    final bytes = await _renderShareCardPng();
    if (bytes == null || !mounted) return;
    await showShareSheet(
      context,
      title: widget.schedule.name,
      type: ShareContentType.image,
      bytes: bytes,
      fileName: '${widget.schedule.name}_课表二维码.png',
      mimeType: 'image/png',
      onMore: _shareImage,
      onSave: _saveImage,
    );
  }

  /// 把二维码 PNG 通过系统分享面板发送。
  Future<void> _shareImage() async {
    final bytes = await _renderShareCardPng();
    if (bytes == null) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: '课途课程表二维码：${widget.schedule.name}',
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'image/png',
            name: '${widget.schedule.name}_课表二维码.png',
          ),
        ],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.schedule;
    return Scaffold(
      appBar: AppBar(title: const Text('导出课程表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 课程表信息
          Card(
            child: ListTile(
              leading: Icon(
                Icons.calendar_month_outlined,
                color: theme.colorScheme.primary,
              ),
              title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${s.info} · ${widget.courses.length}门课\n'
                '第一周周一 ${_dateText(s.firstMonday)}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 16),
          // 二维码
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '扫码导入此课程表',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_qrUsable)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '课程表内容过大，二维码无法清晰承载。\n'
                        '请使用下方「${_isMobile ? '分享课程表' : '保存数据文件'}」导出。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  else ...[
                    // 页面只显示二维码（白底，深色模式下也清晰）；
                    // 保存 / 分享出去的图片由 _renderShareCardPng 离屏绘制。
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: _payload!,
                          size: 240,
                          version: QrVersions.auto,
                          errorCorrectionLevel: QrErrorCorrectLevel.L,
                          errorStateBuilder: (context, error) => Text(
                            '二维码生成失败：$error',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    if (_compressed) ...[
                      const SizedBox(height: 12),
                      Text(
                        '课程表内容较长，二维码已自动压缩编码',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isMobile ? _openShareSheet : _saveFile,
            icon: Icon(
              _isMobile ? Icons.share_outlined : Icons.download_outlined,
            ),
            label: Text(_isMobile ? '分享数据文件' : '保存数据文件'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _qrUsable
                ? (_isMobile ? _openShareImageSheet : _saveImage)
                : null,
            icon: Icon(
              _isMobile ? Icons.qr_code_2_outlined : Icons.image_outlined,
            ),
            label: Text(_isMobile ? '分享二维码' : '保存二维码图片'),
          ),
          const SizedBox(height: 12),
          Text(
            _isMobile
                ? '对方保存文件后，在课途「导入」中选择即可还原课程表。'
                : '在其他设备上可通过「导入」读取此文件或扫描二维码。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  static String _dateText(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
