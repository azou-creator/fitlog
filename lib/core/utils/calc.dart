// 核心业务计算。保持纯函数，方便单测。

/// 单组训练容量：weight × reps。
double calcSetVolume(double weight, int reps) => weight * reps;

/// 总训练容量：所有组 weight × reps 之和，结果保留 1 位小数。
double calcTotalVolume(Iterable<({double weight, int reps})> sets) {
  if (sets.isEmpty) return 0;
  final total = sets.fold<double>(
    0,
    (sum, s) => sum + calcSetVolume(s.weight, s.reps),
  );
  return (total * 10).roundToDouble() / 10;
}

/// 平均配速（秒 / km）。距离非法时返回 0。
int paceSecondsPerKm({
  required int durationSeconds,
  required double distanceKm,
}) {
  if (distanceKm <= 0 || durationSeconds <= 0) return 0;
  return (durationSeconds / distanceKm).round();
}
