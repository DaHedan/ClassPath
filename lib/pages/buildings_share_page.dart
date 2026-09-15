import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/schedule.dart';
import '../services/schedule_share_service.dart';
import '../widgets/share_sheet.dart';
import 'qr_scan_page.dart';

/// 楼宇配置分享页：与「课程表分享」一致，提供二维码与数据文件两种方案
/// （两者内容相同，任选其一即可）。
///
/// - [importMode] = false：导出。展示二维码，可分享/保存二维码图片与 .json；
/// - [importMode] = true：导入。支持扫码、识别图片里的二维码、选择 .json，
///   成功时用 `Navigator.pop(context, List<Building>)` 把楼宇交回调用方。
class BuildingsSharePage extends StatefulWidget {
  /// 要导出的楼宇（导入模式可不传）。
  final List<Building> buildings;

  /// 文件名前缀，一般为课程表名称。
  final String title;

  /// true 为导入模式。
  final bool importMode;

  const BuildingsSharePage({
    super.key,
    this.buildings = const [],
    this.title = '',
    this.importMode = false,
  });

  @override
  State<BuildingsSharePage> createState() => _BuildingsSharePageState();
}

class _BuildingsSharePageState extends State<BuildingsSharePage> {
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 楼宇 JSON：二维码与数据文件共用同一份数据。
  late final Map<String, dynamic> _jsonMap =
      BuildingsSharePackage(widget.buildings).toJson();
  late final String _json = ScheduleShareService.encodeJson(_jsonMap);
  late final String? _payload = ScheduleShareService.qrPayloadOf(_jsonMap);

  /// 待导出的二维码图片（导入模式不渲染）。
  late final Uint8List? _qrPng = _payload == null
      ? null
      : ScheduleShareService.renderQrPng(
          _payload,
          size: 260,
          quiet: 20,
          scale: 3,
        );

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  String get _jsonName =>
      widget.title.isEmpty ? '楼宇.json' : '${widget.title}_楼宇.json';

  String get _qrName =>
      widget.title.isEmpty ? '楼宇二维码.png' : '${widget.title}_楼宇二维码.png';

  // ================= 导出 =================

  /// 分享面板的标题（与课程表分享面板同一套样式）。
  String get _shareTitle => widget.title.isEmpty ? '楼宇' : '${widget.title} 楼宇';

  /// 数据文件：手机端弹分享面板（微信 / QQ / 更多应用 / 保存），桌面端另存为。
  Future<void> _exportJson() async {
    final bytes = Uint8List.fromList(utf8.encode(_json));
    if (!_isMobile) {
      await _saveToDisk(bytes, _jsonName, 'json');
      return;
    }
    await showShareSheet(
      context,
      title: _shareTitle,
      type: ShareContentType.dataFile,
      bytes: bytes,
      fileName: _jsonName,
      mimeType: 'application/json',
      onMore: () => _shareViaSystem(bytes, 'application/json', _jsonName),
      onSave: () => _saveToDisk(bytes, _jsonName, 'json'),
    );
  }

  /// 二维码图片：手机端弹分享面板，桌面端另存为 PNG。
  Future<void> _exportQr() async {
    final png = _qrPng;
    if (png == null) return;
    if (!_isMobile) {
      await _saveToDisk(png, _qrName, 'png');
      return;
    }
    await showShareSheet(
      context,
      title: _shareTitle,
      type: ShareContentType.image,
      bytes: png,
      fileName: _qrName,
      mimeType: 'image/png',
      onMore: () => _shareViaSystem(png, 'image/png', _qrName),
      onSave: () => _saveToDisk(png, _qrName, 'png'),
    );
  }

  /// 面板里的「更多应用」：调起系统分享面板。
  Future<void> _shareViaSystem(
    Uint8List bytes,
    String mime,
    String name,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: '课途 · 楼宇配置',
        files: [XFile.fromData(bytes, mimeType: mime, name: name)],
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _saveToDisk(
    Uint8List bytes,
    String fileName,
    String ext,
  ) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存$fileName',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [ext],
      bytes: bytes,
    );
    if (path != null && mounted) _snack('已保存到 $path');
  }

  // ================= 导入 =================

  /// 解析导入内容（二维码 payload 或文件 JSON），成功即把楼宇交回调用方。
  void _acceptJson(Map<String, dynamic>? json) {
    if (json == null) {
      _snack('内容无法识别');
      return;
    }
    List<Building> buildings;
    try {
      buildings = BuildingsSharePackage.parseBuildings(json);
    } catch (e) {
      _snack('$e');
      return;
    }
    if (buildings.isEmpty) {
      _snack('内容里没有楼宇');
      return;
    }
    Navigator.pop(context, buildings);
  }

  Future<void> _scanCamera() async {
    final content = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (!mounted || content == null) return;
    _acceptJson(ScheduleShareService.decodePayloadToJson(content));
  }

  Future<void> _pickQrImage() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择包含二维码的图片',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null || !mounted) return;
    final content = await ScheduleShareService.qrContentFromImageBytes(bytes);
    if (!mounted) return;
    if (content == null) {
      _snack('图片中未识别到有效的二维码');
      return;
    }
    _acceptJson(ScheduleShareService.decodePayloadToJson(content));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择楼宇数据文件',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null || !mounted) return;
    _acceptJson(
      ScheduleShareService.decodeJson(utf8.decode(bytes, allowMalformed: true)),
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.importMode ? '导入楼宇配置' : '导出楼宇配置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: widget.importMode
            ? _importChildren(context)
            : _exportChildren(context),
      ),
    );
  }

  List<Widget> _exportChildren(BuildContext context) {
    final theme = Theme.of(context);
    final qrUsable = _payload != null;
    return [
      Text(
        '共 ${widget.buildings.length} 栋楼宇（含各楼节次时间段）',
        style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
      ),
      const SizedBox(height: 12),
      if (qrUsable && _qrPng != null)
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.memory(_qrPng, width: 220, height: 220),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '楼宇内容较多，二维码装不下，请用「数据文件」分享。',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.error),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _exportJson,
        icon: Icon(
          _isMobile ? Icons.share_outlined : Icons.download_outlined,
        ),
        label: Text(_isMobile ? '分享数据文件' : '保存数据文件'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: qrUsable && _qrPng != null ? _exportQr : null,
        icon: Icon(
          _isMobile ? Icons.qr_code_2_outlined : Icons.image_outlined,
        ),
        label: Text(_isMobile ? '分享二维码' : '保存二维码图片'),
      ),
      const SizedBox(height: 12),
      Text(
        _isMobile
            ? '对方保存后用「导入楼宇配置」的任意一种方式都能读进来。'
            : '在其他设备上可通过「导入楼宇配置」读取此文件或扫描二维码。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
      ),
    ];
  }

  List<Widget> _importChildren(BuildContext context) {
    final theme = Theme.of(context);
    return [
      if (_isMobile)
        _tile(
          context,
          icon: Icons.qr_code_scanner,
          title: '扫描二维码',
          subtitle: '用摄像头扫对方展示的楼宇二维码',
          onTap: _scanCamera,
        ),
      _tile(
        context,
        icon: Icons.image_outlined,
        title: '从图片识别',
        subtitle: '选择一张包含楼宇二维码的图片',
        onTap: _pickQrImage,
      ),
      _tile(
        context,
        icon: Icons.file_open_outlined,
        title: '选择数据文件',
        subtitle: '支持楼宇配置 .json，也支持整份课程表分享包',
        onTap: _pickFile,
      ),
      const SizedBox(height: 12),
      Text(
        '导入时可选择「替换」现有楼宇，或「追加」到现有列表（重名会自动跳过）。',
        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
      ),
    ];
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
