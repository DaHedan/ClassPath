import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/course.dart';
import '../models/schedule.dart';
import '../services/color_generator.dart';
import '../services/schedule_math.dart';
import '../services/timetable_image_parser.dart';
import '../services/timetable_ocr.dart';
import '../state/app_state.dart';

/// 从图片导入课程：识别一张教务系统课程表截图，
/// 本机离线识别（ML Kit 中文）+ 固定算法解析，再确认导入当前课程表。
/// 选图在进入本页之前就完成了，本页只负责识别结果与导入。
class TimetableImageImportPage extends StatefulWidget {
  final Schedule schedule;

  /// 已选好的课程表图片路径。
  final String imagePath;

  const TimetableImageImportPage({
    super.key,
    required this.schedule,
    required this.imagePath,
  });

  @override
  State<TimetableImageImportPage> createState() =>
      _TimetableImageImportPageState();
}

/// 一门待导入的课程（可勾选）。
class _Candidate {
  final ParsedCourse course;
  final bool importable;

  /// 节次是否落在当前课程表的节数范围内。
  bool selected;

  _Candidate(this.course, {required this.importable})
      : selected = importable;
}

class _TimetableImageImportPageState extends State<TimetableImageImportPage> {
  bool _busy = false;
  String? _message;
  List<_Candidate>? _candidates;

  @override
  void initState() {
    super.initState();
    if (!TimetableOcr.supported) {
      _message = '当前平台不支持图片识别，请在手机上使用。';
      return;
    }
    _recognize(widget.imagePath);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 换一张图重新识别。
  Future<void> _pickAndRecognize() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择课程表图片',
      type: FileType.image,
    );
    if (picked == null || !mounted) return;
    final path = picked.files.single.path;
    if (path == null) {
      _snack('无法读取该图片');
      return;
    }
    await _recognize(path);
  }

  /// OCR → 解析。
  Future<void> _recognize(String path) async {
    setState(() {
      _busy = true;
      _message = '正在识别图片…';
      _candidates = null;
    });
    try {
      final lines = await TimetableOcr.recognizeFile(path);
      final result = TimetableImageParser.parse(lines);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = result.error;
        _candidates = [
          for (final c in result.courses)
            _Candidate(c, importable: _importable(c)),
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '识别失败：$e';
      });
    }
  }

  /// 每节课的节次都要落在课程表的节数范围内才可导入。
  bool _importable(ParsedCourse c) => c.classTimes
      .every((t) => t.startPeriod >= 1 && t.endPeriod <= widget.schedule.periodsPerDay);

  String _timeOf(int period, {required bool start}) {
    final t = widget.schedule.firstBuilding?.timeOf(period);
    if (t != null) return start ? t.start : t.end;
    return start ? '08:00' : '09:40';
  }

  int _nextId(Set<String> used) {
    var max = 0;
    for (final id in used) {
      final n = int.tryParse(id);
      if (n != null && n > max) max = n;
    }
    var next = max + 1;
    while (used.contains('$next')) {
      next++;
    }
    return next;
  }

  Future<void> _import() async {
    final chosen = [
      for (final c in _candidates ?? const <_Candidate>[])
        if (c.selected && c.importable) c,
    ];
    if (chosen.isEmpty) {
      _snack('请选择要导入的课程');
      return;
    }
    final app = context.read<AppState>();
    final existing = app.coursesOf(widget.schedule.id);
    final usedIds = {for (final c in existing) c.id};
    final avoid = [for (final c in existing) c.colorValue];
    var count = 0;
    for (final cand in chosen) {
      final parsedId = cand.course.id;
      final id = (parsedId != null &&
              parsedId.isNotEmpty &&
              !usedIds.contains(parsedId))
          ? parsedId
          : '${_nextId(usedIds)}';
      usedIds.add(id);
      final color = ColorGenerator.generate(avoid: avoid).toARGB32();
      avoid.add(color);
      final courseLocation = cand.course.location == null
          ? CourseLocation()
          : CourseLocation(room: cand.course.location!);
      final course = Course(
        scheduleId: widget.schedule.id,
        id: id,
        name: cand.course.name,
        teacher: cand.course.teacher,
        classTimes: [
          for (final t in cand.course.classTimes)
            ClassTime(
              weekday: t.weekday,
              startPeriod: t.startPeriod,
              endPeriod: t.endPeriod,
              start: _timeOf(t.startPeriod, start: true),
              end: _timeOf(t.endPeriod, start: false),
              // 与课程总体地点相同的就不单独存。
              location: (t.location != null && t.location != cand.course.location)
                  ? CourseLocation(room: t.location!)
                  : null,
              weeks: t.weeks,
            ),
        ],
        location: courseLocation,
        colorValue: color,
      );
      await app.addCourse(course);
      count++;
    }
    if (!mounted) return;
    _snack('已导入 $count 门课程');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = _candidates;
    final selectedCount =
        candidates?.where((c) => c.selected && c.importable).length ?? 0;
    final supported = TimetableOcr.supported;

    return Scaffold(
      appBar: AppBar(title: const Text('图片导入课程')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.image_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: const Text(
                      '重新选择图片',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      '识别结果不对的话，换一张课程表截图重试',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: (_busy || !supported) ? null : _pickAndRecognize,
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_message != null && !_busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                if (candidates != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '识别到 ${candidates.length} 门课程',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final c in candidates) _courseCard(theme, c),
                ],
              ],
            ),
          ),
          if (candidates != null && candidates.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: selectedCount == 0 ? null : _import,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text('导入所选（$selectedCount）'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _courseCard(ThemeData theme, _Candidate cand) {
    final c = cand.course;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Checkbox(
          value: cand.selected,
          onChanged: cand.importable
              ? (v) => setState(() => cand.selected = v ?? false)
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                c.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (c.id != null && c.id!.isNotEmpty)
              Text(
                c.id!,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.teacher != null) ...[
              const SizedBox(height: 2),
              Text(c.teacher!, style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 4),
            for (final t in c.classTimes)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  [
                    ScheduleMath.weekdayName(t.weekday),
                    t.periodLabel,
                    t.weeks == null
                        ? '全部周'
                        : ScheduleMath.weeksToText(t.weeks!),
                    if (t.location != null) t.location!,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!cand.importable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '节次超出当前课程表的节数（${widget.schedule.periodsPerDay} 节），无法导入',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              c.rawText,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
