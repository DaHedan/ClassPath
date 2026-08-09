import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 国务院节假日调休数据服务。
///
/// 数据源：https://timor.tech/api/holiday/year/{年份}
/// 免费、无需 key，官方限速约 1 次/秒，因此按年份拉取并缓存到本地。
///
/// 缓存结构：{"years": {"2026": {"2026-10-01": {"holiday": true, "name": "国庆节"}, ...}, ...}}
/// holiday 为 true 表示该日期放假（自动停课），false 表示调休补班（照常上课）。
/// name 为该日归属假期名（放假日取自身名字，补班日取 target 对齐的名字，
/// 如「国庆节后补班」记为「国庆节」），用于把补班日对应到具体假期。
/// 兼容旧版缓存（值直接为 bool 的格式）。
class HolidayService {
  HolidayService._();

  static const _cacheKey = 'classpath_holiday_cache';
  static const _api = 'https://timor.tech/api/holiday/year/';

  /// 已缓存的全部节假日：date("YYYY-MM-DD") -> 是否放假。
  static Map<String, bool> _cache = {};

  /// 已缓存的假期归属名：date("YYYY-MM-DD") -> 所属假期名（放/班均归一到主名）。
  static Map<String, String> _names = {};

  /// 已缓存的全部节假日快照（只读使用）。
  static Map<String, bool> get cache => _cache;

  /// 已缓存的假期归属名快照（只读使用）。
  static Map<String, String> get names => _names;

  static Future<void> _loadCache() async {
    if (_cache.isNotEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_cacheKey);
      if (raw == null) return;
      final root = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final years = (root['years'] as Map? ?? {}).cast<String, dynamic>();
      for (final entry in years.entries) {
        final yearMap = (entry.value as Map).cast<String, dynamic>();
        for (final e in yearMap.entries) {
          final v = e.value;
          if (v is bool) {
            // 旧版缓存格式：直接存布尔值。
            _cache[e.key] = v;
          } else if (v is Map) {
            final m = v.cast<String, dynamic>();
            if (m['holiday'] is bool) {
              _cache[e.key] = m['holiday'] as bool;
              final n = m['name'];
              if (n is String && n.isNotEmpty) _names[e.key] = n;
            }
          }
        }
      }
    } catch (_) {
      // 缓存损坏时静默忽略，之后重新拉取。
    }
  }

  /// 确保指定年份的节假日已拉取并缓存；已缓存的年份直接跳过。
  ///
  /// 单年份拉取失败时静默降级（该年没有数据时放假判断退化为「不放假」）。
  static Future<void> ensureYears(List<int> years) async {
    if (years.isEmpty) return;
    await _loadCache();
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_cacheKey);
    var root = <String, dynamic>{};
    if (raw != null) {
      try {
        root = (jsonDecode(raw) as Map).cast<String, dynamic>();
      } catch (_) {}
    }
    final yearsMap = (root['years'] as Map? ?? {}).cast<String, dynamic>();
    var changed = false;
    for (final year in years) {
      final key = '$year';
      // 已缓存且为最新格式（含假期名）的年份跳过；
      // 旧版纯布尔缓存缺少假期名，重新拉取以获得补班日与假期的对应关系。
      final cached = yearsMap[key];
      final legacy = cached is Map && (cached as Map).values.any((v) => v is bool);
      if (cached != null && !legacy) continue;
      final data = await _fetchYear(year);
      if (data == null) continue;
      yearsMap[key] = data.map((date, v) => MapEntry(
          date, {'holiday': v.holiday, if (v.name != null) 'name': v.name}));
      _cache.addAll(data.map((date, v) => MapEntry(date, v.holiday)));
      _names.addAll({
        for (final e in data.entries)
          if (e.value.name != null) e.key: e.value.name!,
      });
      changed = true;
      // 官方接口限速约 1 次/秒，多个年份时错开请求。
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    if (changed) {
      root['years'] = yearsMap;
      try {
        await p.setString(_cacheKey, jsonEncode(root));
      } catch (_) {
        // 缓存写入失败不影响内存数据。
      }
    }
  }

  /// 拉取某年数据：date -> (是否放假, 归一后的假期名)。
  /// 放假日取自身的 name；补班日取 target（如「国庆节后补班」->「国庆节」），
  /// 这样补班日与放假日能按同名直接对应到同一个假期。
  static Future<Map<String, ({bool holiday, String? name})>?> _fetchYear(
      int year) async {
    try {
      final resp = await http
          .get(Uri.parse('$_api$year'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final holiday = (json['holiday'] as Map? ?? {}).cast<String, dynamic>();
      final result = <String, ({bool holiday, String? name})>{};
      for (final entry in holiday.entries) {
        final item = (entry.value as Map).cast<String, dynamic>();
        final date = item['date'] as String?;
        final isHoliday = item['holiday'] as bool?;
        if (date == null || isHoliday == null) continue;
        final name = isHoliday
            ? item['name'] as String?
            : (item['target'] as String? ?? item['name'] as String?);
        result[date] = (holiday: isHoliday, name: name);
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  /// [date]（"YYYY-MM-DD"）在 [cache] 中是否为放假日。
  static bool isRest(Map<String, bool> cache, String date) =>
      cache[date] == true;
}
