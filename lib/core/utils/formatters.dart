import 'calc.dart';

const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

/// 9月30日
String formatMonthDay(DateTime d) => '${d.month}月${d.day}日';

/// 星期三
String formatWeekday(DateTime d) => _weekdays[d.weekday - 1];

/// 2026年9月
String formatMonthTitle(DateTime d) => '${d.year}年${d.month}月';

/// 2026/09/30
String formatFullDate(DateTime d) =>
    '${d.year}/${_two(d.month)}/${_two(d.day)}';

/// 训练时长（中文）：<1分钟 / 58分钟 / 1小时05分
String formatDurationCN(int seconds) {
  if (seconds < 60) return '<1分钟';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h <= 0) return '$m分钟';
  return '$h小时${_two(m)}分';
}

/// 时钟格式：28:32 / 1:02:33（跑步用时等）
String formatClock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '$h:${_two(m)}:${_two(s)}';
  return '${_two(m)}:${_two(s)}';
}

/// 平均配速：5'29"/km
String formatPace(int durationSeconds, double distanceKm) {
  final pace = paceSecondsPerKm(
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
  );
  if (pace <= 0) return '--';
  return "${pace ~/ 60}'${_two(pace % 60)}\"/km";
}

/// 重量显示：去掉多余的 0 并加千分位（6820 → 6,820；22.5 → 22.5）
String formatWeight(double w) {
  var s = w.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final posFromEnd = intPart.length - i;
    buf.write(intPart[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
  }
  if (parts.length > 1) {
    buf
      ..write('.')
      ..write(parts[1]);
  }
  return buf.toString();
}

/// 今天 / 昨天 / 前天，否则 9月30日
String formatRelativeDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff == 2) return '前天';
  return formatMonthDay(d);
}

String _two(int n) => n.toString().padLeft(2, '0');
