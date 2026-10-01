import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../database/workout_repository.dart';

/// 「最近训练」卡片：首页 / 记录页共用。
/// 展示最近一次力量训练的名称、相对时间、前几组预览，可[再练一次]。
class RecentWorkoutCard extends StatelessWidget {
  const RecentWorkoutCard({
    super.key,
    required this.detail,
    required this.onRepeat,
  });

  final SessionDetail detail;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final previewSets = <String>[];
    for (final de in detail.exercises) {
      // 动作名列表（最多 3 个）
      if (previewSets.length >= 3) break;
      if (de.sets.isNotEmpty) {
        final s = de.sets.first;
        previewSets.add(
          '${de.exercise.name}  ${formatWeight(s.weight)}kg × ${s.reps}',
        );
      } else {
        previewSets.add(de.exercise.name);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    detail.session.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${formatRelativeDay(detail.session.startTime)} · ${formatDurationCN(detail.session.durationSeconds)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (previewSets.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final line in previewSets)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () =>
                      context.push('/workout/${detail.session.id}'),
                  child: const Text('查看详情'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onRepeat,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('再练一次'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
