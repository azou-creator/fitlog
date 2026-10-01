import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/database_provider.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/database/workout_repository.dart';
import 'package:fitlog/features/workout/active_workout.dart';

/// V1.1 核心体验测试：
/// 1. 添加训练组自动继承上一组重量，第一组不继承
/// 2. 进行中的训练每次修改自动落库（意外退出可恢复）
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await ExerciseRepository(db).ensureSeeded();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    // activeWorkoutProvider 是 autoDispose：测试里保持它存活（模拟编辑器页面在 watch）
    container.listen(activeWorkoutProvider, (_, _) {});
  });

  tearDown(() async {
    await db.close();
    container.dispose();
  });

  Future<Exercise> seeded(String name) async {
    final all = await ExerciseRepository(db).getAll();
    return all.firstWhere((e) => e.name == name);
  }

  test('添加一组自动继承上一组重量；第一组不继承', () async {
    final bench = await seeded('杠铃卧推');
    final controller = container.read(activeWorkoutProvider.notifier);
    await controller.startNew();
    controller.addExercises([bench]);

    final draft = container.read(activeWorkoutProvider)!;
    final exId = draft.exercises.first.id;

    // 第一组：重量为空（0），不继承任何东西
    controller.addSet(exId);
    var sets = container.read(activeWorkoutProvider)!.exercises.first.sets;
    expect(sets.length, 1);
    expect(sets[0].weight, 0);
    expect(sets[0].reps, isNull);

    // 输入 80 × 10
    controller.updateWeight(exId, sets[0].id, 80);
    controller.updateReps(exId, sets[0].id, 10);

    // 添加第二组：自动继承 80，次数为空待输入
    controller.addSet(exId);
    sets = container.read(activeWorkoutProvider)!.exercises.first.sets;
    expect(sets.length, 2);
    expect(sets[1].weight, 80);
    expect(sets[1].reps, isNull);

    // 换一个更轻的重量后再加组：继承最新值
    controller.updateWeight(exId, sets[1].id, 72.5);
    controller.addSet(exId);
    sets = container.read(activeWorkoutProvider)!.exercises.first.sets;
    expect(sets[2].weight, 72.5);
  });

  test('进行中的训练每次修改后自动落库，可重新加载', () async {
    final bench = await seeded('杠铃卧推');
    final controller = container.read(activeWorkoutProvider.notifier);
    await controller.startNew();

    controller.setName('推胸日');
    controller.addExercises([bench]);
    var draft = container.read(activeWorkoutProvider)!;
    final exId = draft.exercises.first.id;
    controller.addSet(exId);
    // 重新读取，拿到新加组的 id
    final setId =
        container.read(activeWorkoutProvider)!.exercises.first.sets[0].id;
    controller.updateWeight(exId, setId, 80);
    controller.updateReps(exId, setId, 10);

    // _persist 是异步落库，等待事件循环处理完成
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // 模拟 App 重启：从数据库重新加载进行中的训练
    final inProgress = await WorkoutRepository(db).getInProgressSession();
    expect(inProgress, isNotNull);

    final restored = await WorkoutRepository(db).loadDraftForEdit(
      inProgress!.id,
    );
    expect(restored!.isInProgress, isTrue);
    expect(restored.name, '推胸日');
    expect(restored.exercises.length, 1);
    expect(restored.exercises.first.sets.length, 1);
    expect(restored.exercises.first.sets.first.weight, 80);
    expect(restored.exercises.first.sets.first.reps, 10);

    // 放弃后数据库中不再有进行中的训练
    await controller.discard();
    expect(await WorkoutRepository(db).getInProgressSession(), isNull);
  });
}
