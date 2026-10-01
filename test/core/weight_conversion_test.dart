import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/core/utils/weight_conversion.dart';
import 'package:fitlog/features/tools/weight_converter_page.dart';

void main() {
  group('磅 → 公斤（精确系数 0.45359237）', () {
    test('1 lb', () {
      expect(poundsToKg(1), closeTo(0.45359237, 1e-9));
    });

    test('10 lb', () {
      expect(poundsToKg(10), closeTo(4.5359237, 1e-9));
    });

    test('50 lb', () {
      expect(poundsToKg(50), closeTo(22.6796185, 1e-9));
    });

    test('70 lb', () {
      expect(poundsToKg(70), closeTo(31.7514659, 1e-9));
    });

    test('100 lb', () {
      expect(poundsToKg(100), closeTo(45.359237, 1e-9));
    });
  });

  group('公斤 → 磅（精确系数 2.2046226218）', () {
    test('30 kg ≈ 66.1387 lb', () {
      expect(kgToPounds(30), closeTo(66.1387, 0.0001));
    });

    test('1 kg', () {
      expect(kgToPounds(1), closeTo(2.2046226218, 1e-9));
    });

    test('往返换算误差在可接受范围', () {
      // 70 lb → kg → lb 应回到约 70
      final kg = poundsToKg(70);
      expect(kgToPounds(kg), closeTo(70, 1e-6));
    });
  });

  group('训练记录参考（四舍五入到 0.1 kg）', () {
    test('31.7514659 → 31.8', () {
      expect(roundToTrainingKg(31.7514659), closeTo(31.8, 1e-9));
    });

    test('31.75 → 31.8（.5 进位）', () {
      expect(roundToTrainingKg(31.75), closeTo(31.8, 1e-9));
    });

    test('10.04 → 10.0', () {
      expect(roundToTrainingKg(10.04), closeTo(10.0, 1e-9));
    });

    test('22.6796185 → 22.7', () {
      expect(roundToTrainingKg(22.6796185), closeTo(22.7, 1e-9));
    });
  });

  group('页面交互', () {
    testWidgets('输入 70 实时显示 31.75 kg 与训练参考 ≈ 31.8 kg', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: WeightConverterPage()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '70');
      await tester.pump();

      expect(find.text('31.75'), findsOneWidget);
      expect(find.text('≈ 31.8 kg'), findsOneWidget);
      expect(find.text('1 lb = 0.453592 kg'), findsOneWidget);
      expect(find.text('常用磅数'), findsOneWidget);
    });

    testWidgets('点击交换后变为 kg → lb 方向', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: WeightConverterPage()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '70');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.swap_vert_rounded));
      await tester.pump();

      // 方向已切换：系数提示变为 kg → lb，常用磅数隐藏
      expect(find.text('1 kg = 2.204623 lb'), findsOneWidget);
      expect(find.text('常用磅数'), findsNothing);
      // 交换后输入为上一步的展示结果 31.75，换算回约 70 lb
      expect(find.text('70'), findsWidgets);
    });
  });
}
