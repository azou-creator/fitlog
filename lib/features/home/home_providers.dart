import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/data_change_provider.dart';
import '../../database/running_repository.dart';
import '../../database/workout_repository.dart';

/// 最近一次力量训练详情（首页「最近训练」）。没有训练时为 null。
final recentWorkoutProvider = FutureProvider((ref) async {
  ref.watch(dataChangeProvider);
  try {
    return await ref.watch(workoutRepositoryProvider).getLatestSessionDetail();
  } catch (e) {
    debugPrint('加载最近训练失败: $e');
    return null;
  }
});

/// 本周概览（周一为一周开始）。
class WeekOverview {
  const WeekOverview({
    required this.strengthCount,
    required this.runCount,
    required this.runDistanceKm,
  });

  final int strengthCount;
  final int runCount;
  final double runDistanceKm;
}

final weekOverviewProvider = FutureProvider<WeekOverview>((ref) async {
  ref.watch(dataChangeProvider);
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  // 周一为一周开始
  final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));

  final sessions = await ref
      .watch(workoutRepositoryProvider)
      .getSessionsBetween(weekStart, now);
  final runs = await ref
      .watch(runningRepositoryProvider)
      .getBetween(weekStart, now);

  return WeekOverview(
    strengthCount: sessions.length,
    runCount: runs.length,
    runDistanceKm: runs.fold<double>(0, (sum, r) => sum + r.distanceKm),
  );
});
