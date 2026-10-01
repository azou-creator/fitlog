import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../database/app_database.dart' show Exercise;
import '../../database/workout_repository.dart';
import '../../shared/widgets/app_snack_bar.dart';
import 'active_workout.dart';
import 'widgets/exercise_card.dart';
import 'workout_draft.dart';

/// 力量训练编辑器（V1.1：训练进行中）。
///
/// 两种模式：
/// - 进行中（isInProgress）：自动落库、实时计时、右上角「完成」、返回时可选保留/放弃。
/// - 编辑已完成训练：手动「保存修改」。
class WorkoutEditorPage extends ConsumerStatefulWidget {
  const WorkoutEditorPage({super.key, this.seed, this.editSessionId});

  final Exercise? seed;
  final int? editSessionId;

  @override
  ConsumerState<WorkoutEditorPage> createState() => _WorkoutEditorPageState();
}

class _WorkoutEditorPageState extends ConsumerState<WorkoutEditorPage> {
  bool _ready = false;
  bool _saving = false;

  /// 各动作「上次」的参考数据：exerciseId → (重量, 次数) 列表。
  Map<int, List<(double, int)>> _lastPerformance = {};

  @override
  void initState() {
    super.initState();
    // provider 不能在构建期修改，统一延迟到帧末执行。
    Future(() => _init());
  }

  Future<void> _init() async {
    final controller = ref.read(activeWorkoutProvider.notifier);
    if (widget.editSessionId != null) {
      await controller.loadForEdit(widget.editSessionId!);
    } else {
      await controller.startNew(seed: widget.seed);
    }
    await _reloadRefs();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _reloadRefs() async {
    final draft = ref.read(activeWorkoutProvider);
    if (draft == null) return;
    try {
      _lastPerformance = await ref
          .read(workoutRepositoryProvider)
          .lastPerformanceMap(
            draft.sessionDbId,
            [for (final e in draft.exercises) e.exerciseId],
          );
    } catch (e) {
      _lastPerformance = {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(activeWorkoutProvider);
    if (!_ready || draft == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final live = draft.isInProgress;

    return PopScope(
      canPop: !live,
      onPopInvokedWithResult: (didPop, _) => _handleBack(didPop, live),
      child: Scaffold(
        appBar: AppBar(
          title: _buildTitle(context, draft),
          actions: [
            if (live)
              TextButton(
                onPressed: _saving ? null : _finish,
                child: const Text('完成',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildBody(context, draft, live)),
            if (!live) _buildSaveBar(context),
          ],
        ),
      ),
    );
  }

  // ============ 顶部 / 标题 ============

  Widget _buildTitle(BuildContext context, WorkoutDraft draft) {
    final scheme = Theme.of(context).colorScheme;
    final hasName = draft.name.trim().isNotEmpty;
    return GestureDetector(
      onTap: _rename,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              hasName ? draft.name.trim() : '未命名训练',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: hasName ? null : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.edit_rounded,
              size: 15, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, WorkoutDraft draft, bool live) {
    final controller = ref.read(activeWorkoutProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // 计时 / 日期行
        Row(
          children: [
            if (live)
              _LiveTimer(startTime: draft.startTime)
            else ...[
              Text(
                '${formatFullDate(draft.startTime)} · ${formatDurationCN(
                  DateTime.now().difference(draft.startTime).inSeconds,
                )}',
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('训练动作',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              '${draft.exercises.length} 个动作 · ${draft.validSetCount} 组',
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (draft.exercises.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '从动作库添加今天要练的动作',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: draft.exercises.length,
            onReorderItem: controller.reorderExercises,
            itemBuilder: (context, i) {
              final e = draft.exercises[i];
              return Container(
                key: ValueKey(e.id),
                child: ExerciseCard(
                  exercise: e,
                  dragHandle: ReorderableDragStartListener(
                    index: i,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  lastPerformance: _lastPerformance[e.exerciseId] ?? const [],
                  onAddSet: () => controller.addSet(e.id),
                  onRemoveExercise: () => controller.removeExercise(e.id),
                  onRemoveSet: (setId) => controller.removeSet(e.id, setId),
                  onWeightChanged: (setId, w) =>
                      controller.updateWeight(e.id, setId, w),
                  onRepsChanged: (setId, r) =>
                      controller.updateReps(e.id, setId, r),
                  onEditNote: () => _editExerciseNote(e.id, e.note),
                ),
              );
            },
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _pickExercises,
          icon: const Icon(Icons.add_rounded),
          label: const Text('添加动作'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: draft.note,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: '训练备注（可选）：今天状态、感受等',
            counterText: '',
          ),
          onChanged: controller.setNote,
        ),
      ],
    );
  }

  Widget _buildSaveBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _saving ? null : _saveEdits,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存修改',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  // ============ 操作 ============

  Future<void> _handleBack(bool didPop, bool live) async {
    if (didPop) return;
    final draft = ref.read(activeWorkoutProvider);
    if (draft == null || !live) {
      if (mounted) context.pop();
      return;
    }
    // 进行中：已自动保存。让用户选择继续保留或放弃。
    if (!draft.hasContent) {
      await ref.read(activeWorkoutProvider.notifier).discard();
      if (mounted) context.pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('训练尚未完成'),
        content: const Text('已自动保存。可以继续训练，也可以放弃并删除这次训练。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续训练'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃训练'),
          ),
        ],
      ),
    );
    if (discard == true) {
      await ref.read(activeWorkoutProvider.notifier).discard();
    }
    if (mounted) context.pop();
  }

  Future<void> _rename() async {
    final draft = ref.read(activeWorkoutProvider);
    if (draft == null) return;
    final ctrl = TextEditingController(text: draft.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('训练名称'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: '例如：胸 + 肩',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      ref.read(activeWorkoutProvider.notifier).setName(result);
    }
  }

  Future<void> _editExerciseNote(int draftExerciseId, String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('动作备注'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 100,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: '例如：器械调到 4 档、握距略宽',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      ref
          .read(activeWorkoutProvider.notifier)
          .setExerciseNote(draftExerciseId, result);
    }
  }

  Future<void> _pickExercises() async {
    final picked = await context.push<List<Exercise>>('/exercises');
    if (picked != null && picked.isNotEmpty) {
      ref.read(activeWorkoutProvider.notifier).addExercises(picked);
      await _reloadRefs();
      if (mounted) setState(() {});
    }
  }

  /// 完成训练（进行中模式，右上角）。
  Future<void> _finish() async {
    final draft = ref.read(activeWorkoutProvider);
    if (draft == null || _saving) return;
    if (!draft.hasValidSet) {
      showAppSnackBar(context, '至少记录一组训练后再完成。');
      return;
    }
    setState(() => _saving = true);
    try {
      final sessionId = await ref.read(activeWorkoutProvider.notifier).finish();
      ref.invalidate(sessionDetailProvider);
      if (mounted && sessionId != null) {
        context.pushReplacement('/workout/summary?id=$sessionId');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppSnackBar(context, '保存失败，请重试', isError: true);
      }
    }
  }

  /// 保存修改（编辑已完成训练模式）。
  Future<void> _saveEdits() async {
    final draft = ref.read(activeWorkoutProvider);
    if (draft == null || _saving) return;
    if (!draft.hasValidSet) {
      showAppSnackBar(context, '至少保留一组有效训练（次数 > 0）。');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(activeWorkoutProvider.notifier).saveEdits();
      ref.invalidate(sessionDetailProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppSnackBar(context, '保存失败，请重试', isError: true);
      }
    }
  }
}

/// 进行中训练的实时计时（当前时间 - 开始时间）。
class _LiveTimer extends StatefulWidget {
  const _LiveTimer({required this.startTime});

  final DateTime startTime;

  @override
  State<_LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<_LiveTimer> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startTime).inSeconds;
    return Text(
      formatClock(elapsed < 0 ? 0 : elapsed),
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
