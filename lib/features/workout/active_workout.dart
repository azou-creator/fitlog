import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart' show Exercise;
import '../../database/workout_repository.dart';
import 'workout_draft.dart';

/// 进行中（或编辑中）的力量训练草稿。
/// null = 当前没有未完成的训练。
///
/// V1.1：进行中的训练实时落库（status = inProgress），
/// App 意外退出后可从首页「继续训练」恢复。
class ActiveWorkoutController extends Notifier<WorkoutDraft?> {
  @override
  WorkoutDraft? build() => null;

  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);

  /// 开始一场新训练。
  /// 若数据库中已有进行中的训练，则恢复它而不是重复创建。
  Future<void> startNew({Exercise? seed}) async {
    final existing = await _repo.getInProgressSession();
    if (existing != null) {
      await continueSession(existing.id);
      return;
    }
    final sessionId = await _repo.createInProgressSession();
    final draft = WorkoutDraft(
      sessionDbId: sessionId,
      isInProgress: true,
      startTime: DateTime.now(),
      exercises: [
        if (seed != null)
          DraftExercise(
            exerciseId: seed.id,
            name: seed.name,
            muscleGroup: seed.muscleGroup,
          ),
      ],
    );
    state = draft;
    _persist();
  }

  /// 「再练一次」：复制历史训练的名称与动作结构（不含组数据）。
  Future<void> startFromSession(int sourceSessionId) async {
    final existing = await _repo.getInProgressSession();
    if (existing != null) {
      await continueSession(existing.id);
      return;
    }
    final sessionId = await _repo.repeatSession(sourceSessionId);
    final draft = await _repo.loadDraftForEdit(sessionId);
    if (draft != null) state = draft;
  }

  /// 继续进行中的训练（首页横幅 / 编辑入口）。
  Future<void> continueSession(int sessionId) async {
    final draft = await _repo.loadDraftForEdit(sessionId);
    if (draft != null && draft.isInProgress) {
      state = draft;
    }
  }

  /// 编辑已完成的历史训练（手动保存，不自动落库）。
  Future<bool> loadForEdit(int sessionId) async {
    final draft = await _repo.loadDraftForEdit(sessionId);
    if (draft == null) return false;
    state = draft;
    return true;
  }

  /// 放弃进行中的训练：删除数据库记录并清空草稿。
  Future<void> discard() async {
    final draft = state;
    state = null;
    final id = draft?.sessionDbId;
    if (draft != null && draft.isInProgress && id != null) {
      try {
        await _repo.deleteSession(id);
      } catch (e) {
        debugPrint('放弃训练失败: $e');
      }
    }
  }

  void reset() => state = null;

  void setName(String value) => _update((d) => d.copyWith(name: value));

  void setNote(String value) => _update((d) => d.copyWith(note: value));

  void addExercises(List<Exercise> exercises) {
    final draft = state;
    if (draft == null || exercises.isEmpty) return;
    final existingIds = draft.exercises.map((e) => e.exerciseId).toSet();
    final additions = [
      for (final e in exercises)
        if (!existingIds.contains(e.id))
          DraftExercise(
            exerciseId: e.id,
            name: e.name,
            muscleGroup: e.muscleGroup,
          ),
    ];
    if (additions.isEmpty) return;
    _update((d) =>
        d.copyWith(exercises: [...d.exercises, ...additions]));
  }

  void removeExercise(int draftExerciseId) {
    _update((d) => d.copyWith(exercises: [
          for (final e in d.exercises)
            if (e.id != draftExerciseId) e,
        ]));
  }

  void setExerciseNote(int draftExerciseId, String note) {
    _update((d) => d.copyWith(exercises: [
          for (final e in d.exercises)
            if (e.id == draftExerciseId) e.copyWith(note: note) else e,
        ]));
  }

  void reorderExercises(int oldIndex, int newIndex) {
    final draft = state;
    if (draft == null) return;
    // onReorderItem 的 newIndex 已由框架做过移位调整，直接插入即可。
    final list = [...draft.exercises];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _update((d) => d.copyWith(exercises: list));
  }

  /// 添加一组：重量自动继承该动作最后一组的重量（第一组为空）。
  void addSet(int draftExerciseId) {
    _update((d) => d.copyWith(exercises: [
          for (final e in d.exercises)
            if (e.id == draftExerciseId)
              e.copyWith(sets: [
                ...e.sets,
                DraftSet(weight: e.sets.isEmpty ? 0 : e.sets.last.weight),
              ])
            else
              e,
        ]));
  }

  void updateWeight(int draftExerciseId, int setId, double weight) {
    _patchSet(draftExerciseId, setId, (s) => s.copyWith(weight: weight));
  }

  void updateReps(int draftExerciseId, int setId, int? reps) {
    _patchSet(draftExerciseId, setId, (s) => s.copyWith(reps: reps));
  }

  void removeSet(int draftExerciseId, int setId) {
    _update((d) => d.copyWith(exercises: [
          for (final e in d.exercises)
            if (e.id == draftExerciseId)
              e.copyWith(sets: [
                for (final s in e.sets)
                  if (s.id != setId) s,
              ])
            else
              e,
        ]));
  }

  /// 完成训练（校验由 UI 负责）。返回总结页用的 session id。
  Future<int?> finish() async {
    final draft = state;
    if (draft == null || draft.sessionDbId == null) return null;
    final id = await _repo.completeSession(draft.sessionDbId!, draft);
    state = null;
    return id;
  }

  /// 手动保存（编辑已完成训练时使用）。
  Future<void> saveEdits() async {
    final draft = state;
    final id = draft?.sessionDbId;
    if (draft == null || id == null || draft.isInProgress) return;
    await _repo.updateSession(id, draft);
    state = null;
  }

  void _update(WorkoutDraft Function(WorkoutDraft) transform) {
    final draft = state;
    if (draft == null) return;
    state = transform(draft);
    _persist();
  }

  void _patchSet(
    int draftExerciseId,
    int setId,
    DraftSet Function(DraftSet) patch,
  ) {
    _update((d) => d.copyWith(exercises: [
          for (final e in d.exercises)
            if (e.id == draftExerciseId)
              e.copyWith(sets: [
                for (final s in e.sets)
                  if (s.id == setId) patch(s) else s,
              ])
            else
              e,
        ]));
  }

  /// 进行中的训练每次修改后自动落库（失败不影响 UI，下次修改会再试）。
  void _persist() {
    final draft = state;
    final id = draft?.sessionDbId;
    if (draft == null || !draft.isInProgress || id == null) return;
    final repo = _repo; // 同步捕获，避免延迟执行时 ref 已被回收
    Future(() async {
      try {
        await repo.saveDraftContent(id, draft);
      } catch (e) {
        debugPrint('训练进度保存失败: $e');
      }
    });
  }
}

final activeWorkoutProvider =
    NotifierProvider<ActiveWorkoutController, WorkoutDraft?>(
        ActiveWorkoutController.new);
