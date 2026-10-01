import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../database/workout_repository.dart' show inProgressSessionProvider;
import '../../shared/widgets/big_action_button.dart';
import '../../shared/widgets/recent_workout_card.dart';
import '../workout/active_workout.dart';
import 'home_providers.dart';

/// 首页 = 今天 + 进行中提醒 + 最近训练 + 本周概览。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final inProgress = ref.watch(inProgressSessionProvider);
    final recentAsync = ref.watch(recentWorkoutProvider);
    final weekAsync = ref.watch(weekOverviewProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('训练日志')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            '${formatMonthDay(now)} · ${formatWeekday(now)}',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          const Text(
            '今天练什么？',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          inProgress.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (session) => session == null
                ? const SizedBox.shrink()
                : _InProgressBanner(
                    sessionId: session.id,
                    name: session.name,
                    startTime: session.startTime,
                  ),
          ),
          BigActionButton(
            icon: Icons.fitness_center_rounded,
            title: '记录力量训练',
            subtitle: '动作 · 组数 · 重量',
            onTap: () => context.push('/workout/new'),
          ),
          const SizedBox(height: 12),
          BigActionButton(
            icon: Icons.directions_run_rounded,
            title: '记录跑步',
            subtitle: '距离 · 用时 · 配速',
            color: scheme.secondaryContainer,
            onTap: () => context.push('/running/new'),
          ),
          const SizedBox(height: 24),
          recentAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (detail) => detail == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '最近训练',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      RecentWorkoutCard(
                        detail: detail,
                        onRepeat: () =>
                            _repeat(context, ref, detail.session.id),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          const Text(
            '本周',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          weekAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (week) => Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    _weekStat(context, '${week.strengthCount}', '力量训练 · 次'),
                    _weekStat(context, '${week.runCount}', '跑步 · 次'),
                    _weekStat(
                      context,
                      formatWeight(week.runDistanceKm),
                      '跑步距离 · km',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _repeat(
    BuildContext context,
    WidgetRef ref,
    int sessionId,
  ) async {
    await ref.read(activeWorkoutProvider.notifier).startFromSession(sessionId);
    if (context.mounted) context.push('/workout/new');
  }

  Widget _weekStat(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 「正在进行」横幅：检测到未完成训练时显示，点击继续。
class _InProgressBanner extends StatelessWidget {
  const _InProgressBanner({
    required this.sessionId,
    required this.name,
    required this.startTime,
  });

  final int sessionId;
  final String name;
  final DateTime startTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final elapsed = DateTime.now().difference(startTime).inMinutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: scheme.primaryContainer,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: Icon(
            Icons.play_circle_fill_rounded,
            size: 32,
            color: scheme.onPrimaryContainer,
          ),
          title: Text(
            name.trim().isEmpty ? '未命名训练' : name.trim(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onPrimaryContainer,
            ),
          ),
          subtitle: Text(
            '正在进行 · 已训练 $elapsed 分钟',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
            ),
          ),
          trailing: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.onPrimaryContainer,
              foregroundColor: scheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 36),
            ),
            onPressed: () => context.push('/workout/$sessionId/edit'),
            child: const Text('继续训练'),
          ),
        ),
      ),
    );
  }
}
