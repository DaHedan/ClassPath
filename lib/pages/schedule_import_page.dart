import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/schedule_share_service.dart';
import '../state/app_state.dart';
import 'qr_scan_page.dart';

/// 导入课程表：从 .json 文件 / 二维码图片 / 摄像头扫码导入。
///
/// 数据格式在各端（Windows / Android / iOS / Web）完全一致，
/// 因此可以在任意一端导出，另一端导入。
class ScheduleImportPage extends StatefulWidget {
  const ScheduleImportPage({super.key});

  @override
  State<ScheduleImportPage> createState() => _ScheduleImportPageState();
}

class _ScheduleImportPageState extends State<ScheduleImportPage> {
  /// 桌面端只支持文件 / 图片；Android / iOS 额外支持摄像头扫码。
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 从 .json 文件导入。
  Future<void> _pickJsonFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择课程表文件',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || !mounted) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    final pkg = ScheduleShareService.decode(text);
    if (pkg == null) {
      _showSnack('无法识别该文件，请确认是「课途」导出的课程表文件');
      return;
    }
    await _confirmImport(pkg);
  }

  /// 从包含二维码的图片导入（桌面端解码图片）。
  Future<void> _pickQrImage() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择包含课程表二维码的图片',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      withData: true,
    );
    if (result == null || !mounted) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;
    // 解码图片里的二维码，再解析其中的课程表数据。
    final content = await ScheduleShareService.qrContentFromImageBytes(bytes);
    if (!mounted) return;
    if (content == null) {
      _showSnack('图片中未识别到有效的二维码');
      return;
    }
    final pkg = ScheduleShareService.decodeQrPayload(content);
    if (pkg == null) {
      _showSnack('二维码内容不是有效的课程表数据');
      return;
    }
    await _confirmImport(pkg);
  }

  /// 手机端摄像头扫码导入。
  Future<void> _scanCamera() async {
    final content = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (!mounted || content == null) return;
    final pkg = ScheduleShareService.decodeQrPayload(content);
    if (pkg == null) {
      _showSnack('二维码内容不是有效的课程表数据');
      return;
    }
    await _confirmImport(pkg);
  }

  /// 确认后导入，完成后返回上一页。
  Future<void> _confirmImport(ScheduleSharePackage pkg) async {
    final s = pkg.schedule;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入课程表'),
        content: Text(
          '将导入课程表「${s.name}」及其 ${pkg.courses.length} 门课程。\n'
          '（${s.info}）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await context.read<AppState>().importSchedules([pkg]);
    if (!mounted) return;
    final msg = result.renamed > 0
        ? '已导入「${result.names.join('、')}」（重名已加副本后缀）'
        : '已导入「${result.names.join('、')}」';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
  }

  Widget _option({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('导入课程表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '课程表数据在各端格式一致，可从 Windows / Android / iOS / Web '
            '任意一端导出的文件或二维码导入。',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          _option(
            icon: Icons.folder_open_outlined,
            title: '从 .json 文件导入',
            subtitle: '选择「课途」导出的课程表文件',
            onTap: _pickJsonFile,
          ),
          // 手机端不单独提供「二维码图片导入」：从二维码导入直接进扫码页，
          // 扫码页左下角可从相册选图解码。
          if (!_isMobile)
            _option(
              icon: Icons.image_outlined,
              title: '从二维码图片导入',
              subtitle: '选择一张包含课程表二维码的图片',
              onTap: _pickQrImage,
            ),
          if (_isMobile)
            _option(
              icon: Icons.qr_code_scanner,
              title: '从二维码导入',
              subtitle: '扫描另一台设备上的二维码',
              onTap: _scanCamera,
            ),
          const SizedBox(height: 12),
          Text(
            '导入的课程表会作为新课程表加入列表，不会覆盖现有数据；'
            '重名时会自动添加「（副本N）」后缀。',
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
