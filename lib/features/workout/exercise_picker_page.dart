import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/muscle_groups.dart';
import '../../database/app_database.dart' show Exercise;
import '../../database/exercise_repository.dart';
import '../../shared/widgets/app_snack_bar.dart';
import '../../shared/widgets/empty_state.dart';
import 'widgets/custom_exercise_dialog.dart';
import 'workout_providers.dart';

/// 动作选择页：肌群筛选 chips + 搜索 + 整行多选 + 底部固定「添加 N 个动作」。
/// 右上角 + 创建自定义动作。pop 返回选中的 Exercise 列表。
class ExercisePickerPage extends ConsumerStatefulWidget {
  const ExercisePickerPage({super.key});

  @override
  ConsumerState<ExercisePickerPage> createState() => _ExercisePickerPageState();
}

class _ExercisePickerPageState extends ConsumerState<ExercisePickerPage> {
  static const _filterAll = '全部';
  static const _filterRecent = '最近';

  final Set<int> _selectedIds = {};
  String _query = '';
  late String _filter = _filterAll; // 在 initState 中按数据情况调整

  @override
  void initState() {
    super.initState();
    Future(() {
      final recent = ref.read(recentExercisesProvider).value ?? [];
      if (recent.isNotEmpty && mounted) {
        setState(() => _filter = _filterRecent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(exercisesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择动作'),
        actions: [
          IconButton(
            tooltip: '创建自定义动作',
            icon: const Icon(Icons.add_rounded),
            onPressed: _createCustom,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索动作',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (t) => setState(() => _query = t.trim()),
            ),
          ),
          // 肌群筛选 chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _chip(context, _filterAll),
                _chip(context, _filterRecent),
                for (final g in muscleGroups) _chip(context, g),
              ],
            ),
          ),
          Expanded(
            child: allAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const EmptyState(
                icon: Icons.error_outline_rounded,
                title: '加载失败',
                subtitle: '请返回后重试',
              ),
              data: (list) => _buildList(context, list),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _selectedIds.isEmpty ? null : () => _confirm(allAsync),
              child: Text(
                _selectedIds.isEmpty ? '添加动作' : '添加 ${_selectedIds.length} 个动作',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _filter = label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Exercise> all) {
    final scheme = Theme.of(context).colorScheme;

    List<Exercise> filtered;
    String? groupFilter;
    if (_filter != _filterAll && _filter != _filterRecent) {
      groupFilter = _filter;
    }

    if (_filter == _filterRecent) {
      final recent = ref.read(recentExercisesProvider).value ?? [];
      final recentIds = recent.map((e) => e.id).toSet();
      filtered = [
        for (final e in all)
          if (recentIds.contains(e.id)) e,
      ];
    } else {
      filtered = groupFilter == null
          ? all
          : all.where((e) => e.muscleGroup == groupFilter).toList();
    }
    if (_query.isNotEmpty) {
      filtered = [
        for (final e in filtered)
          if (e.name.contains(_query)) e,
      ];
    }

    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.fitness_center_rounded,
        title: '动作库是空的',
        subtitle: '点击右上角 + 创建你的第一个自定义动作',
      );
    }
    if (filtered.isEmpty) {
      if (_filter == _filterRecent) {
        return EmptyState(
          icon: Icons.history_rounded,
          title: '还没有最近使用的动作',
          subtitle: '完成一次训练后会出现在这里',
          actionLabel: '查看全部动作',
          onAction: () => setState(() => _filter = _filterAll),
        );
      }
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: '没有找到匹配的动作',
      );
    }

    // 按「最近 → 肌群固定顺序」分组展示
    final grouped = <String, List<Exercise>>{};
    for (final e in filtered) {
      (grouped[e.muscleGroup] ??= []).add(e);
    }
    final orderedGroups = _filter == _filterRecent
        ? grouped.keys.toList()
        : [
            ...muscleGroups.where(grouped.containsKey),
            ...grouped.keys.where((g) => !muscleGroups.contains(g)),
          ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      itemCount: orderedGroups.fold<int>(
        0,
        (n, g) => n + 1 + grouped[g]!.length,
      ),
      itemBuilder: (context, index) {
        var cursor = index;
        for (final group in orderedGroups) {
          final items = grouped[group]!;
          if (cursor == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                group,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            );
          }
          cursor -= 1;
          if (cursor < items.length) {
            final e = items[cursor];
            final selected = _selectedIds.contains(e.id);
            return CheckboxListTile(
              value: selected,
              controlAffinity: ListTileControlAffinity.trailing,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 0,
              ),
              title: Text(e.name),
              subtitle: e.isCustom
                  ? const Text('自定义', style: TextStyle(fontSize: 12))
                  : null,
              onChanged: (_) => setState(() {
                selected ? _selectedIds.remove(e.id) : _selectedIds.add(e.id);
              }),
            );
          }
          cursor -= items.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _confirm(AsyncValue<List<Exercise>> allAsync) {
    final all = allAsync.value ?? [];
    final picked = [
      for (final e in all)
        if (_selectedIds.contains(e.id)) e,
    ];
    Navigator.of(context).pop(picked);
  }

  Future<void> _createCustom() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const CustomExerciseDialog(),
    );
    if (result == null) return;
    final (name, group) = result;
    try {
      final id = await ref
          .read(exerciseRepositoryProvider)
          .createCustom(name: name, muscleGroup: group);
      if (!mounted) return;
      setState(() => _selectedIds.add(id));
    } catch (e) {
      if (mounted) showAppSnackBar(context, '创建失败，请重试', isError: true);
    }
  }
}
