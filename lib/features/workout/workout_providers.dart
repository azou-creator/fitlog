import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/data_change_provider.dart';
import '../../database/app_database.dart' show Exercise;
import '../../database/exercise_repository.dart';

/// 全部动作（动作库页 / 选择页共用）。
final exercisesStreamProvider = StreamProvider<List<Exercise>>((ref) {
  return ref.watch(exerciseRepositoryProvider).watchAll();
});

/// 最近使用过的动作（记录页快速开始），数据变化时自动刷新。
final recentExercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  ref.watch(dataChangeProvider);
  try {
    return await ref.watch(exerciseRepositoryProvider).getRecentUsed();
  } catch (e) {
    debugPrint('加载最近动作失败: $e');
    return [];
  }
});
