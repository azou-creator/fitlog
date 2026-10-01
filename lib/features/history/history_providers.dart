import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/database_provider.dart';
import '../../database/running_repository.dart';

/// 历史列表条目：力量训练或跑步二选一。
class HistoryItem {
  const HistoryItem._({
    required this.date,
    this.session,
    this.setsCount = 0,
    this.run,
  });

  final DateTime date;
  final WorkoutSession? session;
  final int setsCount;
  final RunningRecord? run;

  bool get isWorkout => session != null;
}

/// 每次力量训练对应的组数统计。
class SessionWithCount {
  SessionWithCount({required this.session, required this.setCount});

  final WorkoutSession session;
  final int setCount;
}

/// 合并力量训练 + 跑步的历史流，按时间倒序。
/// 通过 db.tableUpdates 在任意数据变化时自动重查（个人数据量小，直接全量刷新）。
final historyProvider = StreamProvider<List<HistoryItem>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final runningRepo = ref.watch(runningRepositoryProvider);

  Future<List<HistoryItem>> load() async {
    try {
      final sessions = await _sessionsWithCounts(db);
      final runs = await runningRepo.getAll();
      final items = <HistoryItem>[
        for (final s in sessions)
          HistoryItem._(
            date: s.session.startTime,
            session: s.session,
            setsCount: s.setCount,
          ),
        for (final r in runs) HistoryItem._(date: r.date, run: r),
      ]..sort((a, b) => b.date.compareTo(a.date));
      return items;
    } catch (e) {
      debugPrint('加载历史失败: $e');
      return [];
    }
  }

  late StreamSubscription<Set<TableUpdate>> sub;
  final controller = StreamController<List<HistoryItem>>();

  Future<void> push() async => controller.add(await load());

  // 立即推一次初始数据，之后监听任何数据表变化
  Future(() => push());
  sub = db.tableUpdates().listen((_) => push());
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

Future<List<SessionWithCount>> _sessionsWithCounts(AppDatabase db) async {
  final sessions = await (db.select(
    db.workoutSessions,
  )..orderBy([(s) => OrderingTerm.desc(s.startTime)])).get();
  if (sessions.isEmpty) return [];

  final countExp = countAll();
  final query = db.selectOnly(db.workoutExercises)
    ..addColumns([db.workoutExercises.workoutSessionId, countExp])
    ..join([
      leftOuterJoin(
        db.workoutSets,
        db.workoutSets.workoutExerciseId.equalsExp(db.workoutExercises.id),
      ),
    ])
    ..groupBy([db.workoutExercises.workoutSessionId]);

  final counts = <int, int>{};
  for (final row in await query.get()) {
    final sessionId = row.read(db.workoutExercises.workoutSessionId);
    if (sessionId != null) {
      counts[sessionId] = row.read(countExp) ?? 0;
    }
  }
  return [
    for (final s in sessions)
      SessionWithCount(session: s, setCount: counts[s.id] ?? 0),
  ];
}
