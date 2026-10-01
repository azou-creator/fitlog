import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../database/running_repository.dart';
import '../../shared/widgets/app_snack_bar.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/empty_state.dart';
import 'running_providers.dart';

/// 跑步详情。
class RunningDetailPage extends ConsumerWidget {
  const RunningDetailPage({super.key, required this.recordId});

  final int recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordAsync = ref.watch(runningRecordProvider(recordId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('跑步详情'),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/running/$recordId/edit'),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: recordAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: '加载失败',
        ),
        data: (record) {
          if (record == null) {
            return const EmptyState(
              icon: Icons.directions_run_rounded,
              title: '记录不存在',
              subtitle: '可能已被删除',
            );
          }
          final pace =
              formatPace(record.durationSeconds, record.distanceKm);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '跑步',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            formatFullDate(record.date),
                            style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _stat(context, '距离',
                              '${formatWeight(record.distanceKm)} km'),
                          _stat(context, '用时',
                              formatClock(record.durationSeconds)),
                        ],
                      ),
                      const Divider(height: 28),
                      Row(
                        children: [
                          _stat(context, '平均配速', pace),
                          _stat(
                            context,
                            '平均心率',
                            record.averageHeartRate != null
                                ? '${record.averageHeartRate} bpm'
                                : '--',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (record.note != null && record.note!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '备注',
                          style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          record.note!,
                          style: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除这条跑步记录？',
      content: '删除后无法恢复',
    );
    if (!confirmed) return;
    try {
      await ref.read(runningRepositoryProvider).delete(recordId);
      ref.invalidate(runningRecordProvider);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, '删除失败，请重试', isError: true);
      }
    }
  }
}
