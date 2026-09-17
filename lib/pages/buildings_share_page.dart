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

  /// 勾选要分享的楼宇（[widget.buildings] 的下标），默认全选。
  late Set<int> _selected = {
    for (var i = 0; i < widget.buildings.length; i++) i,
  };

  /// 分享时是否带上各楼节的节次时间段。
  bool _withPeriods = true;

  /// 楼宇 JSON 与二维码：二维码与数据文件共用同一份数据
  /// （导出模式下由「分享内容」选项决定内容）。
  String _json = '';
  String? _payload;

  /// 待导出的二维码图片（导入模式或内容过大时为 null）。
  Uint8List? _qrPng;

  @override
  void initState() {
    super.initState();
    if (!widget.importMode) _rebuild();
  }

  /// 按当前选项重新生成 json / 二维码（不触发重建，调用方负责 setState）。
  void _rebuild() {
    final json = BuildingsSharePackage(_effectiveBuildings).toJson();
    _json = ScheduleShareService.encodeJson(json);
    _payload = ScheduleShareService.qrPayloadOf(json);
    _qrPng = _payload == null
        ? null
        : ScheduleShareService.renderQrPng(
            _payload!,
            size: 260,
            quiet: 20,
            scale: 3,
          );
  }

  /// 当前选项下真正要分享的楼宇；未勾选任何楼宇时为空。
  List<Building> get _effectiveBuildings => [
        for (var i = 0; i < widget.buildings.length; i++)
          if (_selected.contains(i))
            _withPeriods
                ? widget.buildings[i].copy()
                : (widget.buildings[i].copy()..periodTimes = []),
      ];

  /// 「分享内容」一行里的摘要文字。
  String _optionsSummary() {
    final total = widget.buildings.length;
    if (_selected.isEmpty) return '未选择任何楼宇';
    final scope =
        _selected.length == total ? '全部 $total 栋楼宇' : '已选 ${_selected.length}/$total 栋楼宇';
    return '$scope · ${_withPeriods ? '含节次时间段' : '仅楼宇名称'}';
  }

  /// 打开「分享内容」弹窗：勾选楼宇、选择是否带节次时间段。
  Future<void> _openOptions() async {
    final result = await showDialog<({Set<int> selected, bool withPeriods})>(
      context: context,
      builder: (_) => _BuildingsOptionsDialog(
        buildings: widget.buildings,
        initialSelected: _selected,
        initialWithPeriods: _withPeriods,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selected = result.selected;
      _withPeriods = result.withPeriods;
      _rebuild();
    });
  }

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
  ///
  /// 与课程表分享一致：导出的不是裸二维码，而是带名称/提示的分享卡片
  /// （页面展示仍用纯二维码，方便直接扫）。
  Future<void> _exportQr() async {
    final png = _qrPng;
    if (png == null) return;
    final card = await ScheduleShareService.renderShareCardPng(
          qrPng: png,
          title: _shareTitle,
          subtitle: '共 ${_effectiveBuildings.length} 栋楼宇',
          tip: '扫一扫，导入楼宇配置',
        ) ??
        png;
    if (!mounted) return;
    if (!_isMobile) {
      await _saveToDisk(card, _qrName, 'png');
      return;
    }
    await showShareSheet(
      context,
      title: _shareTitle,
      type: ShareContentType.image,
      bytes: card,
      fileName: _qrName,
      mimeType: 'image/png',
      onMore: () => _shareViaSystem(card, 'image/png', _qrName),
      onSave: () => _saveToDisk(card, _qrName, 'png'),
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
    final path = await saveBytesToDisk(
      bytes: bytes,
      fileName: fileName,
      allowedExtensions: [ext],
      dialogTitle: '保存$fileName',
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
    final hasSelection = _selected.isNotEmpty;
    final qrUsable = hasSelection && _payload != null && _qrPng != null;
    return [
      // 楼宇信息
      Card(
        child: ListTile(
          leading: Icon(
            Icons.apartment_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            widget.title.isEmpty ? '学校楼宇' : widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '共 ${widget.buildings.length} 栋楼宇（含各楼节次时间段）',
            style: const TextStyle(fontSize: 12),
          ),
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
                '扫码导入这些楼宇',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              if (!hasSelection)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '未选择任何楼宇，无法分享。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                    ),
                  ),
                )
              else if (!qrUsable)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '楼宇内容过多，二维码装不下。\n'
                    '请使用下方「${_isMobile ? '分享数据文件' : '保存数据文件'}」导出。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              else
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.memory(_qrPng!, width: 240, height: 240),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: hasSelection ? _exportJson : null,
        icon: Icon(
          _isMobile ? Icons.share_outlined : Icons.download_outlined,
        ),
        label: Text(_isMobile ? '分享数据文件' : '保存数据文件'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: qrUsable ? _exportQr : null,
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

/// 楼宇分享内容选择弹窗：勾选要分享的楼宇、是否带上节次时间段。
class _BuildingsOptionsDialog extends StatefulWidget {
  final List<Building> buildings;
  final Set<int> initialSelected;
  final bool initialWithPeriods;

  const _BuildingsOptionsDialog({
    required this.buildings,
    required this.initialSelected,
    required this.initialWithPeriods,
  });

  @override
  State<_BuildingsOptionsDialog> createState() =>
      _BuildingsOptionsDialogState();
}

class _BuildingsOptionsDialogState extends State<_BuildingsOptionsDialog> {
  late Set<int> _selected = {...widget.initialSelected};
  late bool _withPeriods = widget.initialWithPeriods;

  void _toggle(int index, bool on) => setState(() {
        if (on) {
          _selected.add(index);
        } else {
          _selected.remove(index);
        }
      });

  @override
  Widget build(BuildContext context) {
    final allSelected = _selected.length == widget.buildings.length;
    return AlertDialog(
      title: const Text('分享内容'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                value: _withPeriods,
                onChanged: (v) => setState(() => _withPeriods = v ?? true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('节次时间段'),
                subtitle: const Text(
                  '取消后只分享楼宇名称',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 16),
              Row(
                children: [
                  const Text('楼宇：'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected = {
                          for (var i = 0; i < widget.buildings.length; i++) i,
                        };
                      }
                    }),
                    child: Text(allSelected ? '取消全选' : '全选'),
                  ),
                ],
              ),
              for (var i = 0; i < widget.buildings.length; i++)
                CheckboxListTile(
                  value: _selected.contains(i),
                  onChanged: (v) => _toggle(i, v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    widget.buildings[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    widget.buildings[i].periodTimes.isEmpty
                        ? '未设置节次时间'
                        : '共 ${widget.buildings[i].periodTimes.length} 段节次时间',
                    style: const TextStyle(fontSize: 12),
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
          onPressed: () => Navigator.pop(
            context,
            (selected: _selected, withPeriods: _withPeriods),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
