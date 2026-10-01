import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/core/utils/formatters.dart';

void main() {
  group('跑步配速格式化', () {
    test("28:32 / 5.2km → 5'29\"/km", () {
      expect(formatPace(28 * 60 + 32, 5.2), "5'29\"/km");
    });

    test('非法输入 → --', () {
      expect(formatPace(0, 5.2), '--');
      expect(formatPace(100, 0), '--');
    });
  });

  group('时长格式化', () {
    test('时钟格式（无小时）', () {
      expect(formatClock(28 * 60 + 32), '28:32');
    });

    test('时钟格式（有小时）', () {
      expect(formatClock(3735), '1:02:15');
    });

    test('中文时长（无小时）', () {
      expect(formatDurationCN(58 * 60), '58分钟');
    });

    test('中文时长（有小时）', () {
      expect(formatDurationCN(3665), '1小时01分');
    });

    test('不足 1 分钟显示 <1分钟（不显示 0分钟）', () {
      expect(formatDurationCN(0), '<1分钟');
      expect(formatDurationCN(45), '<1分钟');
      expect(formatDurationCN(59), '<1分钟');
      expect(formatDurationCN(60), '1分钟');
    });
  });

  group('重量格式化', () {
    test('整数加千分位', () {
      expect(formatWeight(6820), '6,820');
      expect(formatWeight(80), '80');
    });

    test('小数去掉多余的 0', () {
      expect(formatWeight(22.5), '22.5');
      expect(formatWeight(60.0), '60');
    });
  });

  group('日期格式化', () {
    test('月日 / 星期', () {
      final d = DateTime(2026, 9, 30);
      expect(formatMonthDay(d), '9月30日');
    });

    test('星期映射', () {
      // 2026-01-01 是星期四
      expect(formatWeekday(DateTime(2026, 1, 1)), '星期四');
    });

    test('月份标题', () {
      expect(formatMonthTitle(DateTime(2026, 9, 30)), '2026年9月');
    });

    test('完整日期', () {
      expect(formatFullDate(DateTime(2026, 9, 30)), '2026/09/30');
    });
  });
}
