import 'dart:math' as math;
import 'dart:ui' show Rect;

/// 图中一行文字及其在图片里的位置（像素坐标）。
///
/// 这是 OCR 与解析算法之间的唯一契约：换 OCR 引擎（ML Kit 等）时，
/// 只要把结果转成 [OcrLine] 列表即可，解析逻辑不用动。
class OcrLine {
  final String text;
  final Rect box;

  const OcrLine(this.text, this.box);

  double get cx => box.center.dx;
  double get cy => box.center.dy;
}

/// 解析出的一次上课时间。
class ParsedClassTime {
  /// 1=周一 … 7=周日。
  final int weekday;

  /// 起止节次。
  final int startPeriod;
  final int endPeriod;

  /// 上课周；null 表示全部周。
  final List<int>? weeks;

  /// 该次上课的地点原文（如「J301多」「（电工实验室）训1353」）。
  final String? location;

  const ParsedClassTime({
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.weeks,
    this.location,
  });

  String get periodLabel => startPeriod == endPeriod
      ? '第$startPeriod节'
      : '第$startPeriod-$endPeriod节';
}

/// 解析出的一门课程（同名课程会由多个单元格合并而来）。
class ParsedCourse {
  final String name;
  final String? id;
  final String? teacher;
  final String? location;

  /// 多个单元格合并后的全部上课时间。
  final List<ParsedClassTime> classTimes;

  /// 合并前各单元格的原始识别文本，供人工核对。
  final String rawText;

  const ParsedCourse({
    required this.name,
    this.id,
    this.teacher,
    this.location,
    required this.classTimes,
    required this.rawText,
  });
}

/// 解析结果。[error] 非空表示表格结构没认出来（列头/节次列缺失）。
class TimetableParseResult {
  final List<ParsedCourse> courses;

  /// 识别到的列头文字（如「周一」…），用于确认表格认对了。
  final List<String> weekdays;

  /// 识别到的节次行数。
  final int periodRows;

  final String? error;

  const TimetableParseResult({
    required this.courses,
    required this.weekdays,
    required this.periodRows,
    this.error,
  });
}

/// 图片课程表解析（纯算法，不含 OCR）。
///
/// 定位策略不硬编码列数 / 行数：
/// - 列由表头的「星期X / 周X」文字位置决定；
/// - 行由左侧的节次编号决定；
/// - 周次、节次、教师、地点从单元格文本里按关键词正则提取，
///   不依赖字段的固定顺序，因此能覆盖多数学校的排版。
class TimetableImageParser {
  TimetableImageParser._();

  static const _weekdayChars = ['一', '二', '三', '四', '五', '六', '日', '天'];

  /// 「(1-3,5~12周)(1-2节) J301多 陈莉」里的周次部分。
  static final RegExp _weekRe = RegExp(
    r'[（(]?\s*([0-9][0-9,，、\-~～至\s]*?)\s*(单|双)?\s*周\s*(?:[（(]\s*(单|双)\s*[）)])?',
  );

  /// 同上文本里的节次部分。
  static final RegExp _periodRe = RegExp(
    r'[（(]?\s*(?:第)?\s*([0-9]{1,2}(?:\s*[-~～至]\s*[0-9]{1,2})?)\s*节\s*[）)]?',
  );

  /// 课程编号：3-6 位独立数字。
  static final RegExp _idRe = RegExp(r'^\d{3,6}$');

  /// 表格边框、复选框之类的符号会被当成字符混进文字里。
  static final RegExp _decorationRe = RegExp(r'[|｜¦□■▪▲△★☆﹁﹂「」]+');

  /// 节次行号常被粘在课程名前面（如「6大学物理A(下)」）；
  /// 只在后面紧跟汉字时才当行号清掉，避免误伤「3D打印」这类课名。
  static final RegExp _leadingPeriodNoRe = RegExp(r'^\d{1,2}(?=[\u4e00-\u9fa5])');

  /// 房号后缀字：本校房号形如「C306多」「J301多」，这里的字跟着地点而非姓名。
  static const _roomSuffixChars = {'多', '楼'};

  static TimetableParseResult parse(List<OcrLine> rawLines) {
    if (rawLines.isEmpty) {
      return const TimetableParseResult(
        courses: [],
        weekdays: [],
        periodRows: 0,
        error: '未识别到任何文字',
      );
    }

    // 0. ML Kit 会把同一水平线、跨列（甚至跨到左侧节次列）的文字并成一个「行」，
    //    直接用行框判列会把整行算进某一列。这里先按水平间距把词框拼回「段」：
    //    同一行、间距小的拼成一段，间距大的断开——断开处正是列/格的分界。
    final lines = _mergeWordsIntoRuns(rawLines);

    // 1. 列头：星期X / 周X。
    final headers = <(int, OcrLine)>[];
    for (final l in lines) {
      final w = _weekdayOf(l.text.trim());
      if (w != null) headers.add((w, l));
    }
    if (headers.length < 2) {
      return const TimetableParseResult(
        courses: [],
        weekdays: [],
        periodRows: 0,
        error: '未识别到星期列表头',
      );
    }
    headers.sort((a, b) => a.$2.cx.compareTo(b.$2.cx));
    var headerBottom = headers.first.$2.box.bottom;
    for (final h in headers) {
      if (h.$2.box.bottom > headerBottom) headerBottom = h.$2.box.bottom;
    }

    // 2. 节次行：位于列头左侧的纯数字（或「第N节」）。
    //    同时记录这些编号的最右边缘，作为「表格主体」的左边界，
    //    避免用列头文字的左边（可能在列内部）而丢掉最左列靠左的文字。
    final periodRows = <(int, double)>[];
    var bodyLeft = headers.first.$2.box.left;
    var hasPeriodCol = false;
    for (final l in lines) {
      if (l.cx >= headers.first.$2.cx) continue;
      final p = _periodNumberOf(l.text.trim());
      if (p == null) continue;
      periodRows.add((p, l.cy));
      bodyLeft = !hasPeriodCol || l.box.right > bodyLeft ? l.box.right : bodyLeft;
      hasPeriodCol = true;
    }
    periodRows.sort((a, b) => a.$2.compareTo(b.$2));
    // 同编号只保留一次。
    final periods = <int>[];
    final periodYs = <double>[];
    for (final r in periodRows) {
      if (periods.contains(r.$1)) continue;
      periods.add(r.$1);
      periodYs.add(r.$2);
    }
    if (periods.isEmpty) {
      return TimetableParseResult(
        courses: const [],
        weekdays: [for (final h in headers) _weekdayLabel(h.$1)],
        periodRows: 0,
        error: '未识别到节次列',
      );
    }

    // 列 / 行都按「相邻中心的中点」划分区间。
    final colCenters = [for (final h in headers) h.$2.cx];
    final rowCenters = periodYs;

    // 3. 先按列归拢文字行，再在列内把纵向紧挨着的行聚成一个「单元格文本块」。
    //    一门课的多行文字是紧挨着的，不同课程/不同行之间会被行高隔开；
    //    这样即使一个单元格的文字跨到了下一节的范围内，也仍属于同一个格子。
    final colBounds = _bandBounds(colCenters);
    final byColumn = <int, List<OcrLine>>{};
    for (final l in lines) {
      if (_weekdayOf(l.text.trim()) != null) continue; // 列头
      if (l.box.top <= headerBottom) continue; // 表头行
      if (l.box.right <= bodyLeft) continue; // 左侧节次列
      for (final piece in _splitRunByColumns(l, colBounds)) {
        byColumn.putIfAbsent(piece.$1, () => []).add(piece.$2);
      }
    }

    // 节次行高（相邻节次中心距）取中位数，比只看前两行稳。
    final rowGap = _medianAdjacentGap(rowCenters, fallback: 40.0);

    // 每个「按间距分出的块」就是一个单元格。
    // 注意不能按 (列, 节次) 再做一次合并：节次列常常识别不全（行号被粘进课程名），
    // 那样同一列里相隔很远的两个格子会撞到同一个 key 而被并成一门课。
    final cells = <(int ci, int period, List<OcrLine> lines)>[];
    for (final entry in byColumn.entries) {
      final list = entry.value..sort((a, b) {
          final dy = a.cy.compareTo(b.cy);
          return dy != 0 ? dy : a.cx.compareTo(b.cx);
        });
      // 「换格子」的门槛：格子内部各行的间距远小于跨格处的间距，
      // 用本列行距的中位数就能自适应不同截图的字号与留白。
      final gaps = <double>[];
      double? lastBottom;
      for (final l in list) {
        if (lastBottom != null && l.box.top - lastBottom > 0) {
          gaps.add(l.box.top - lastBottom);
        }
        lastBottom = l.box.bottom;
      }
      final gapMax = math.min(
        (_median(gaps) ?? rowGap * 0.25) * 2,
        rowGap * 0.45,
      );
      var block = <OcrLine>[];
      int? blockRow;
      double? prevBottom;

      void flush() {
        if (block.isEmpty) return;
        final ri = blockRow;
        if (ri != null) {
          cells.add((entry.key, periods[ri], [...block]));
        }
        block = <OcrLine>[];
        blockRow = null;
      }

      for (final l in list) {
        final ri = _bandIndex(rowCenters, l.cy);
        if (block.isNotEmpty) {
          // 空行隔开、或整行跨了不止一节，就另起一个单元格。
          final rowJump = ri != null && blockRow != null && ri > blockRow! + 1;
          final gap = prevBottom == null ? 0.0 : l.box.top - prevBottom;
          if (rowJump || gap > gapMax) flush();
        }
        if (block.isEmpty) blockRow = ri;
        block.add(l);
        prevBottom = l.box.bottom;
      }
      flush();
    }

    // 4. 逐单元格解析，再按课程名合并。
    final byName = <String, List<ParsedCourse>>{};
    for (final cell in cells) {
      final ci = cell.$1;
      if (ci < 0 || ci >= headers.length) continue;
      final list = cell.$3..sort((a, b) {
          final dy = a.cy.compareTo(b.cy);
          return dy != 0 ? dy : a.cx.compareTo(b.cx);
        });
      final text = list.map((e) => e.text.trim()).where((t) => t.isNotEmpty).join('\n');
      if (text.isEmpty) continue;
      final weekday = headers[ci].$1;
      final parsed = _parseCell(text, weekday, cell.$2);
      if (parsed == null) continue;
      byName.putIfAbsent(parsed.name, () => []).add(parsed);
    }

    final courses = <ParsedCourse>[];
    for (final group in byName.values) {
      courses.add(_merge(group));
    }
    courses.sort((a, b) {
      final w = a.classTimes.first.weekday.compareTo(b.classTimes.first.weekday);
      if (w != 0) return w;
      return a.classTimes.first.startPeriod.compareTo(b.classTimes.first.startPeriod);
    });

    return TimetableParseResult(
      courses: courses,
      weekdays: [for (final h in headers) _weekdayLabel(h.$1)],
      periodRows: periods.length,
      error: courses.isEmpty ? '未能从表格中解析出课程' : null,
    );
  }

  /// 星期文字 → 1..7；不是星期表头返回 null。
  static int? _weekdayOf(String s) {
    final m = RegExp(r'^(?:星期|周|礼拜)\s*([一二三四五六日天])$').firstMatch(s);
    if (m == null) return null;
    final i = _weekdayChars.indexOf(m.group(1)!);
    if (i < 0) return null;
    return i >= 7 ? 7 : i + 1;
  }

  static String _weekdayLabel(int weekday) => '周${_weekdayChars[weekday - 1]}';

  /// 「12」「第12节」→ 12。
  static int? _periodNumberOf(String s) {
    final m = RegExp(r'^(?:第)?\s*(\d{1,2})\s*节?$').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// 中心位置 [c] 落在 [centers] 划分的哪个区间：
  /// 区间边界取相邻中心的中点，因此取的是「最近的一行/一列」。
  static int? _bandIndex(List<double> centers, double c) {
    if (centers.isEmpty) return null;
    for (var i = 0; i < centers.length - 1; i++) {
      if (c < (centers[i] + centers[i + 1]) / 2) return i;
    }
    return centers.length - 1;
  }

  /// 中位数；空列表返回 null。
  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// 相邻数值间距的中位数，用于估计节次行高这类尺度。
  static double _medianAdjacentGap(List<double> values, {required double fallback}) {
    if (values.length < 2) return fallback;
    final gaps = <double>[];
    for (var i = 1; i < values.length; i++) {
      final g = (values[i] - values[i - 1]).abs();
      if (g > 0.5) gaps.add(g);
    }
    if (gaps.isEmpty) return fallback;
    gaps.sort();
    return gaps[gaps.length ~/ 2];
  }

  /// 相邻中心的中点划分出的区间；最左/最右区间向外无限延伸。
  static List<(double, double)> _bandBounds(List<double> centers) {
    final bounds = <(double, double)>[];
    for (var i = 0; i < centers.length; i++) {
      final left = i == 0 ? double.negativeInfinity : (centers[i - 1] + centers[i]) / 2;
      final right =
          i == centers.length - 1 ? double.infinity : (centers[i] + centers[i + 1]) / 2;
      bounds.add((left, right));
    }
    return bounds;
  }

  static int? _bandIndexFromBounds(List<(double, double)> bounds, double c) {
    if (bounds.isEmpty) return null;
    for (var i = 0; i < bounds.length; i++) {
      if (c >= bounds[i].$1 && c < bounds[i].$2) return i;
    }
    return bounds.length - 1;
  }

  /// 把 OCR 输出的词框按「同一行 + 水平间距」拼回文字段。
  ///
  /// ML Kit 的行框可能横跨多列，但词框是贴着文字的；因此：
  /// - 间距小 → 直接相连（CJK 词框之间本来就没有空格）；
  /// - 间距中等（词间空格）→ 连成一段但补一个空格，保留「地点 教师」这类分词；
  /// - 间距大（跨列/跨格）→ 断开成两段，各自再判列。
  static List<OcrLine> _mergeWordsIntoRuns(List<OcrLine> words) {
    final sorted = [...words]..sort((a, b) {
        final dy = a.box.top.compareTo(b.box.top);
        return dy != 0 ? dy : a.box.left.compareTo(b.box.left);
      });
    final runs = <OcrLine>[];
    final line = <OcrLine>[];

    void flushLine() {
      if (line.isEmpty) return;
      line.sort((a, b) => a.box.left.compareTo(b.box.left));
      var current = <OcrLine>[];

      void flushRun() {
        if (current.isEmpty) return;
        final sb = StringBuffer();
        var left = current.first.box.left;
        var right = current.first.box.right;
        var top = current.first.box.top;
        var bottom = current.first.box.bottom;
        for (final w in current) {
          sb.write(w.text);
          left = math.min(left, w.box.left);
          right = math.max(right, w.box.right);
          top = math.min(top, w.box.top);
          bottom = math.max(bottom, w.box.bottom);
        }
        final text = sb.toString().trim();
        if (text.isNotEmpty) {
          runs.add(OcrLine(text, Rect.fromLTRB(left, top, right, bottom)));
        }
        current = <OcrLine>[];
      }

      double? prevRight;
      var heightSum = 0.0;
      for (final w in line) {
        if (current.isNotEmpty && prevRight != null) {
          final avgH = heightSum / current.length;
          final gap = w.box.left - prevRight;
          if (gap > math.max(6, avgH * 0.4)) {
            flushRun();
            heightSum = 0;
            prevRight = null;
          } else if (gap > math.max(2, avgH * 0.15)) {
            current.add(OcrLine(' ', Rect.fromLTRB(prevRight, w.box.top, w.box.left, w.box.bottom)));
          }
        }
        current.add(w);
        prevRight = w.box.right;
        heightSum += w.box.height;
      }
      flushRun();
      line.clear();
    }

    for (final w in sorted) {
      if (line.isNotEmpty) {
        final anchor = line.first;
        final sameLine =
            (w.cy - anchor.cy).abs() <= 0.6 * math.max(w.box.height, anchor.box.height);
        if (!sameLine) flushLine();
      }
      line.add(w);
    }
    flushLine();
    return runs;
  }

  /// 把一段文字落到列上。正常一段只落一列；若词框本身横跨多列
  /// （OCR 仍把跨列文字并进一个词框），就按列边界切开。
  static List<(int, OcrLine)> _splitRunByColumns(
    OcrLine run,
    List<(double, double)> bounds,
  ) {
    if (bounds.isEmpty) return const [];
    // 只在「确实横跨多列」时才切：某列占的宽度不到两成就忽略它，
    // 否则贴边的正常文字会被切掉尾巴。
    final crossed = <int>[];
    final minShare = run.box.width * 0.2;
    for (var i = 0; i < bounds.length; i++) {
      final overlap = math.min(run.box.right, bounds[i].$2) - math.max(run.box.left, bounds[i].$1);
      if (overlap > minShare) crossed.add(i);
    }
    if (crossed.length <= 1) {
      final ci = _bandIndexFromBounds(bounds, run.cx);
      return ci == null ? const [] : [(ci, run)];
    }
    final text = run.text;
    final width = run.box.width;
    final out = <(int, OcrLine)>[];
    var start = 0;
    for (var k = 0; k < crossed.length; k++) {
      final ci = crossed[k];
      final segLeft = math.max(run.box.left, bounds[ci].$1);
      final segRight = math.min(run.box.right, bounds[ci].$2);
      var end = text.length;
      if (k < crossed.length - 1 && width > 0) {
        end = _refineCut(
          text,
          start,
          (text.length * (segRight - run.box.left) / width).round(),
        );
      }
      if (end <= start) continue;
      final piece = text.substring(start, end).trim();
      if (piece.isNotEmpty) {
        out.add((ci, OcrLine(piece, Rect.fromLTRB(segLeft, run.box.top, segRight, run.box.bottom))));
      }
      start = end;
      if (start >= text.length) break;
    }
    return out;
  }

  /// 按比例算出的切点会因中英文字宽不同而偏一两个字，
  /// 这里在附近找「新起一段周次/节次」的位置（左括号前）来对齐，
  /// 退而求其次找空格。
  static int _refineCut(String text, int from, int cut) {
    final c = cut.clamp(from, text.length);
    for (var d = 0; d <= 3; d++) {
      for (final cand in [c - d, c + d]) {
        if (cand <= from || cand >= text.length) continue;
        if (_isSpecOpen(text[cand])) return cand;
      }
    }
    return _snapToSpace(text, from, c);
  }

  static bool _isSpecOpen(String ch) => ch == '(' || ch == '（' || ch == '[' || ch == '【';

  /// 切点尽量落在空格上（前后各找一个最近的），
  /// 避免把半个词切给隔壁列。
  static int _snapToSpace(String text, int from, int cut) {
    final c = cut.clamp(from, text.length);
    for (var d = 0; d < 12; d++) {
      final forward = c + d;
      if (forward < text.length && _isSpace(text[forward])) return forward + 1;
      final backward = c - d;
      if (backward > from && _isSpace(text[backward - 1])) return backward;
    }
    return c;
  }

  static bool _isSpace(String ch) => ch == ' ' || ch == '\u3000' || ch == '\n';

  /// 解析一个单元格：拆出课程名/编号，以及（可多组）周次+节次+地点+教师。
  static ParsedCourse? _parseCell(String text, int weekday, int fallbackPeriod) {
    // 收集周次 / 节次片段的位置，按出现顺序配对。
    final tokens = <_Token>[];
    for (final m in _weekRe.allMatches(text)) {
      tokens.add(_Token(m.start, m.end,
          weekSpec: m.group(1), oddEven: m.group(2) ?? m.group(3)));
    }
    for (final m in _periodRe.allMatches(text)) {
      tokens.add(_Token(m.start, m.end, periodSpec: m.group(1)));
    }
    tokens.sort((a, b) => a.start.compareTo(b.start));

    final specs = <_Spec>[];
    for (final t in tokens) {
      if (t.isWeek) {
        specs.add(_Spec(weekSpec: t.weekSpec, oddEven: t.oddEven, start: t.start, end: t.end));
      } else if (specs.isNotEmpty && specs.last.periodSpec == null) {
        specs.last.periodSpec = t.periodSpec;
        specs.last.end = t.end;
      } else {
        specs.add(_Spec(periodSpec: t.periodSpec, start: t.start, end: t.end));
      }
    }

    final head = specs.isEmpty ? text : text.substring(0, specs.first.start);
    final headInfo = _parseHead(head);
    if (headInfo.name.isEmpty) return null;

    final classTimes = <ParsedClassTime>[];
    String? location;
    String? teacher;
    if (specs.isEmpty) {
      classTimes.add(ParsedClassTime(
        weekday: weekday,
        startPeriod: fallbackPeriod,
        endPeriod: fallbackPeriod,
      ));
    } else {
      for (var i = 0; i < specs.length; i++) {
        final s = specs[i];
        final tail = text.substring(
          s.end,
          i + 1 < specs.length ? specs[i + 1].start : text.length,
        );
        final tailInfo = _parseTail(tail);
        location ??= tailInfo.$1;
        teacher ??= tailInfo.$2;
        final range = s.periodSpec == null ? null : _parsePeriodSpec(s.periodSpec!);
        final a = range?.$1 ?? fallbackPeriod;
        final b = range?.$2 ?? fallbackPeriod;
        final weeks = s.weekSpec == null ? null : _parseWeekSpec(s.weekSpec!, s.oddEven);
        classTimes.add(ParsedClassTime(
          weekday: weekday,
          startPeriod: a < b ? a : b,
          endPeriod: a < b ? b : a,
          weeks: (weeks == null || weeks.isEmpty) ? null : weeks,
          location: tailInfo.$1,
        ));
      }
    }

    return ParsedCourse(
      name: headInfo.name,
      id: headInfo.id,
      teacher: teacher,
      location: location,
      classTimes: classTimes,
      rawText: text,
    );
  }

  /// 单元格头部：课程名（取最长的中文行）+ 编号（独立数字行）。
  static ({String name, String? id}) _parseHead(String head) {
    final lines = head
        .split('\n')
        .map((e) => _cleanText(e).replaceFirst(_leadingPeriodNoRe, '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
    String? id;
    final candidates = <String>[];
    for (final line in lines) {
      if (id == null && _idRe.hasMatch(line)) {
        id = line;
        continue;
      }
      candidates.add(line);
    }
    if (candidates.isEmpty) return (name: '', id: id);
    // 名字通常是字数最多的那行（避免把「电学磁学」这类小字备注当成课名）。
    var name = candidates.first;
    var best = _cjkCount(name);
    for (final c in candidates.skip(1)) {
      final n = _cjkCount(c);
      if (n > best) {
        name = c;
        best = n;
      }
    }
    return (name: name, id: id);
  }

  /// 清掉表格边框之类的装饰符号。
  static String _cleanText(String s) => s.replaceAll(_decorationRe, '').trim();

  /// 地点尾串：「J301多 陈莉」→ 地点 J301多、教师 陈莉。
  ///
  /// 单元格文字常被折行（甚至把姓名拆成两半），所以先按行拼回整串，
  /// 再切出结尾的教师名。
  static (String?, String?) _parseTail(String tail) {
    final text = _cleanText(tail.replaceAll('\n', ''));
    if (text.isEmpty) return (null, null);
    final run = RegExp(r'[\u4e00-\u9fa5]+$').firstMatch(text);
    if (run == null) return (text, null);
    var start = run.start;
    // 房号后缀跟着地点（「C306多卞之豪」→ 地点 C306多、教师 卞之豪）。
    if (run.group(0)!.length >= 3 &&
        start > 0 &&
        _roomSuffixChars.contains(text[start]) &&
        RegExp(r'[0-9A-Za-z]').hasMatch(text[start - 1])) {
      start += 1;
    }
    final teacher = text.substring(start);
    // 结尾这段得确实像个姓名（2-4 个汉字），否则整串都是地点。
    if (teacher.length < 2 || teacher.length > 4 || _cjkCount(teacher) != teacher.length) {
      return (text, null);
    }
    final location = text.substring(0, start).trim();
    return (location.isEmpty ? null : location, teacher);
  }

  static int _cjkCount(String s) =>
      s.runes.where((r) => r >= 0x4E00 && r <= 0x9FA5).length;

  /// 「1-3,5~12」→ [1,2,3,5,…,12]；[oddEven] 为「单」「双」时只保留奇/偶周。
  static List<int> _parseWeekSpec(String spec, String? oddEven) {
    final s = spec.replaceAll(RegExp(r'[（()）\s]'), '');
    final rangeRe = RegExp(r'(\d{1,2})\s*[-~～至]\s*(\d{1,2})');
    final weeks = <int>{};
    for (final m in rangeRe.allMatches(s)) {
      final a = int.tryParse(m.group(1)!) ?? 0;
      final b = int.tryParse(m.group(2)!) ?? 0;
      for (var w = a; w <= b && w <= 60; w++) {
        if (w >= 1) weeks.add(w);
      }
    }
    for (final m in RegExp(r'\d{1,2}').allMatches(s.replaceAll(rangeRe, ' '))) {
      final w = int.tryParse(m.group(0)!) ?? 0;
      if (w >= 1 && w <= 60) weeks.add(w);
    }
    var list = weeks.toList()..sort();
    if (oddEven == '单') list = list.where((w) => w.isOdd).toList();
    if (oddEven == '双') list = list.where((w) => w.isEven).toList();
    return list;
  }

  /// 「1-2」「10-14」「3」→ (起, 止)。
  static (int, int)? _parsePeriodSpec(String spec) {
    final m = RegExp(r'^\s*(\d{1,2})\s*[-~～至]\s*(\d{1,2})\s*$').firstMatch(spec);
    if (m != null) {
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a != null && b != null) return (a, b);
    }
    final single = RegExp(r'^\s*(\d{1,2})\s*$').firstMatch(spec);
    if (single != null) {
      final p = int.tryParse(single.group(1)!);
      if (p != null) return (p, p);
    }
    return null;
  }

  /// 同名课程的多个单元格合并成一门课。
  static ParsedCourse _merge(List<ParsedCourse> group) {
    final first = group.first;
    final times = <ParsedClassTime>[];
    String? id;
    String? teacher;
    String? location;
    final raws = <String>[];
    for (final c in group) {
      times.addAll(c.classTimes);
      id ??= c.id;
      teacher ??= c.teacher;
      location ??= c.location;
      if (!raws.contains(c.rawText)) raws.add(c.rawText);
    }
    times.sort((a, b) {
      final w = a.weekday.compareTo(b.weekday);
      return w != 0 ? w : a.startPeriod.compareTo(b.startPeriod);
    });
    return ParsedCourse(
      name: first.name,
      id: id,
      teacher: teacher,
      location: location,
      classTimes: times,
      rawText: raws.join('\n---\n'),
    );
  }
}

class _Token {
  final int start;
  final int end;
  final String? weekSpec;
  final String? oddEven;
  final String? periodSpec;

  _Token(this.start, this.end, {this.weekSpec, this.oddEven, this.periodSpec});

  bool get isWeek => weekSpec != null;
}

class _Spec {
  final String? weekSpec;
  final String? oddEven;
  String? periodSpec;
  final int start;
  int end;

  _Spec({this.weekSpec, this.oddEven, this.periodSpec, required this.start, required this.end});
}
