import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/core/utils/calc.dart';

void main() {
  group('训练容量计算', () {
    test('单组容量 = 重量 × 次数', () {
      expect(calcSetVolume(80, 10), 800);
      expect(calcSetVolume(22.5, 10), 225);
    });

    test('空列表容量为 0', () {
      expect(calcTotalVolume([]), 0);
    });

    test('多组累加', () {
      final v = calcTotalVolume([
        (weight: 60.0, reps: 12),
        (weight: 80.0, reps: 10),
        (weight: 80.0, reps: 8),
      ]);
      expect(v, 60 * 12 + 80 * 10 + 80 * 8);
    });

    test('小数重量结果保留 1 位小数', () {
      final v = calcTotalVolume([(weight: 22.5, reps: 3)]);
      expect(v, 67.5);
    });
  });

  group('平均配速计算', () {
    test('28:32 / 5.2km = 329 秒/km', () {
      expect(
        paceSecondsPerKm(durationSeconds: 28 * 60 + 32, distanceKm: 5.2),
        329,
      );
    });

    test('距离为 0 时返回 0', () {
      expect(paceSecondsPerKm(durationSeconds: 100, distanceKm: 0), 0);
    });

    test('时长为 0 时返回 0', () {
      expect(paceSecondsPerKm(durationSeconds: 0, distanceKm: 5.0), 0);
    });
  });
}
