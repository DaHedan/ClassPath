import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

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
  /// 分享内容选项：进入页面时弹出选择，决定实际导出的内容。
  ShareOptions _options = const ShareOptions();

  /// 当前选项下实际导出的数据。
  late String _json;
  String? _payload;
  bool _compressed = false;

  /// 当前选项下实际导出的课程数。
  int _courseCount = 0;

  /// 页面展示的二维码：与导出/分享的图片同源（离屏渲染），
  /// 保证"软件里看到的"和"保存出去的"完全一致。
  Uint8List? _displayQrPng;

  @override
  void initState() {
    super.initState();
    _rebuildPayload();
    _loadDisplayQr();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openOptions());
  }

  /// 按当前分享内容选项重新生成导出数据。
  void _rebuildPayload() {
    final pkg = ScheduleShareService.filtered(
      widget.schedule,
      widget.courses,
      _options,
    );
    _json = ScheduleShareService.encode(pkg.schedule, pkg.courses);
    _payload = ScheduleShareService.qrPayload(pkg.schedule, pkg.courses);
    _compressed = _payload?.startsWith(compressedMagic) ?? false;
    _courseCount = pkg.courses.length;
  }

  /// 弹出「分享内容」选择弹窗；确认后按新选项重新生成二维码与数据。
  Future<void> _openOptions() async {
    if (!mounted) return;
    final result = await showDialog<ShareOptions>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShareOptionsDialog(
        initial: _options,
        courses: widget.courses,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _options = result;
      _rebuildPayload();
      _displayQrPng = null;
    });
    _loadDisplayQr();
  }

  /// 「分享内容」摘要：列出当前勾选的可选内容。
  String _optionsSummary() {
    final parts = <String>[
      if (_options.meals) '用餐时间',
      if (_options.reschedules) '调休安排',
      if (_options.courses) '课程',
      if (_options.courses && _options.teacher) '教师',
      if (_options.courses && _options.remind) '提前提醒',
      if (_options.courses && _options.exam) '考试信息',
      if (_options.courses && _options.note) '备注',
      if (_options.courses && _options.excludedCourses.isNotEmpty)
        '排除${_options.excludedCourses.length}门',
    ];
    return parts.isEmpty ? '仅课程表基本信息' : parts.join('、');
  }

  Future<void> _loadDisplayQr() async {
    final payload = _payload;
    if (payload == null) return;
    final png = await _renderQrPng(payload);
    if (mounted) setState(() => _displayQrPng = png);
  }

  String get _fileName => '${widget.schedule.name}_课表.json';

  /// 手机端走系统分享面板；桌面端保持保存文件。
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 二维码 payload 长度上限。内容过长时强行编码会得到超高密度二维码，
  /// 相册等静态识别困难，渲染也可能出错，此时只提供文件导出。
  static const int _qrMaxLen = 2400;

  /// 当前课程表是否适合用二维码承载。
  bool get _qrUsable => _payload != null && _payload!.length <= _qrMaxLen;

  /// 导出二维码的渲染参数（逻辑像素，最终以 _qrScale 倍分辨率输出）。
  static const double _qrRenderSize = 260;
  static const double _qrQuiet = 20;
  static const int _qrScale = 3;

  /// 渲染一张纯二维码图（白底 + 静区），供页面展示，保证页面与导出的
  /// 二维码同源一致。用 image 库绘制（整数像素模块，zxing 易解）。
  Future<Uint8List?> _renderQrPng(String payload) async {
    return ScheduleShareService.renderQrPng(
      payload,
      size: _qrRenderSize,
      quiet: _qrQuiet,
      scale: _qrScale,
    );
  }

  Future<void> _saveFile() async {
    final bytes = Uint8List.fromList(utf8.encode(_json));
    final path = await saveBytesToDisk(
      bytes: bytes,
      fileName: _fileName,
      allowedExtensions: ['json'],
      dialogTitle: '保存课程表',
    );
    if (path != null && mounted) {
      _showSnack('已保存到 $path');
    }
  }

  /// 手机端：把 .json 写入内存文件后调起系统分享面板，可选择应用发送。
  Future<void> _shareJson() async {
    final bytes = Uint8List.fromList(utf8.encode(_json));
    final box = context.findRenderObject() as RenderBox?;
    await shareBytesToSystem(
      bytes: bytes,
      fileName: _fileName,
      mimeType: 'application/json',
      text: '课途课程表：${widget.schedule.name}',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  /// 离屏绘制完整分享卡片（软件图标 + 软件名 + 课程表名称 + 二维码 + 提示），
  /// 以 3 倍分辨率绘制后输出 PNG 字节，不依赖 widget 渲染。
  /// 绘制逻辑在 [ScheduleShareService.renderShareCardPng]，与楼宇分享同款。
  Future<Uint8List?> _renderShareCardPng() async {
    final payload = _payload;
    if (payload == null) return null;

    // 二维码用 image 库绘制（整数像素模块，zxing 易解；含白底静区），
    // 与页面展示用的是同一张图。
    final qrPng = await _renderQrPng(payload);
    if (qrPng == null) return null;
    return ScheduleShareService.renderShareCardPng(
      qrPng: qrPng,
      title: widget.schedule.name,
      subtitle: '共 ${widget.schedule.totalWeeks} 周',
      tip: '扫一扫，导入课程表',
    );
  }

  Future<void> _saveImage() async {
    final bytes = await _renderShareCardPng();
    if (bytes == null || !mounted) return;
    // 手机端存进相册，桌面端另存为。
    final msg = await saveImageBytes(
      bytes: bytes,
      fileName: '${widget.schedule.name}_课表二维码.png',
    );
    if (msg.isNotEmpty && mounted) _showSnack(msg);
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
    await shareBytesToSystem(
      bytes: bytes,
      fileName: '${widget.schedule.name}_课表二维码.png',
      mimeType: 'image/png',
      text: '课途课程表二维码：${widget.schedule.name}',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
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
                '${s.info} · $_courseCount门课\n'
                '第一周周一 ${_dateText(s.firstMonday)}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 12),
          // 分享内容：可选内容在此调整。
          Card(
            child: ListTile(
              leading: Icon(Icons.tune, color: theme.colorScheme.primary),
              title: const Text('分享内容'),
              subtitle: Text(
                _optionsSummary(),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: _openOptions,
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
                    // 页面显示离屏渲染的纯二维码图，与保存/分享出去的
                    // 图片同源；加载完成前显示占位。
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _displayQrPng == null
                            ? const SizedBox(
                                width: 240,
                                height: 240,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                ),
                              )
                            : Image.memory(
                                _displayQrPng!,
                                width: 240,
                                height: 240,
                                gaplessPlayback: true,
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

/// 分享内容选择弹窗：勾选随课程表一起分享的可选内容，
/// 并可排除指定的课程。
///
/// 课程未勾选时，教师 / 提前提醒 / 考试信息 / 备注变灰不可选。
class _ShareOptionsDialog extends StatefulWidget {
  final ShareOptions initial;

  /// 当前课程表的全部课程，用于「排除课程」的选择。
  final List<Course> courses;

  const _ShareOptionsDialog({required this.initial, required this.courses});

  @override
  State<_ShareOptionsDialog> createState() => _ShareOptionsDialogState();
}

class _ShareOptionsDialogState extends State<_ShareOptionsDialog> {
  late ShareOptions _options = widget.initial;

  void _update(ShareOptions next) => setState(() => _options = next);

  /// 选择要从分享中排除的课程。
  Future<void> _pickExcludedCourses() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _CourseExcludeDialog(
        courses: widget.courses,
        selected: _options.excludedCourses,
      ),
    );
    if (result != null && mounted) {
      _update(_options.copyWith(excludedCourses: result));
    }
  }

  void _removeExcluded(String uid) {
    _update(
      _options.copyWith(
        excludedCourses: {
          for (final u in _options.excludedCourses)
            if (u != uid) u,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCourses = _options.courses;
    final excluded = [
      for (final c in widget.courses)
        if (_options.excludedCourses.contains(c.uid)) c,
    ];
    return AlertDialog(
      title: const Text('分享内容'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tile('用餐时间', _options.meals,
                  (v) => _update(_options.copyWith(meals: v))),
              _tile('调休安排', _options.reschedules,
                  (v) => _update(_options.copyWith(reschedules: v))),
              _tile('课程', _options.courses,
                  (v) => _update(_options.copyWith(courses: v))),
              _tile('教师', _options.teacher,
                  hasCourses ? (v) => _update(_options.copyWith(teacher: v)) : null),
              _tile('提前提醒', _options.remind,
                  hasCourses ? (v) => _update(_options.copyWith(remind: v)) : null),
              _tile('考试信息', _options.exam,
                  hasCourses ? (v) => _update(_options.copyWith(exam: v)) : null),
              _tile('备注', _options.note,
                  hasCourses ? (v) => _update(_options.copyWith(note: v)) : null),
              const SizedBox(height: 4),
              // 课程未勾选时，整块「排除课程」（含已排除课程的删除叉）都不可交互。
              Opacity(
                opacity: hasCourses ? 1 : 0.5,
                child: IgnorePointer(
                  ignoring: !hasCourses,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('排除课程：'),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: hasCourses ? _pickExcludedCourses : null,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加'),
                          ),
                        ],
                      ),
                      if (excluded.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in excluded)
                              InputChip(
                                label: Text(c.name),
                                labelStyle: const TextStyle(fontSize: 12),
                                visualDensity: VisualDensity.compact,
                                onDeleted: () => _removeExcluded(c.uid),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _options),
          child: const Text('确定'),
        ),
      ],
    );
  }

  /// 单个勾选项；[onChanged] 为空表示变灰不可选。
  Widget _tile(String label, bool value, ValueChanged<bool>? onChanged) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      value: value,
      onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
    );
  }
}

/// 排除课程选择弹窗：多选要从分享中排除的课程。
class _CourseExcludeDialog extends StatefulWidget {
  final List<Course> courses;
  final Set<String> selected;

  const _CourseExcludeDialog({required this.courses, required this.selected});

  @override
  State<_CourseExcludeDialog> createState() => _CourseExcludeDialogState();
}

class _CourseExcludeDialogState extends State<_CourseExcludeDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('排除课程'),
      content: SizedBox(
        width: 320,
        height: 360,
        child: ListView(
          children: [
            for (final c in widget.courses)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: c.id.trim().isEmpty
                    ? null
                    : Text(c.id, style: const TextStyle(fontSize: 11)),
                value: _selected.contains(c.uid),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _selected.add(c.uid);
                  } else {
                    _selected.remove(c.uid);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
