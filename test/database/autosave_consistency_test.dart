import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/database_provider.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/database/workout_repository.dart';
import 'package:fitlog/features/workout/active_workout.dart';

/// P0（数据可靠性）：自动保存的最终一致性。
///
/// 覆盖：
/// - 快速连续修改同一组：最终库状态 = 用户最后看到的值（旧值不覆盖新值）；
/// - 输入后立即「完成训练」：最后一次输入 100% 落库后才执行完成事务；
/// - 完成事务的原子性：status/endTime/duration/最后一组数据一致；
/// - 数据库写失败时训练保持 inProgress，不会被错误完成；
/// - debounce 的 flush 语义：flush 后最后一次值一定已写入。
void main() {
  late AppDatabase db;
  late WorkoutRepository repo;
  late ProviderContainer container;
  late ActiveWorkoutController controller;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await ExerciseRepository(db).ensureSeeded();
    repo = WorkoutRepository(db);
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    // activeWorkoutProvider 是 autoDispose：测试中保持存活（模拟编辑器在 watch）
    container.listen(activeWorkoutProvider, (_, _) {});
    controller = container.read(activeWorkoutProvider.notifier);
  });

  tearDown(() async {
    await db.close();
    container.dispose();
  });

  /// 开始一场带「杠铃卧推 × 1 组」的训练。
  /// 返回 (sessionDbId, draftExerciseId, setId)。
  Future<(int, int, int)> startWithOneSet() async {
    await controller.startNew();
    final sessionDbId = container.read(activeWorkoutProvider)!.sessionDbId!;
    final bench = (await ExerciseRepository(
      db,
    ).getAll()).firstWhere((e) => e.name == '杠铃卧推');
    controller.addExercises([bench]);
    final draftExId = container.read(activeWorkoutProvider)!.exercises.first.id;
    controller.addSet(draftExId);
    final setId = container
        .read(activeWorkoutProvider)!
        .exercises
        .first
        .sets[0]
        .id;
    return (sessionDbId, draftExId, setId);
  }

  Future<int> activeCount() async {
    final rows = await (db.select(
      db.workoutSessions,
    )..where((s) => s.status.equals(SessionStatus.inProgress))).get();
    return rows.length;
  }

  test('测试 1：有效组快速修改重量 60 → 80 → 80.5，最终数据库为 80.5', () async {
    final (sessionDbId, draftExId, setId) = await startWithOneSet();

    // 先输入次数让组成为有效组（无效组不落库，这是产品规则），
    // 然后模拟竞速修改重量：每个字符触发一次 onChanged。
    controller.updateReps(draftExId, setId, 10);
    controller.updateWeight(draftExId, setId, 60);
    controller.updateWeight(draftExId, setId, 80);
    controller.updateWeight(draftExId, setId, 80.5);

    await controller.flushPendingChanges();

    final detail = await repo.getDetail(sessionDbId);
    final set = detail!.exercises.first.sets.single;
    expect(set.weight, 80.5);
    expect(set.reps, 10);
    expect(await activeCount(), 1);
  });

  test('测试 2：快速修改次数 10 → 8 → 6，最终数据库为 6，重量不受影响', () async {
    final (sessionDbId, draftExId, setId) = await startWithOneSet();

    controller.updateWeight(draftExId, setId, 80);
    controller.updateReps(draftExId, setId, 10);
    controller.updateReps(draftExId, setId, 8);
    controller.updateReps(draftExId, setId, 6);

    await controller.flushPendingChanges();

    final detail = await repo.getDetail(sessionDbId);
    final set = detail!.exercises.first.sets.single;
    expect(set.reps, 6);
    expect(set.weight, 80);
  });

  test('测试 3：输入 80×8 后立即完成训练（最后一次保存尚未落库），数据库仍为 80×8', () async {
    final (sessionDbId, draftExId, setId) = await startWithOneSet();

    controller.updateWeight(draftExId, setId, 80);
    controller.updateReps(draftExId, setId, 8);
    // 注意：这里不调用 flush——pending 的 debounce 还没有触发，
    // 直接点「完成」，finish 内部必须先 flush 再完成。

    final finishedId = await controller.finish();
    expect(finishedId, sessionDbId);

    final detail = await repo.getDetail(sessionDbId);
    final set = detail!.exercises.first.sets.single;
    expect(set.weight, 80);
    expect(set.reps, 8);
  });

  test('测试 4：完成训练后 status/endTime/duration 与最后一组数据一致', () async {
    final (sessionDbId, draftExId, setId) = await startWithOneSet();

    controller.updateWeight(draftExId, setId, 80);
    controller.updateReps(draftExId, setId, 8);
    await controller.finish();

    final detail = await repo.getDetail(sessionDbId);
    expect(detail!.session.status, SessionStatus.completed);
    expect(detail.session.endTime, isNotNull);
    expect(detail.session.durationSeconds, greaterThanOrEqualTo(0));
    expect(detail.exercises.first.sets.single.weight, 80);
    expect(detail.exercises.first.sets.single.reps, 8);
    expect(await activeCount(), 0);
  });

  test('测试 5：数据库写入失败时，完成操作不把训练错误标记为 completed', () async {
    final (sessionDbId, draftExId, setId) = await startWithOneSet();

    // 注入一个不存在于动作库的动作（外键约束会让落库/完成失败）
    final ghost = Exercise(
      id: 999999,
      name: '幽灵动作',
      muscleGroup: '胸',
      isCustom: false,
      createdAt: DateTime.now(),
    );
    controller.addExercises([ghost]);
    final ghostDraftExId = container
        .read(activeWorkoutProvider)!
        .exercises
        .last
        .id;
    controller.addSet(ghostDraftExId);
    final ghostSetId = container
        .read(activeWorkoutProvider)!
        .exercises
        .last
        .sets[0]
        .id;
    controller.updateWeight(ghostDraftExId, ghostSetId, 80);
    controller.updateReps(ghostDraftExId, ghostSetId, 8);

    // finish 内部 flush 会因外键失败（被队列吞掉），completeSession 事务同样失败
    await expectLater(controller.finish(), throwsA(anything));

    // 训练必须保持 inProgress：状态、结束时间都未被破坏
    final detail = await repo.getDetail(sessionDbId);
    expect(detail!.session.status, SessionStatus.inProgress);
    expect(detail.session.endTime, isNull);
    expect(await activeCount(), 1);
  });

  test('测试 6：debounce 之后调用 flush，最后一次值必须已经写入', () async {
    final (sessionDbId, draftExId, setId) = await startWithOneSet();
    // 组有效化（先输次数）
    controller.updateReps(draftExId, setId, 10);
    await controller.flushPendingChanges();

    // 路径 A：修改后立即 flush（debounce 被取消，快照直接入队）
    controller.updateWeight(draftExId, setId, 77.5);
    await controller.flushPendingChanges();
    var detail = await repo.getDetail(sessionDbId);
    expect(detail!.exercises.first.sets.single.weight, 77.5);

    // 路径 B：不 flush，等 debounce timer 自然触发，也应写入最后一次值
    controller.updateWeight(draftExId, setId, 82.5);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    detail = await repo.getDetail(sessionDbId);
    expect(detail!.exercises.first.sets.single.weight, 82.5);
  });
}
