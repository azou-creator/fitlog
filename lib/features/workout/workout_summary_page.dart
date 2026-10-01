import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../database/workout_repository.dart' show sessionDetailProvider;
import '../../shared/widgets/empty_state.dart';

/// 完成训练后的总结页。
class WorkoutSummaryPage extends ConsumerWidget {
  const WorkoutSummaryPage({super.key, required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(sessionDetailProvider(sessionId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练完成'),
        automaticallyImplyLeading: false,
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: '加载失败',
        ),
        data: (detail) {
          if (detail == null) {
            return const EmptyState(
              icon: Icons.error_outline_rounded,
              title: '记录不存在',
            );
          }
          final s = detail.session;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 8),
              Icon(Icons.check_circle_rounded,
                  size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                s.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatFullDate(s.startTime)} · ${formatDurationCN(s.durationSeconds)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _row(context, '动作', '${detail.exerciseCount} 个'),
                      const Divider(indent: 60),
                      _row(context, '训练组', '${detail.totalSets} 组'),
                      const Divider(indent: 60),
                      _row(context, '训练容量',
                          '${formatWeight(detail.totalVolume)} kg'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('完成',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
