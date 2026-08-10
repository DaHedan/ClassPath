import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/course.dart';
import '../models/schedule.dart';
import '../services/schedule_share_service.dart';

/// 导出课程表：展示二维码，支持保存为 .json 文件或复制 JSON 内容。
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
  late final String _payload = ScheduleShareService.qrPayload(
      widget.schedule, widget.courses);
  late final String _json =
      ScheduleShareService.encode(widget.schedule, widget.courses);
  late final bool _compressed =
      _payload.startsWith(compressedMagic);

  String get _fileName =>
      '${widget.schedule.name}_课表.json';

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

  Future<void> _copyJson() async {
    await Clipboard.setData(ClipboardData(text: _json));
    if (mounted) _showSnack('JSON 内容已复制到剪贴板');
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
              leading: Icon(Icons.calendar_month_outlined,
                  color: theme.colorScheme.primary),
              title: Text(s.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  Text('扫码导入此课程表',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: QrImageView(
                      data: _payload,
                      size: 240,
                      version: QrVersions.auto,
                      errorCorrectionLevel: QrErrorCorrectLevel.L,
                      errorStateBuilder: (context, error) => Text(
                        '二维码生成失败：$error',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  if (_compressed) ...[
                    const SizedBox(height: 12),
                    Text(
                      '课程表内容较长，二维码已自动压缩编码',
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.outline),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saveFile,
            icon: const Icon(Icons.download_outlined),
            label: const Text('保存为 .json 文件'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _copyJson,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('复制 JSON 内容'),
          ),
          const SizedBox(height: 12),
          Text(
            '在其他设备上可通过「导入」读取此文件或扫描二维码。',
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
