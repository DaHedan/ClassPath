import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// 与 Android 原生端（MainActivity）的分享通道：
/// 把内存文件直接分享给指定应用（微信 / QQ）。
const _channel = MethodChannel('classpath/share');

/// 调起分享面板把内存文件发出去。
///
/// [toSystem] 为 true 时走系统（Android 端走原生 ACTION_SEND，让 ROM 用自己的
/// 分享面板；share_plus 内部用 createChooser，会得到 AOSP 那个传统方形图标列表）。
Future<bool> _shareFile(
  String pkg,
  Uint8List bytes,
  String mime,
  String name, {
  required bool toSystem,
}) async {
  try {
    return await _channel.invokeMethod<bool>(
          toSystem ? 'shareToSystem' : 'shareFileTo',
          {
            if (!toSystem) 'package': pkg,
            'mimeType': mime,
            'fileName': name,
            'bytesBase64': base64Encode(bytes),
          },
        ) ??
        false;
  } catch (_) {
    return false;
  }
}

/// 分享面板的内容类型：课程表数据文件（json）或二维码图片。
enum ShareContentType { dataFile, image }

/// 弹系统「另存为」对话框并把 [bytes] 写盘，返回保存路径（用户取消返回 null）。
///
/// 桌面端（Windows / Linux / macOS）的 file_picker 只负责弹框、返回用户选的
/// 路径，不会写文件，必须自己落盘；移动端由插件负责写入，这里不能重复写。
Future<String?> saveBytesToDisk({
  required Uint8List bytes,
  required String fileName,
  required List<String> allowedExtensions,
  String? dialogTitle,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle ?? '保存$fileName',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    bytes: bytes,
  );
  if (path == null) return null;
  final isDesktop = !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (isDesktop) await File(path).writeAsBytes(bytes);
  return path;
}

/// 保存图片：手机端直接写进系统相册（Android MediaStore / iOS 照片），
/// 桌面端仍弹「另存为」对话框（[saveBytesToDisk]）。
///
/// 返回给用户看的提示文字；用户取消保存时返回空串。
Future<String> saveImageBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  if (isMobile) {
    // gal 要求名字不带扩展名。
    final name = fileName.toLowerCase().endsWith('.png')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(bytes, name: name);
      return '已保存到相册';
    } on GalException catch (e) {
      return e.type == GalExceptionType.accessDenied
          ? '没有相册权限，请在系统设置里允许后重试'
          : '保存到相册失败';
    }
  }
  final path = await saveBytesToDisk(
    bytes: bytes,
    fileName: fileName,
    allowedExtensions: ['png'],
    dialogTitle: '保存$fileName',
  );
  return path == null ? '' : '已保存到 $path';
}

/// 调起**系统分享面板**发送内存文件（分享面板里的「更多应用」走这里）。
///
/// Android 端优先用原生 `ACTION_SEND`（交给 ROM 自己的分享面板渲染，
/// 华为/ HarmonyOS 上就是那种圆角图标 + 分页的样式）；原生通道不可用时
/// 退回 share_plus（它内部用 createChooser，样式是 AOSP 传统列表）。
Future<void> shareBytesToSystem({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? text,
  Rect? sharePositionOrigin,
}) async {
  final isAndroid = !kIsWeb && Platform.isAndroid;
  if (isAndroid &&
      await _shareFile('', bytes, mimeType, fileName, toSystem: true)) {
    return;
  }
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

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
    final ok =
        await _shareFile(pkg, bytes, mimeType, fileName, toSystem: false);
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
