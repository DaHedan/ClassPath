import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/schedule_share_service.dart';

/// 手机摄像头扫码页：识别到二维码后立即返回其原始内容（Navigator.pop）。
/// 左下角的图库按钮可改从相册选择含二维码的图片解码。
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _handled = true;
      Navigator.pop(context, raw);
      return;
    }
  }

  /// 从相册选择一张含二维码的图片解码；识别失败则留在本页提示。
  Future<void> _pickFromGallery() async {
    if (_handled) return;
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择包含二维码的图片',
      // 用 image 类型走系统相册选择器（显示全部图片、无需存储权限）。
      type: FileType.image,
      withData: true,
    );
    if (!mounted || result == null) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;
    final content = await ScheduleShareService.qrContentFromImageBytes(bytes);
    if (!mounted) return;
    if (content == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('图片中未识别到有效的二维码')));
      return;
    }
    _handled = true;
    Navigator.pop(context, content);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描二维码'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, value, child) {
              final on = value.torchState == TorchState.on;
              return IconButton(
                tooltip: on ? '关闭手电筒' : '打开手电筒',
                icon: Icon(
                  on ? Icons.flash_on : Icons.flash_off,
                  color: on ? Colors.amber : null,
                ),
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // 扫描框提示
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Text(
              '将二维码对准取景框',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          // 左下角：从相册选图解码。
          Positioned(
            left: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'qr_gallery',
              tooltip: '从相册选择图片',
              onPressed: _pickFromGallery,
              child: const Icon(Icons.photo_library_outlined),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
