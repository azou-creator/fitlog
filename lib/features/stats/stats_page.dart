import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import 'stats_providers.dart';
import 'widgets/charts.dart';

/// 数据统计页：周/月概览 + 30 天柱状图 + 跑步趋势 + 动作重量趋势。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(statsWeekProvider);
    final month = ref.watch(statsMonthProvider);
    final daily = ref.watch(dailyCount30Provider);
    final runTrend = ref.watch(runDistance30Provider);
    final scheme = Theme.of(context).colorScheme;

    // 是否有任意训练数据（决定整体空状态）
    final weekData = week.value;
    final hasAnyActivity =
        weekData != null &&
        (weekData.strengthCount > 0 || weekData.runCount > 0);

    return Scaffold(
      appBar: AppBar(title: const Text('数据统计')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!hasAnyActivity) ...[
            const SizedBox(height: 24),
            Icon(
              Icons.insights_rounded,
              size: 48,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '再记录几次训练，这里会慢慢生成趋势。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            const Text(
              '动作重量趋势',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const _ExerciseTrendSection(),
          ] else ...[
            _section(context, '本周'),
            const SizedBox(height: 8),
            week.when(
              loading: () => const _ChartPlaceholder(),
              error: (_, _) => const Text('加载失败'),
              data: (w) => Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      _stat(context, '${w.strengthCount}', '力量 · 次'),
                      _stat(context, '${w.setCount}', '力量 · 组'),
                      _stat(context, '${w.runCount}', '跑步 · 次'),
                      _stat(context, formatWeight(w.runDistanceKm), '跑步 · km'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _section(context, '本月'),
            const SizedBox(height: 8),
            month.when(
              loading: () => const _ChartPlaceholder(),
              error: (_, _) => const Text('加载失败'),
              data: (m) => Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      _stat(context, '${m.strengthCount}', '力量 · 次'),
                      _stat(context, '${m.runCount}', '跑步 · 次'),
                      _stat(context, formatWeight(m.runDistanceKm), '跑步 · km'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _section(context, '最近 30 天训练次数'),
            const SizedBox(height: 8),
            daily.when(
              loading: () => const _ChartPlaceholder(),
              error: (_, _) => const Text('加载失败'),
              data: (points) {
                final hasData = points.any((p) => p.value > 0);
                if (!hasData) return const SizedBox.shrink();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DailyBarChart(points: points),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            _section(context, '最近 30 天跑步距离 (km)'),
            const SizedBox(height: 8),
            runTrend.when(
              loading: () => const _ChartPlaceholder(),
              error: (_, _) => const Text('加载失败'),
              data: (points) {
                final hasData = points.any((p) => p.value > 0);
                if (!hasData) return const SizedBox.shrink();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SimpleLineChart(points: points),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            _section(context, '动作重量趋势'),
            const SizedBox(height: 8),
            const _ExerciseTrendSection(),
          ],
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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

class _ExerciseTrendSection extends ConsumerStatefulWidget {
  const _ExerciseTrendSection();

  @override
  ConsumerState<_ExerciseTrendSection> createState() =>
      _ExerciseTrendSectionState();
}

class _ExerciseTrendSectionState extends ConsumerState<_ExerciseTrendSection> {
  int? _selectedExerciseId;

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(trendExerciseListProvider);
    final scheme = Theme.of(context).colorScheme;

    return exercisesAsync.when(
      loading: () => const _ChartPlaceholder(),
      error: (_, _) => const Text('加载失败'),
      data: (exercises) {
        if (exercises.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '暂无动作',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }
        final selectedId =
            _selectedExerciseId ??
            (exercises.any((e) => e.name == '杠铃卧推')
                ? exercises.firstWhere((e) => e.name == '杠铃卧推').id
                : exercises.first.id);
        final selectedName = exercises
            .firstWhere(
              (e) => e.id == selectedId,
              orElse: () => exercises.first,
            )
            .name;
        final trend = ref.watch(exerciseTrendProvider(selectedId));

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '选择动作'),
                  items: [
                    for (final e in exercises)
                      DropdownMenuItem(value: e.id, child: Text(e.name)),
                  ],
                  onChanged: (v) => setState(() => _selectedExerciseId = v),
                ),
                const SizedBox(height: 8),
                trend.when(
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const SizedBox(
                    height: 60,
                    child: Center(child: Text('加载失败')),
                  ),
                  data: (points) {
                    if (points.length < 2) {
                      return SizedBox(
                        height: 120,
                        child: Center(
                          child: Text(
                            '至少记录 2 次「$selectedName」后展示趋势',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }
                    return SimpleLineChart(points: points);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChartPlaceholder extends StatelessWidget {
  const _ChartPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 100,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
