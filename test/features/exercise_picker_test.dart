import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/core/providers/shared_prefs_provider.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/database_provider.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/features/workout/exercise_picker_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 动作选择页：整行点击即可多选，底部按钮实时显示数量。
void main() {
  testWidgets('点击两行动作后按钮显示「添加 2 个动作」', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await ExerciseRepository(db).ensureSeeded();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: ExercisePickerPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 整行可点（不是只有 Checkbox）
    await tester.tap(find.text('杠铃卧推'));
    await tester.pump();
    await tester.tap(find.text('哑铃卧推'));
    await tester.pump();

    expect(find.text('添加 2 个动作'), findsOneWidget);

    // 再次点击取消选择
    await tester.tap(find.text('杠铃卧推'));
    await tester.pump();
    expect(find.text('添加 1 个动作'), findsOneWidget);

    await db.close();
  });
}
