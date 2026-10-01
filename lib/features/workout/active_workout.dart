import 'dart:async';

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
///
/// P0（数据可靠性）：所有持久化经过「串行保存队列 + 最新快照 + 可 flush 的
/// debounce」——
/// - UI 输入立即更新内存 state，不等数据库；
/// - 每次修改只刷新最新 draft 快照，debounce（250ms）合并连续击键；
/// - 到期后进入串行队列，写顺序 = 修改顺序，旧值永远不会覆盖新值；
/// - [flushPendingChanges] 立即落库所有未写内容并等待全部完成，
///   「完成训练 / 保存修改 / App 退到后台」之前必须调用。
class ActiveWorkoutController extends Notifier<WorkoutDraft?> {
  @override
  WorkoutDraft? build() => null;

  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);

  // ===== 保存队列 / debounce（P0） =====
  static const _debounceDuration = Duration(milliseconds: 250);
  Timer? _debounceTimer;
  WorkoutDraft? _pendingSave;
  Future<void> _saveQueue = Future<void>.value();

  /// 进行中的「开始训练」请求（P0 防护的体验层辅助）：
  /// 并发触发（双击 / 跨页面快速点击）共享同一个 Future，
  /// 数据不变量本身由 Repository 事务与数据库唯一索引保证。
  Future<void>? _pendingStart;

  /// 把尚未落库的最新 draft 快照加入串行保存队列。
  /// 队列保证：上一次写完成后才开始下一次，最终库状态 = 最后一次修改。
  void _enqueueSave(WorkoutRepository repo) {
    final draft = _pendingSave;
    if (draft == null) return;
    _pendingSave = null;
    final id = draft.sessionDbId;
    if (id == null) return;
    _saveQueue = _saveQueue.then((_) async {
      try {
        await repo.saveDraftContent(id, draft);
      } catch (e) {
        // 保存失败不中断队列、不影响 UI；后续修改会再次尝试。
        debugPrint('训练进度保存失败: $e');
      }
    });
  }

  /// 立即落库所有未持久化的修改（名称/备注/动作/组/重量/次数）。
  /// 返回的 Future 在全部已入队写操作完成后才完成。
  /// 「完成训练」「保存修改」「App 退到后台」之前必须调用。
  Future<void> flushPendingChanges() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _enqueueSave(_repo);
    return _saveQueue;
  }

  void _schedulePersist() {
    final draft = state;
    if (draft == null || !draft.isInProgress || draft.sessionDbId == null) {
      return;
    }
    _pendingSave = draft; // 永远保留最新快照，旧快照被直接丢弃
    _debounceTimer ??= Timer(_debounceDuration, () {
      _debounceTimer = null;
      _enqueueSave(_repo);
    });
  }

  // ===== 开始 / 恢复 =====

  /// 开始一场新训练（首页 / 记录页 / 最近动作快速开始共用）。
  /// 若数据库中已有进行中的训练，则恢复它而不是重复创建。
  Future<void> startNew({Exercise? seed}) {
    final pending = _pendingStart;
    if (pending != null) return pending;
    final op = _startNewNow(seed: seed)
        .whenComplete(() => _pendingStart = null);
    _pendingStart = op;
    return op;
  }

  Future<void> _startNewNow({Exercise? seed}) async {
    final session = await _repo.createOrResumeWorkout(
      exerciseStructure: seed == null
          ? null
          : [
              DraftExercise(
                exerciseId: seed.id,
                name: seed.name,
                muscleGroup: seed.muscleGroup,
              ),
            ],
    );
    final draft = await _repo.loadDraftForEdit(session.id);
    if (draft != null && draft.isInProgress) state = draft;
  }

  /// 「再练一次」：以历史训练为模板开始。
  /// 已存在进行中训练时进入现有训练（不覆盖其动作、不删除）。
  Future<void> startFromSession(int sourceSessionId) {
    final pending = _pendingStart;
    if (pending != null) return pending;
    final op = _startFromSessionNow(sourceSessionId)
        .whenComplete(() => _pendingStart = null);
    _pendingStart = op;
    return op;
  }

  Future<void> _startFromSessionNow(int sourceSessionId) async {
    final session = await _repo.createOrResumeFromSession(sourceSessionId);
    final draft = await _repo.loadDraftForEdit(session.id);
    if (draft != null && draft.isInProgress) state = draft;
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

  // ===== 结束 =====

  /// 放弃进行中的训练：删除数据库记录并清空草稿。
  Future<void> discard() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingSave = null; // 丢弃尚未落库的内容
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

  void reset() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingSave = null;
    state = null;
  }

  // ===== 完成训练（严格顺序） =====

  /// 完成训练（有效组校验由 UI 负责）。返回总结页用的 session id。
  ///
  /// 顺序保证：先 flush 所有未持久化修改（最后一次输入 100% 落库），
  /// 再执行 completeSession 单事务（endTime/duration/status/内容全部在内），
  /// 自动保存与完成事务永远不会并发交错。
  Future<int?> finish() async {
    final draft = state;
    if (draft == null || draft.sessionDbId == null) return null;
    await flushPendingChanges();
    final id = await _repo.completeSession(draft.sessionDbId!, draft);
    state = null;
    return id;
  }

  /// 手动保存（编辑已完成训练时使用）。
  Future<void> saveEdits() async {
    final draft = state;
    final id = draft?.sessionDbId;
    if (draft == null || id == null || draft.isInProgress) return;
    await flushPendingChanges();
    await _repo.updateSession(id, draft);
    state = null;
  }

  // ===== 修改操作（UI 输入立即更新内存 state，不等待数据库） =====

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
    _update((d) => d.copyWith(exercises: [...d.exercises, ...additions]));
  }

  void removeExercise(int draftExerciseId) {
    _update(
      (d) => d.copyWith(
        exercises: [
          for (final e in d.exercises)
            if (e.id != draftExerciseId) e,
        ],
      ),
    );
  }

  void setExerciseNote(int draftExerciseId, String note) {
    _update(
      (d) => d.copyWith(
        exercises: [
          for (final e in d.exercises)
            if (e.id == draftExerciseId) e.copyWith(note: note) else e,
        ],
      ),
    );
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
    _update(
      (d) => d.copyWith(
        exercises: [
          for (final e in d.exercises)
            if (e.id == draftExerciseId)
              e.copyWith(
                sets: [
                  ...e.sets,
                  DraftSet(weight: e.sets.isEmpty ? 0 : e.sets.last.weight),
                ],
              )
            else
              e,
        ],
      ),
    );
  }

  void updateWeight(int draftExerciseId, int setId, double weight) {
    _patchSet(draftExerciseId, setId, (s) => s.copyWith(weight: weight));
  }

  void updateReps(int draftExerciseId, int setId, int? reps) {
    _patchSet(draftExerciseId, setId, (s) => s.copyWith(reps: reps));
  }

  void removeSet(int draftExerciseId, int setId) {
    _update(
      (d) => d.copyWith(
        exercises: [
          for (final e in d.exercises)
            if (e.id == draftExerciseId)
              e.copyWith(
                sets: [
                  for (final s in e.sets)
                    if (s.id != setId) s,
                ],
              )
            else
              e,
        ],
      ),
    );
  }

  void _update(WorkoutDraft Function(WorkoutDraft) transform) {
    final draft = state;
    if (draft == null) return;
    state = transform(draft);
    _schedulePersist();
  }

  void _patchSet(
    int draftExerciseId,
    int setId,
    DraftSet Function(DraftSet) patch,
  ) {
    _update(
      (d) => d.copyWith(
        exercises: [
          for (final e in d.exercises)
            if (e.id == draftExerciseId)
              e.copyWith(
                sets: [
                  for (final s in e.sets)
                    if (s.id == setId) patch(s) else s,
                ],
              )
            else
              e,
        ],
      ),
    );
  }
}

final activeWorkoutProvider =
    NotifierProvider<ActiveWorkoutController, WorkoutDraft?>(
      ActiveWorkoutController.new,
    );
