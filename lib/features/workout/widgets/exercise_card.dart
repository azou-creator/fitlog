import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../workout_draft.dart';
import 'set_row.dart';

/// 一次训练里的单个动作模块：动作名 + 上次参考 + 紧凑组列表 + 添加一组。
/// 删除组：左滑；动作操作：右上角 ⋯ 菜单（备注 / 删除动作）。
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.dragHandle,
    this.lastPerformance = const [],
    required this.onAddSet,
    required this.onRemoveExercise,
    required this.onRemoveSet,
    required this.onWeightChanged,
    required this.onRepsChanged,
    required this.onEditNote,
  });

  final DraftExercise exercise;

  /// 拖动排序手柄（由 ReorderableDragStartListener 包装）。
  final Widget dragHandle;

  /// 上一次该动作的 (重量, 次数) 列表，仅作参考展示。
  final List<(double, int)> lastPerformance;

  final VoidCallback onAddSet;
  final VoidCallback onRemoveExercise;
  final VoidCallback onEditNote;
  final void Function(int setId) onRemoveSet;
  final void Function(int setId, double weight) onWeightChanged;
  final void Function(int setId, int? reps) onRepsChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weakStyle = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                dragHandle,
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(exercise.muscleGroup, style: weakStyle),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '动作操作',
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (value) {
                    if (value == 'note') onEditNote();
                    if (value == 'delete') onRemoveExercise();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'note', child: Text('添加备注')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '删除动作',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (exercise.note.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(exercise.note, style: weakStyle),
              ),
            ],
            if (lastPerformance.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  '上次  ${[for (final (w, r) in lastPerformance) '${formatWeight(w)}×$r'].join('  ·  ')}',
                  style: weakStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 6),
            if (exercise.sets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('点击下方「添加一组」开始记录', style: weakStyle),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < exercise.sets.length; i++)
                    Dismissible(
                      key: ValueKey('set-${exercise.sets[i].id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      onDismissed: (_) => onRemoveSet(exercise.sets[i].id),
                      child: SetRow(
                        key: ValueKey(exercise.sets[i].id),
                        index: i,
                        set: exercise.sets[i],
                        onWeightChanged: (w) =>
                            onWeightChanged(exercise.sets[i].id, w),
                        onRepsChanged: (r) =>
                            onRepsChanged(exercise.sets[i].id, r),
                      ),
                    ),
                ],
              ),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onAddSet,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加一组'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
