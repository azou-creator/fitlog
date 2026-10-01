import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/database/workout_repository.dart';
import 'package:fitlog/features/workout/workout_draft.dart';

/// P0 稳定性：任意时刻至多一个 status = inProgress 的力量训练 session。
///
/// 三层保证：
/// 1. 所有入口收敛到 WorkoutRepository.createOrResumeWorkout
/// 2. 查询+创建在同一个 drift 事务内（事务串行化，无 check-then-act 竞态）
/// 3. 数据库 partial unique index（idx_workout_sessions_active）兜底
void main() {
  late AppDatabase db;
  late WorkoutRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkoutRepository(db);
    await ExerciseRepository(db).ensureSeeded();
  });

  tearDown(() => db.close());

  Future<int> activeCount() async {
    final rows = await (db.select(
      db.workoutSessions,
    )..where((s) => s.status.equals(SessionStatus.inProgress))).get();
    return rows.length;
  }

  test('数据库 v3 建库后存在 partial unique index', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
          variables: [Variable.withString('idx_workout_sessions_active')],
        )
        .get();
    expect(rows, hasLength(1));
  });

  test('绕过业务层直接插入第二个 inProgress 会被数据库唯一索引拒绝', () async {
    await repo.createOrResumeWorkout(name: '第一场');
    expect(
      () => db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              name: '第二场',
              startTime: DateTime.now(),
              durationSeconds: 0,
              status: const Value(SessionStatus.inProgress),
            ),
          ),
      throwsA(isA<Exception>()),
    );
  });

  test('测试 1：无 active 时连续两次调用，最终只有 1 条 inProgress', () async {
    final first = await repo.createOrResumeWorkout(name: '第一场');
    final second = await repo.createOrResumeWorkout(name: '第二场');

    expect(second.id, first.id);
    expect(await activeCount(), 1);
    // 名称仍是第一场的（不会被第二次调用覆盖）
    expect(second.name, '第一场');
  });

  test('测试 2：已存在 active 时再次开始训练，返回原 session 且内容不被覆盖', () async {
    final bench = (await ExerciseRepository(
      db,
    ).getAll()).firstWhere((e) => e.name == '杠铃卧推');

    final session = await repo.createOrResumeWorkout(name: '练胸');
    // 给现有训练写入内容（模拟用户已经在练）
    await repo.saveDraftContent(
      session.id,
      WorkoutDraft(
        sessionDbId: session.id,
        isInProgress: true,
        name: '练胸',
        startTime: session.startTime,
        exercises: [
          DraftExercise(
            exerciseId: bench.id,
            name: bench.name,
            muscleGroup: bench.muscleGroup,
            sets: [DraftSet(weight: 80, reps: 10)],
          ),
        ],
      ),
    );

    // 另一个入口再次"开始训练"（带了完全不同的预填结构）
    final again = await repo.createOrResumeWorkout(
      name: '另一次',
      exerciseStructure: [
        DraftExercise(exerciseId: bench.id, name: bench.name, muscleGroup: '胸'),
      ],
    );

    expect(again.id, session.id);
    expect(await activeCount(), 1);

    // 现有训练内容不被覆盖
    final detail = await repo.getDetail(session.id);
    expect(detail!.session.name, '练胸');
    expect(detail.exercises.first.sets.single.weight, 80);
  });

  test('测试 3：已有 active 时调用「再练一次」，不创建第二个 active session', () async {
    final all = await ExerciseRepository(db).getAll();
    final bench = all.firstWhere((e) => e.name == '杠铃卧推');

    // 模板（历史已完成训练）
    final templateId = await repo.createInProgressSession(name: '肩部日');
    final templateDraft = WorkoutDraft(
      sessionDbId: templateId,
      isInProgress: true,
      name: '肩部日',
      startTime: DateTime.now(),
      exercises: [
        DraftExercise(
          exerciseId: bench.id,
          name: bench.name,
          muscleGroup: bench.muscleGroup,
          sets: [DraftSet(weight: 50, reps: 12)],
        ),
      ],
    );
    await repo.saveDraftContent(templateId, templateDraft);
    await repo.completeSession(templateId, templateDraft);

    // 先开始了一场进行中的训练
    final active = await repo.createOrResumeWorkout(name: '正在练的');

    // 再点「再练一次」→ 应返回正在练的这场，而不是新建
    final result = await repo.createOrResumeFromSession(templateId);
    expect(result.id, active.id);
    expect(await activeCount(), 1);

    // 正在练的这场内容没有被模板偷偷覆盖
    final detail = await repo.getDetail(active.id);
    expect(detail!.session.name, '正在练的');

    // 模板本身不受影响
    final template = await repo.getDetail(templateId);
    expect(template!.session.status, SessionStatus.completed);
    expect(template.exercises.first.sets.single.weight, 50);
  });

  test('测试 4：并发调用 createOrResumeWorkout，仍只有 1 条 inProgress', () async {
    final results = await Future.wait([
      repo.createOrResumeWorkout(name: '并发A'),
      repo.createOrResumeWorkout(name: '并发B'),
      repo.createOrResumeWorkout(),
    ]);

    // 三个调用全部返回同一场训练
    expect(results[0].id, results[1].id);
    expect(results[1].id, results[2].id);
    expect(await activeCount(), 1);
  });

  test('测试 4b：并发混合「开始训练」与「再练一次」', () async {
    final all = await ExerciseRepository(db).getAll();
    final bench = all.firstWhere((e) => e.name == '杠铃卧推');

    final templateId = await repo.createInProgressSession(name: '模板');
    final templateDraft = WorkoutDraft(
      sessionDbId: templateId,
      isInProgress: true,
      name: '模板',
      startTime: DateTime.now(),
      exercises: [
        DraftExercise(
          exerciseId: bench.id,
          name: bench.name,
          muscleGroup: bench.muscleGroup,
          sets: [DraftSet(weight: 60, reps: 8)],
        ),
      ],
    );
    await repo.saveDraftContent(templateId, templateDraft);
    await repo.completeSession(templateId, templateDraft);

    final results = await Future.wait([
      repo.createOrResumeFromSession(templateId),
      repo.createOrResumeWorkout(name: '直接开始'),
    ]);

    expect(results[0].id, results[1].id);
    expect(await activeCount(), 1);
  });
}
