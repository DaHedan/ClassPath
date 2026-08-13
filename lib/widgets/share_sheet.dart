import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 与 Android 原生端（MainActivity）的分享通道：
/// 把内存文件直接分享给指定应用（微信 / QQ）。
const _channel = MethodChannel('classpath/share');

Future<bool> _shareFileTo(
  String pkg,
  Uint8List bytes,
  String mime,
  String name,
) async {
  try {
    return await _channel.invokeMethod<bool>('shareFileTo', {
          'package': pkg,
          'mimeType': mime,
          'fileName': name,
          'bytesBase64': base64Encode(bytes),
        }) ??
        false;
  } catch (_) {
    return false;
  }
}

/// 分享面板的内容类型：课程表数据文件（json）或二维码图片。
enum ShareContentType { dataFile, image }

/// 底部弹出式分享面板（国产 App 常见样式）。
///
/// - 第一行：微信、QQ 直接调起对应应用分享当前内容；「更多应用」走系统分享面板；
///   （微信/QQ 仅 Android 可用，iOS 上不显示）
/// - 第二行：保存当前内容（数据文件或二维码图片）。
Future<void> showShareSheet(
  BuildContext context, {
  required String title,
  required ShareContentType type,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required VoidCallback onMore,
  required VoidCallback onSave,
}) async {
  final isAndroid = !kIsWeb && Platform.isAndroid;
  final isImage = type == ShareContentType.image;
  final scheme = Theme.of(context).colorScheme;
  final messenger = ScaffoldMessenger.of(context);

  void toast(String msg) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 调起指定应用；未安装或失败时提示。
  Future<void> shareTo(String label, String pkg) async {
    Navigator.of(context).pop();
    final ok = await _shareFileTo(pkg, bytes, mimeType, fileName);
    if (!ok) toast('未安装 $label，或分享失败');
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: scheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '分享「$title」',
              style: Theme.of(sheetCtx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // 分享到应用。
            Row(
              children: [
                if (isAndroid) ...[
                  Expanded(
                    child: _ShareItem(
                      icon: Icons.wechat,
                      color: const Color(0xFF07C160),
                      label: '微信',
                      onTap: () => shareTo('微信', 'com.tencent.mm'),
                    ),
                  ),
                  Expanded(
                    child: _ShareItem(
                      icon: Icons.forum_outlined,
                      color: const Color(0xFF12B7F5),
                      label: 'QQ',
                      onTap: () => shareTo('QQ', 'com.tencent.mobileqq'),
                    ),
                  ),
                ],
                Expanded(
                  child: _ShareItem(
                    icon: Icons.more_horiz,
                    color: scheme.primary,
                    label: '更多应用',
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      onMore();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 保存到本机。
            Row(
              children: [
                Expanded(
                  child: _ShareItem(
                    icon: isImage
                        ? Icons.image_outlined
                        : Icons.file_download_outlined,
                    color: isImage ? const Color(0xFF8E44AD) : const Color(0xFFE67E22),
                    label: isImage ? '保存图片' : '保存文件',
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      onSave();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ShareItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ShareItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
