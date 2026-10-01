import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../database/workout_repository.dart';
import '../../shared/widgets/app_snack_bar.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/empty_state.dart';

/// 力量训练详情：只读展示全部动作与组，可编辑 / 删除。
class WorkoutDetailPage extends ConsumerWidget {
  const WorkoutDetailPage({super.key, required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(sessionDetailProvider(sessionId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练详情'),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/workout/$sessionId/edit'),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            const EmptyState(icon: Icons.error_outline_rounded, title: '加载失败'),
        data: (detail) {
          if (detail == null) {
            return const EmptyState(
              icon: Icons.fitness_center_rounded,
              title: '记录不存在',
              subtitle: '可能已被删除',
            );
          }
          final s = detail.session;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${formatFullDate(s.startTime)} · ${formatDurationCN(s.durationSeconds)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (s.note != null && s.note!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          s.note!,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _stat(context, '${detail.exerciseCount}', '动作'),
                          _stat(context, '${detail.totalSets}', '组数'),
                          _stat(
                            context,
                            formatWeight(detail.totalVolume),
                            '总容量 kg',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final de in detail.exercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  de.exercise.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                de.exercise.muscleGroup,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (de.sets.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '未记录训练组',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            for (var i = 0; i < de.sets.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 26,
                                      child: Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      formatWeight(de.sets[i].weight),
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      ' kg × ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      '${de.sets[i].reps}',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
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

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除这次训练？',
      content: '删除后无法恢复',
    );
    if (!confirmed) return;
    try {
      await ref.read(workoutRepositoryProvider).deleteSession(sessionId);
      ref.invalidate(sessionDetailProvider);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, '删除失败，请重试', isError: true);
      }
    }
  }
}
