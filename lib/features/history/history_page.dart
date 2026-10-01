import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import 'history_providers.dart';

/// 历史页：按月份分组，力量训练 / 跑步混合时间线。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('历史')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const EmptyState(
          icon: Icons.error_outline_rounded,
          title: '加载失败',
          subtitle: '请下拉重试或重启应用',
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.fitness_center_rounded,
              title: '还没有训练记录',
              subtitle: '完成第一次训练后，会显示在这里',
              actionLabel: '开始第一次训练',
              onAction: () => context.push('/workout/new'),
            );
          }

          // 已按时间倒序，按月分组保持顺序
          final rows = <Widget>[];
          String? currentMonth;
          for (final item in items) {
            final month = formatMonthTitle(item.date);
            if (month != currentMonth) {
              currentMonth = month;
              rows.add(Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                child: Text(
                  month,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ));
            }
            rows.add(_HistoryTile(item: item));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: rows.length,
            itemBuilder: (_, i) => rows[i],
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWorkout = item.isWorkout;

    final title = isWorkout ? item.session!.name : '跑步';
    final subtitle = isWorkout
        ? '${formatDurationCN(item.session!.durationSeconds)} · ${item.setsCount} 组'
        : '${formatWeight(item.run!.distanceKm)} km · ${formatClock(item.run!.durationSeconds)} · ${formatPace(item.run!.durationSeconds, item.run!.distanceKm)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          onTap: () => context.push(isWorkout
              ? '/workout/${item.session!.id}'
              : '/running/${item.run!.id}'),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isWorkout
                  ? scheme.primaryContainer
                  : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isWorkout
                  ? Icons.fitness_center_rounded
                  : Icons.directions_run_rounded,
              size: 22,
              color: isWorkout
                  ? scheme.onPrimaryContainer
                  : scheme.onSecondaryContainer,
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          trailing: Text(
            formatMonthDay(item.date),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
