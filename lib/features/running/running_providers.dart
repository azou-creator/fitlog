import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart' show RunningRecord;
import '../../database/running_repository.dart';

/// 单条跑步记录（详情 / 编辑用）。不存在返回 null。
final runningRecordProvider = FutureProvider.family<RunningRecord?, int>((
  ref,
  id,
) async {
  try {
    return await ref.watch(runningRepositoryProvider).getById(id);
  } catch (e) {
    debugPrint('加载跑步记录失败: $e');
    return null;
  }
});
