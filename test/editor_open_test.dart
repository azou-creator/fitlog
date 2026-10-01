import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/app/app.dart';
import 'package:fitlog/core/providers/shared_prefs_provider.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/database_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归测试：首页两个入口能正常打开对应页面，
/// 且不出现 "Tried to modify a provider while the widget tree was building"。
///
/// 注意：训练进行中页面有每秒刷新的计时器，不能用 pumpAndSettle，
/// 需要用带时长的 pump 推进帧。
void main() {
  Future<(ProviderScope, AppDatabase)> buildApp() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final scope = ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const FitLogApp(),
    );
    return (scope, db);
  }

  testWidgets('首页点击记录力量训练能正常进入进行中编辑器', (tester) async {
    final (scope, db) = await buildApp();
    await tester.pumpWidget(scope);
    await tester.pumpAndSettle();

    expect(find.text('今天练什么？'), findsOneWidget);

    await tester.tap(find.text('记录力量训练'));
    // 推进帧让 initState 里的 Future 完成草稿创建（计时器不会在短 pump 中触发）
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));

    // 编辑器页面出现：标题、完成按钮、添加动作入口
    // （标题「未命名训练」可能出现两次：首页的进行中横幅 + 编辑器标题）
    expect(find.text('未命名训练'), findsWidgets);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('训练动作'), findsOneWidget);
    expect(find.text('添加动作'), findsOneWidget);

    await db.close();
  });

  testWidgets('首页点击记录跑步能正常进入跑步录入', (tester) async {
    final (scope, db) = await buildApp();
    await tester.pumpWidget(scope);
    await tester.pumpAndSettle();

    await tester.tap(find.text('记录跑步'));
    await tester.pumpAndSettle();

    expect(find.text('距离'), findsWidgets);
    expect(find.text('平均配速'), findsOneWidget);
    // 保存按钮可能在测试视口之外
    expect(find.text('保存', skipOffstage: false), findsOneWidget);

    await db.close();
  });
}
