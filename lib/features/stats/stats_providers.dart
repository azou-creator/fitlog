import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/data_change_provider.dart';
import '../../database/app_database.dart' show Exercise;
import '../../database/database_provider.dart';
import '../../database/exercise_repository.dart';
import '../../database/running_repository.dart';
import '../../database/workout_repository.dart';

/// 一个时间段内的概览数据。
class PeriodOverview {
  const PeriodOverview({
    required this.strengthCount,
    required this.setCount,
    required this.runCount,
    required this.runDistanceKm,
  });

  final int strengthCount;
  final int setCount;
  final int runCount;
  final double runDistanceKm;
}

/// 本周概览（周一为一周开始，含总组数）。
final statsWeekProvider = FutureProvider<PeriodOverview>((ref) async {
  ref.watch(dataChangeProvider);
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));

  final workoutRepo = ref.watch(workoutRepositoryProvider);
  final runningRepo = ref.watch(runningRepositoryProvider);

  final sessions = await workoutRepo.getSessionsBetween(weekStart, now);
  final runs = await runningRepo.getBetween(weekStart, now);
  final setCount = await workoutRepo.countSetsBetween(weekStart, now);

  return PeriodOverview(
    strengthCount: sessions.length,
    setCount: setCount,
    runCount: runs.length,
    runDistanceKm: runs.fold<double>(0, (s, r) => s + r.distanceKm),
  );
});

/// 本月概览。
final statsMonthProvider = FutureProvider<PeriodOverview>((ref) async {
  ref.watch(dataChangeProvider);
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);

  final workoutRepo = ref.watch(workoutRepositoryProvider);
  final runningRepo = ref.watch(runningRepositoryProvider);

  final sessions = await workoutRepo.getSessionsBetween(monthStart, now);
  final runs = await runningRepo.getBetween(monthStart, now);

  return PeriodOverview(
    strengthCount: sessions.length,
    setCount: 0,
    runCount: runs.length,
    runDistanceKm: runs.fold<double>(0, (s, r) => s + r.distanceKm),
  );
});

/// 一天的数据点。
typedef DayPoint = ({DateTime day, double value});

/// 最近 30 天每天的训练次数（力量 + 跑步）。
final dailyCount30Provider = FutureProvider<List<DayPoint>>((ref) async {
  ref.watch(dataChangeProvider);
  final db = ref.watch(appDatabaseProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(const Duration(days: 29));

  try {
    final sessions = await db.select(db.workoutSessions).get();
    final runs = await ref.watch(runningRepositoryProvider).getAll();

    final counts = <DateTime, int>{};
    DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
    for (final s in sessions) {
      final k = dayOf(s.startTime);
      if (!k.isBefore(start)) counts[k] = (counts[k] ?? 0) + 1;
    }
    for (final r in runs) {
      final k = dayOf(r.date);
      if (!k.isBefore(start)) counts[k] = (counts[k] ?? 0) + 1;
    }

    return [
      for (var i = 0; i < 30; i++)
        (
          day: start.add(Duration(days: i)),
          value: (counts[start.add(Duration(days: i))] ?? 0).toDouble(),
        ),
    ];
  } catch (e) {
    debugPrint('加载30天统计失败: $e');
    return [];
  }
});

/// 最近 30 天每天的跑步距离（km）。
final runDistance30Provider = FutureProvider<List<DayPoint>>((ref) async {
  ref.watch(dataChangeProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(const Duration(days: 29));

  try {
    final runs = await ref.watch(runningRepositoryProvider).getBetween(
          start,
          now,
        );
    final byDay = <DateTime, double>{};
    for (final r in runs) {
      final k = DateTime(r.date.year, r.date.month, r.date.day);
      byDay[k] = (byDay[k] ?? 0) + r.distanceKm;
    }
    return [
      for (var i = 0; i < 30; i++)
        (
          day: start.add(Duration(days: i)),
          value: byDay[start.add(Duration(days: i))] ?? 0,
        ),
    ];
  } catch (e) {
    debugPrint('加载跑步趋势失败: $e');
    return [];
  }
});

/// 某个动作的重量趋势：每次训练当天的最大重量。
final exerciseTrendProvider =
    FutureProvider.family<List<DayPoint>, int>((ref, exerciseId) async {
  ref.watch(dataChangeProvider);
  final db = ref.watch(appDatabaseProvider);

  try {
    final query = db.select(db.workoutExercises).join([
      innerJoin(db.workoutSessions,
          db.workoutSessions.id.equalsExp(db.workoutExercises.workoutSessionId)),
    ])
      ..where(db.workoutExercises.exerciseId.equals(exerciseId))
      ..orderBy([OrderingTerm.asc(db.workoutSessions.startTime)]);

    final rows = await query.get();
    final points = <DayPoint>[];
    for (final row in rows) {
      final we = row.readTable(db.workoutExercises);
      final session = row.readTable(db.workoutSessions);
      final sets = await (db.select(db.workoutSets)
            ..where((s) => s.workoutExerciseId.equals(we.id)))
          .get();
      final valid = sets.where((s) => s.reps > 0).toList();
      if (valid.isEmpty) continue;
      final maxWeight = valid.map((s) => s.weight).reduce(
            (a, b) => a > b ? a : b,
          );
      final day = DateTime(
          session.startTime.year, session.startTime.month, session.startTime.day);
      points.add((day: day, value: maxWeight));
    }
    // 同一天同动作只保留最大重量
    final dedup = <DateTime, double>{};
    for (final p in points) {
      dedup[p.day] = p.value > (dedup[p.day] ?? 0) ? p.value : (dedup[p.day] ?? 0);
    }
    return [
      for (final e in dedup.entries) (day: e.key, value: e.value),
    ];
  } catch (e) {
    debugPrint('加载动作趋势失败: $e');
    return [];
  }
});

/// 动作趋势选择用的动作列表。
final trendExerciseListProvider = FutureProvider<List<Exercise>>((ref) async {
  ref.watch(dataChangeProvider);
  return ref.watch(exerciseRepositoryProvider).getAll();
});
