import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/data_change_provider.dart';
import '../core/utils/calc.dart' show calcTotalVolume;
import '../features/workout/workout_draft.dart';
import 'app_database.dart';
import 'database_provider.dart';

/// session 状态（v2 起存库）。
class SessionStatus {
  static const inProgress = 'inProgress';
  static const completed = 'completed';
}

/// 详情页 / 总结页的读取模型。
class DetailExercise {
  DetailExercise({
    required this.workoutExerciseId,
    required this.exercise,
    required this.sets,
    this.note,
  });

  final int workoutExerciseId;
  final Exercise exercise;
  final List<WorkoutSet> sets;
  final String? note;
}

class SessionDetail {
  SessionDetail({required this.session, required this.exercises});

  final WorkoutSession session;
  final List<DetailExercise> exercises;

  int get totalSets => exercises.fold(0, (n, e) => n + e.sets.length);

  double get totalVolume => calcTotalVolume([
    for (final e in exercises)
      for (final s in e.sets) (weight: s.weight, reps: s.reps),
  ]);

  int get exerciseCount => exercises.length;
}

class WorkoutRepository {
  WorkoutRepository(this._db);

  final AppDatabase _db;

  String _normalizeName(String raw) {
    final t = raw.trim();
    return t.isEmpty ? '未命名训练' : t;
  }

  String? _normalizeNullable(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  // ============ 进行中草稿（V1.1） ============

  Future<int> _insertInProgressRow({required String name}) {
    return _db
        .into(_db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            name: name,
            startTime: DateTime.now(),
            endTime: const Value(null),
            durationSeconds: 0,
            status: const Value(SessionStatus.inProgress),
            note: const Value(null),
          ),
        );
  }

  /// 创建一场进行中的训练（不做去重检查，仅供测试与内部使用）。
  /// 业务入口请使用 [createOrResumeWorkout]。
  Future<int> createInProgressSession({
    DateTime? startTime,
    String name = '',
    String note = '',
  }) {
    final start = startTime ?? DateTime.now();
    return _db
        .into(_db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            name: name,
            startTime: start,
            endTime: const Value(null),
            durationSeconds: 0,
            status: const Value(SessionStatus.inProgress),
            note: Value(_normalizeNullable(note)),
          ),
        );
  }

  /// ===== P0 唯一业务入口：开始力量训练 =====
  ///
  /// 所有「开始训练」路径（首页 / 记录页 / 最近动作快速开始 / 再练一次）
  /// 最终都必须调用这里。保证任意时刻数据库中至多一个 inProgress session：
  ///
  /// - 查询与创建放在同一个事务内（drift 的事务串行化，并发调用会排队，
  ///   后执行的事务一定能看到先执行事务的插入结果），不存在先查后退出的竞态；
  /// - 数据库层另有 partial unique index（见 AppDatabase v3）兜底。
  ///
  /// [exerciseStructure]：预填的动作结构（快速开始的单个动作 / 再练一次的
  /// 动作顺序），不包含任何组数据。若已存在进行中训练，则返回现有训练，
  /// 结构参数被忽略（不覆盖当前训练的动作）。
  Future<WorkoutSession> createOrResumeWorkout({
    String? name,
    List<DraftExercise>? exerciseStructure,
  }) {
    return _db.transaction(() async {
      final existing = await getInProgressSession();
      if (existing != null) {
        return existing;
      }
      final id = await _insertInProgressRow(name: name ?? '');
      if (exerciseStructure != null && exerciseStructure.isNotEmpty) {
        await _replaceContent(
          id,
          WorkoutDraft(
            sessionDbId: id,
            isInProgress: true,
            name: name ?? '',
            startTime: DateTime.now(),
            exercises: exerciseStructure,
          ),
        );
      }
      return (_db.select(
        _db.workoutSessions,
      )..where((s) => s.id.equals(id))).getSingle();
    });
  }

  /// 「再练一次」：以历史训练为模板开始。
  /// 已存在进行中训练时返回现有训练（不覆盖其动作、不删除）；
  /// 否则复制模板的名称与动作顺序（不复制组数据 / 时长 / 结束时间 / 备注）。
  Future<WorkoutSession> createOrResumeFromSession(int sourceSessionId) async {
    final source = await getDetail(sourceSessionId);
    if (source == null) {
      throw StateError('要复制的训练不存在');
    }
    final structure = [
      for (final de in source.exercises)
        DraftExercise(
          exerciseId: de.exercise.id,
          name: de.exercise.name,
          muscleGroup: de.exercise.muscleGroup,
        ),
    ];
    return createOrResumeWorkout(
      name: source.session.name,
      exerciseStructure: structure,
    );
  }

  /// 当前是否存在进行中的训练（首页横幅 / 防止重复创建）。
  Future<WorkoutSession?> getInProgressSession() {
    return (_db.select(_db.workoutSessions)
          ..where((s) => s.status.equals(SessionStatus.inProgress))
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 把草稿内容（动作/组/名称/备注）写入进行中的 session。每次修改后调用。
  Future<void> saveDraftContent(int sessionId, WorkoutDraft draft) {
    return _db.transaction(() async {
      await (_db.update(
        _db.workoutSessions,
      )..where((s) => s.id.equals(sessionId))).write(
        WorkoutSessionsCompanion(
          name: Value(draft.name.trim()),
          note: Value(_normalizeNullable(draft.note)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _replaceContent(sessionId, draft);
    });
  }

  /// 完成训练：写结束时间/时长/状态，并替换内容。返回 session id。
  Future<int> completeSession(int sessionId, WorkoutDraft draft) {
    final end = DateTime.now();
    var duration = end.difference(draft.startTime).inSeconds;
    if (duration < 0) duration = 0;
    return _db.transaction(() async {
      await (_db.update(
        _db.workoutSessions,
      )..where((s) => s.id.equals(sessionId))).write(
        WorkoutSessionsCompanion(
          name: Value(_normalizeName(draft.name)),
          startTime: Value(draft.startTime),
          endTime: Value(end),
          durationSeconds: Value(duration),
          status: const Value(SessionStatus.completed),
          note: Value(_normalizeNullable(draft.note)),
          updatedAt: Value(end),
        ),
      );
      await _replaceContent(sessionId, draft);
      return sessionId;
    });
  }

  /// 每个动作「上次」的参考数据：最近一次（不含 excludeSessionId）包含该动作的
  /// 已完成训练中，该动作各组的 (重量, 次数)。
  Future<Map<int, List<(double, int)>>> lastPerformanceMap(
    int? excludeSessionId,
    List<int> exerciseIds,
  ) async {
    if (exerciseIds.isEmpty) return {};
    final result = <int, List<(double, int)>>{};
    for (final exerciseId in exerciseIds) {
      var query =
          _db.select(_db.workoutExercises).join([
              innerJoin(
                _db.workoutSessions,
                _db.workoutSessions.id.equalsExp(
                  _db.workoutExercises.workoutSessionId,
                ),
              ),
            ])
            ..where(
              _db.workoutExercises.exerciseId.equals(exerciseId) &
                  _db.workoutSessions.status.equals(SessionStatus.completed),
            )
            ..orderBy([OrderingTerm.desc(_db.workoutSessions.startTime)])
            ..limit(1);
      if (excludeSessionId != null) {
        query.where(
          _db.workoutExercises.workoutSessionId.equals(excludeSessionId).not(),
        );
      }
      final rows = await query.get();
      if (rows.isEmpty) continue;
      final we = rows.first.readTable(_db.workoutExercises);
      final sets =
          await (_db.select(_db.workoutSets)
                ..where((s) => s.workoutExerciseId.equals(we.id))
                ..orderBy([(s) => OrderingTerm.asc(s.setOrder)]))
              .get();
      result[exerciseId] = [for (final s in sets) (s.weight, s.reps)];
    }
    return result;
  }

  // ============ 已完成训练 ============

  /// 更新已有训练：替换名称、备注与全部动作/组；开始时间与时长保持不变。
  Future<void> updateSession(int sessionId, WorkoutDraft draft) {
    return _db.transaction(() async {
      await (_db.update(
        _db.workoutSessions,
      )..where((s) => s.id.equals(sessionId))).write(
        WorkoutSessionsCompanion(
          name: Value(_normalizeName(draft.name)),
          note: Value(_normalizeNullable(draft.note)),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _replaceContent(sessionId, draft);
    });
  }

  Future<void> _replaceContent(int sessionId, WorkoutDraft draft) async {
    await (_db.delete(
      _db.workoutExercises,
    )..where((u) => u.workoutSessionId.equals(sessionId))).go();
    var sort = 0;
    for (final de in draft.exercises) {
      final validSets = de.sets.where((s) => s.isValid).toList();
      // 动作结构（含尚未记录组的动作）必须保留：进行中草稿和「再练一次」
      // 依赖它，否则没有组的动作会凭空消失。
      final weId = await _db
          .into(_db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              workoutSessionId: sessionId,
              exerciseId: de.exerciseId,
              sortOrder: sort,
              note: Value(_normalizeNullable(de.note)),
            ),
          );
      sort += 1;
      for (var j = 0; j < validSets.length; j++) {
        final s = validSets[j];
        await _db
            .into(_db.workoutSets)
            .insert(
              WorkoutSetsCompanion.insert(
                workoutExerciseId: weId,
                setOrder: j,
                weight: s.weight,
                reps: s.reps!,
              ),
            );
      }
    }
  }

  Future<SessionDetail?> getDetail(int sessionId) async {
    final session = await (_db.select(
      _db.workoutSessions,
    )..where((s) => s.id.equals(sessionId))).getSingleOrNull();
    if (session == null) return null;

    final query =
        _db.select(_db.workoutExercises).join([
            innerJoin(
              _db.exercises,
              _db.exercises.id.equalsExp(_db.workoutExercises.exerciseId),
            ),
          ])
          ..where(_db.workoutExercises.workoutSessionId.equals(sessionId))
          ..orderBy([OrderingTerm.asc(_db.workoutExercises.sortOrder)]);

    final rows = await query.get();
    final exercises = <DetailExercise>[];
    for (final row in rows) {
      final we = row.readTable(_db.workoutExercises);
      final ex = row.readTable(_db.exercises);
      final sets =
          await (_db.select(_db.workoutSets)
                ..where((s) => s.workoutExerciseId.equals(we.id))
                ..orderBy([(s) => OrderingTerm.asc(s.setOrder)]))
              .get();
      exercises.add(
        DetailExercise(
          workoutExerciseId: we.id,
          exercise: ex,
          sets: sets,
          note: we.note,
        ),
      );
    }
    return SessionDetail(session: session, exercises: exercises);
  }

  /// 编辑模式：把已有训练加载回草稿（含进行中标记）。
  Future<WorkoutDraft?> loadDraftForEdit(int sessionId) async {
    final detail = await getDetail(sessionId);
    if (detail == null) return null;
    return WorkoutDraft(
      sessionDbId: sessionId,
      isInProgress: detail.session.status == SessionStatus.inProgress,
      name: detail.session.name == '未命名训练' ? '' : detail.session.name,
      note: detail.session.note ?? '',
      startTime: detail.session.startTime,
      exercises: [
        for (final de in detail.exercises)
          DraftExercise(
            exerciseId: de.exercise.id,
            name: de.exercise.name,
            muscleGroup: de.exercise.muscleGroup,
            note: de.note ?? '',
            sets: [
              for (final s in de.sets) DraftSet(weight: s.weight, reps: s.reps),
            ],
          ),
      ],
    );
  }

  /// 真实删除（级联删除动作与组）。
  Future<void> deleteSession(int sessionId) {
    return (_db.delete(
      _db.workoutSessions,
    )..where((s) => s.id.equals(sessionId))).go();
  }

  /// 最近一次已完成训练的详情（首页 / 记录页）。
  Future<SessionDetail?> getLatestSessionDetail() async {
    final latest =
        await (_db.select(_db.workoutSessions)
              ..where((s) => s.status.equals(SessionStatus.completed))
              ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
              ..limit(1))
            .getSingleOrNull();
    if (latest == null) return null;
    return getDetail(latest.id);
  }

  /// 时间区间内已完成的力量训练（用于统计）。
  Future<List<WorkoutSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) {
    return (_db.select(_db.workoutSessions)..where(
          (s) =>
              s.status.equals(SessionStatus.completed) &
              s.startTime.isBiggerOrEqualValue(start) &
              s.startTime.isSmallerOrEqualValue(end),
        ))
        .get();
  }

  /// 统计时间区间内力量训练的总组数。
  Future<int> countSetsBetween(DateTime start, DateTime end) async {
    final countExp = countAll();
    final query = _db.selectOnly(_db.workoutSets)
      ..addColumns([countExp])
      ..join([
        innerJoin(
          _db.workoutExercises,
          _db.workoutExercises.id.equalsExp(_db.workoutSets.workoutExerciseId),
        ),
        innerJoin(
          _db.workoutSessions,
          _db.workoutSessions.id.equalsExp(
            _db.workoutExercises.workoutSessionId,
          ),
        ),
      ])
      ..where(
        _db.workoutSessions.status.equals(SessionStatus.completed) &
            _db.workoutSessions.startTime.isBiggerOrEqualValue(start) &
            _db.workoutSessions.startTime.isSmallerOrEqualValue(end),
      );
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// 全部已完成 session（历史页用）。
  Future<List<WorkoutSession>> getAllCompletedSessions() {
    return (_db.select(_db.workoutSessions)
          ..where((s) => s.status.equals(SessionStatus.completed))
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
        .get();
  }

  /// 全部 session（导出用，含进行中）。
  Future<List<WorkoutSession>> getAllSessionsForExport() {
    return (_db.select(
      _db.workoutSessions,
    )..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
  }
}

final workoutRepositoryProvider = Provider<WorkoutRepository>(
  (ref) => WorkoutRepository(ref.watch(appDatabaseProvider)),
);

/// 训练详情（含总结页）。加载失败或不存在返回 null。
final sessionDetailProvider = FutureProvider.family<SessionDetail?, int>((
  ref,
  sessionId,
) async {
  try {
    return await ref.watch(workoutRepositoryProvider).getDetail(sessionId);
  } catch (e) {
    debugPrint('加载训练详情失败: $e');
    return null;
  }
});

/// 进行中的训练（首页横幅）。数据变化时自动刷新。
final inProgressSessionProvider = FutureProvider((ref) async {
  ref.watch(dataChangeProvider);
  try {
    return await ref.watch(workoutRepositoryProvider).getInProgressSession();
  } catch (e) {
    debugPrint('查询进行中训练失败: $e');
    return null;
  }
});
