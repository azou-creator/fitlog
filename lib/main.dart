import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/providers/shared_prefs_provider.dart';
import 'database/app_database.dart';
import 'database/database_provider.dart';
import 'database/exercise_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase();

  try {
    await ExerciseRepository(db).ensureSeeded();
  } catch (e) {
    // 种子失败不阻塞启动，用户仍可使用自定义动作。
    debugPrint('内置动作库初始化失败: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const FitLogApp(),
    ),
  );
}
