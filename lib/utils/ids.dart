import 'dart:math';

/// 生成一个稳定的唯一 ID（用于课程表、课程在本地存储中的身份标识）。
String genId() {
  final rnd = Random();
  return '${DateTime.now().microsecondsSinceEpoch}_${rnd.nextInt(0xFFFF)}';
}
