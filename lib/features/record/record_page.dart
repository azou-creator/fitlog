import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../database/app_database.dart' show Exercise;
import '../../shared/widgets/big_action_button.dart';
import '../../shared/widgets/recent_workout_card.dart';
import '../home/home_providers.dart' show recentWorkoutProvider;
import '../workout/active_workout.dart';
import '../workout/workout_providers.dart';

/// 记录页 = 快速开始 + 最近使用的动作 + 最近训练（与首页职责区分）。
class RecordPage extends ConsumerWidget {
  const RecordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentExercisesProvider);
    final latestAsync = ref.watch(recentWorkoutProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('记录')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          BigActionButton(
            icon: Icons.fitness_center_rounded,
            title: '力量训练',
            subtitle: '添加动作与训练组',
            onTap: () => context.push('/workout/new'),
          ),
          const SizedBox(height: 12),
          BigActionButton(
            icon: Icons.directions_run_rounded,
            title: '跑步',
            subtitle: '手动记录距离与用时',
            color: scheme.secondaryContainer,
            onTap: () => context.push('/running/new'),
          ),
          const SizedBox(height: 24),
          latestAsync.when(
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
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      RecentWorkoutCard(
                        detail: detail,
                        onRepeat: () => _repeat(context, ref, detail.session.id),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
          recentAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (exercises) {
              if (exercises.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '最近使用的动作',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击直接开始，动作已加入训练',
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in exercises) _ExerciseChip(exercise: e),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _repeat(BuildContext context, WidgetRef ref, int sessionId) async {
    await ref.read(activeWorkoutProvider.notifier).startFromSession(sessionId);
    if (context.mounted) context.push('/workout/new');
  }
}

class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      side: BorderSide.none,
      label: Text(exercise.name),
      labelStyle: const TextStyle(fontSize: 14),
      onPressed: () => context.push('/workout/new', extra: exercise),
    );
  }
}
