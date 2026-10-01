import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database_provider.dart';

/// 任意数据表发生变化时发出事件（初始时也发一次）。
/// 需要随数据刷新的查询型 Provider watch 它即可。
final dataChangeProvider = StreamProvider<void>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final controller = StreamController<void>();

  Future(() => controller.add(null));
  final sub = db.tableUpdates().listen((_) => controller.add(null));
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});
