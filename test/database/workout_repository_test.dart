import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/database/seed_exercises.dart';
import 'package:fitlog/database/workout_repository.dart';
import 'package:fitlog/features/workout/workout_draft.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository exerciseRepo;
  late WorkoutRepository workoutRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    exerciseRepo = ExerciseRepository(db);
    workoutRepo = WorkoutRepository(db);
    await exerciseRepo.ensureSeeded();
  });

  tearDown(() => db.close());

  Future<int> seededId(String name) async {
    final all = await exerciseRepo.getAll();
    return all.firstWhere((e) => e.name == name).id;
  }

  /// 构造一场已完成训练（V1.1 流程：创建草稿 → 写内容 → 完成）。
  Future<int> quickCompletedSession({
    required String name,
    required Map<int, List<(double, int)>> exercises,
    DateTime? startTime,
  }) async {
    final sessionId = await workoutRepo.createInProgressSession(
      startTime: startTime ?? DateTime.now(),
      name: name,
    );
    final draft = WorkoutDraft(
      sessionDbId: sessionId,
      isInProgress: true,
      name: name,
      startTime: startTime ?? DateTime.now(),
      exercises: [
        for (final entry in exercises.entries)
          DraftExercise(
            exerciseId: entry.key,
            name: '动作${entry.key}',
            muscleGroup: '胸',
            sets: [
              for (final (w, r) in entry.value) DraftSet(weight: w, reps: r),
            ],
          ),
      ],
    );
    await workoutRepo.saveDraftContent(sessionId, draft);
    await workoutRepo.completeSession(sessionId, draft);
    return sessionId;
  }

  test('动作库初始化幂等：重复调用不重复插入', () async {
    await exerciseRepo.ensureSeeded();
    final all = await exerciseRepo.getAll();
    final total = seedExercises.values.fold<int>(0, (n, l) => n + l.length);
    expect(all.length, total);
    expect(all.every((e) => !e.isCustom), isTrue);
  });

  test('创建自定义动作；同名同部位不会重复创建', () async {
    final id1 = await exerciseRepo.createCustom(
      name: '农夫行走',
      muscleGroup: '核心',
    );
    final id2 = await exerciseRepo.createCustom(
      name: '农夫行走',
      muscleGroup: '核心',
    );
    expect(id1, id2);

    final all = await exerciseRepo.getAll();
    final custom = all.where((e) => e.name == '农夫行走').toList();
    expect(custom.length, 1);
    expect(custom.first.isCustom, isTrue);
  });

  group('训练草稿 / 完成（V1.1 流程）', () {
    test('保存后详情完整：名称、动作顺序、组顺序、小数重量、备注', () async {
      final benchId = await seededId('杠铃卧推');
      final dbPressId = await seededId('哑铃卧推');

      final sessionId = await workoutRepo.createInProgressSession(
        name: '胸 + 肩',
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final draft = WorkoutDraft(
        sessionDbId: sessionId,
        isInProgress: true,
        name: '胸 + 肩',
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        note: '状态不错',
        exercises: [
          DraftExercise(
            exerciseId: benchId,
            name: '杠铃卧推',
            muscleGroup: '胸',
            note: '握距略宽',
            sets: [
              DraftSet(weight: 60, reps: 12),
              DraftSet(weight: 80, reps: 10),
              DraftSet(weight: 80, reps: null), // 无效组不落库
            ],
          ),
          DraftExercise(
            exerciseId: dbPressId,
            name: '哑铃卧推',
            muscleGroup: '胸',
            sets: [DraftSet(weight: 22.5, reps: 12)],
          ),
        ],
      );
      await workoutRepo.saveDraftContent(sessionId, draft);
      await workoutRepo.completeSession(sessionId, draft);

      final detail = await workoutRepo.getDetail(sessionId);
      expect(detail, isNotNull);
      expect(detail!.session.name, '胸 + 肩');
      expect(detail.session.status, SessionStatus.completed);
      expect(detail.session.endTime, isNotNull);
      expect(detail.exerciseCount, 2);
      expect(detail.exercises[0].exercise.name, '杠铃卧推');
      expect(detail.exercises[0].note, '握距略宽');
      expect(detail.exercises[0].sets.length, 2); // 无效组被过滤
      expect(detail.exercises[0].sets[0].weight, 60);
      expect(detail.exercises[0].sets[1].weight, 80);
      expect(detail.exercises[1].sets.first.weight, 22.5);
      expect(detail.totalVolume, closeTo(60 * 12 + 80 * 10 + 22.5 * 12, 0.01));
    });

    test('进行中的训练可恢复；完成后状态变更', () async {
      final benchId = await seededId('杠铃卧推');
      final sessionId = await workoutRepo.createInProgressSession(
        name: '胸',
        startTime: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      await workoutRepo.saveDraftContent(
        sessionId,
        WorkoutDraft(
          sessionDbId: sessionId,
          isInProgress: true,
          name: '胸',
          startTime: DateTime.now().subtract(const Duration(minutes: 30)),
          exercises: [
            DraftExercise(
              exerciseId: benchId,
              name: '杠铃卧推',
              muscleGroup: '胸',
              sets: [DraftSet(weight: 60, reps: 10)],
            ),
          ],
        ),
      );

      // App 重启后：能找到进行中的训练并加载回草稿
      final inProgress = await workoutRepo.getInProgressSession();
      expect(inProgress, isNotNull);
      expect(inProgress!.id, sessionId);

      final draft = await workoutRepo.loadDraftForEdit(sessionId);
      expect(draft!.isInProgress, isTrue);
      expect(draft.exercises.first.sets.first.weight, 60);

      // 完成后：不再出现在进行中列表
      await workoutRepo.completeSession(sessionId, draft);
      expect(await workoutRepo.getInProgressSession(), isNull);
      final detail = await workoutRepo.getDetail(sessionId);
      expect(detail!.session.status, SessionStatus.completed);
    });

    test('更新已完成训练：替换动作与组，session 不新增', () async {
      final benchId = await seededId('杠铃卧推');
      final squatId = await seededId('深蹲');

      final sessionId = await quickCompletedSession(
        name: '胸',
        exercises: {
          benchId: [(60, 10)],
        },
      );

      final draft = await workoutRepo.loadDraftForEdit(sessionId);
      final updated = WorkoutDraft(
        sessionDbId: sessionId,
        isInProgress: false,
        name: '腿',
        startTime: draft!.startTime,
        exercises: [
          DraftExercise(
            exerciseId: squatId,
            name: '深蹲',
            muscleGroup: '腿',
            sets: [
              DraftSet(weight: 100, reps: 8),
              DraftSet(weight: 120, reps: 6),
            ],
          ),
        ],
      );
      await workoutRepo.updateSession(sessionId, updated);

      final sessions = await workoutRepo.getAllCompletedSessions();
      expect(sessions.length, 1);
      expect(sessions.first.name, '腿');

      final detail = await workoutRepo.getDetail(sessionId);
      expect(detail!.exerciseCount, 1);
      expect(detail.exercises.first.exercise.name, '深蹲');
      expect(detail.exercises.first.sets.length, 2);
    });

    test('删除训练级联删除动作与组', () async {
      final benchId = await seededId('杠铃卧推');
      final sessionId = await quickCompletedSession(
        name: '胸',
        exercises: {
          benchId: [(80, 8)],
        },
      );

      await workoutRepo.deleteSession(sessionId);

      expect(await workoutRepo.getDetail(sessionId), isNull);
      expect(await db.select(db.workoutExercises).get(), isEmpty);
      expect(await db.select(db.workoutSets).get(), isEmpty);
    });

    test('名称为空时完成训练自动归一化为「未命名训练」', () async {
      final benchId = await seededId('杠铃卧推');
      final sessionId = await workoutRepo.createInProgressSession();
      await workoutRepo.saveDraftContent(
        sessionId,
        WorkoutDraft(
          sessionDbId: sessionId,
          isInProgress: true,
          startTime: DateTime.now(),
          exercises: [
            DraftExercise(
              exerciseId: benchId,
              name: '杠铃卧推',
              muscleGroup: '胸',
              sets: [DraftSet(weight: 80, reps: 8)],
            ),
          ],
        ),
      );
      await workoutRepo.completeSession(
        sessionId,
        WorkoutDraft(
          sessionDbId: sessionId,
          isInProgress: true,
          startTime: DateTime.now(),
          exercises: [
            DraftExercise(
              exerciseId: benchId,
              name: '杠铃卧推',
              muscleGroup: '胸',
              sets: [DraftSet(weight: 80, reps: 8)],
            ),
          ],
        ),
      );
      final detail = await workoutRepo.getDetail(sessionId);
      expect(detail!.session.name, '未命名训练');
    });
  });

  test('「再练一次」只复制名称与动作结构，不复制组数据/备注', () async {
    final benchId = await seededId('杠铃卧推');
    final lateralId = await seededId('侧平举');

    final sourceId = await quickCompletedSession(
      name: '肩部日',
      exercises: {
        benchId: [(60, 12), (80, 10)],
        lateralId: [(10, 15)],
      },
    );

    final session = await workoutRepo.createOrResumeFromSession(sourceId);
    final draft = await workoutRepo.loadDraftForEdit(session.id);

    expect(draft, isNotNull);
    expect(draft!.isInProgress, isTrue);
    expect(draft.name, '肩部日');
    expect(draft.exercises.length, 2);
    // 动作顺序保留
    expect(draft.exercises[0].exerciseId, benchId);
    expect(draft.exercises[1].exerciseId, lateralId);
    // 不复制任何组数据
    expect(draft.exercises[0].sets, isEmpty);
    expect(draft.exercises[1].sets, isEmpty);
    // 原训练不受影响
    final source = await workoutRepo.getDetail(sourceId);
    expect(source!.exercises[0].sets.length, 2);
  });

  test('「上次」参考：返回最近一次完成该动作的各组数据', () async {
    final benchId = await seededId('杠铃卧推');

    // 第一次训练（旧）
    await quickCompletedSession(
      name: '第一次',
      startTime: DateTime.now().subtract(const Duration(days: 7)),
      exercises: {
        benchId: [(60, 12), (70, 10)],
      },
    );
    // 第二次训练（最近）
    final latestId = await quickCompletedSession(
      name: '第二次',
      startTime: DateTime.now().subtract(const Duration(days: 1)),
      exercises: {
        benchId: [(75, 10), (80, 8)],
      },
    );

    // 进行中的新训练（exclude 传一个不存在的 id）：应参考最近一次（75 / 80）
    final refs = await workoutRepo.lastPerformanceMap(999999, [benchId]);
    expect(refs[benchId], isNotNull);
    expect(refs[benchId]!.length, 2);
    expect(refs[benchId]!.first.$1, 75);
    expect(refs[benchId]!.first.$2, 10);
    expect(refs[benchId]!.last.$1, 80);

    // 编辑第二次训练本身时，应参考它上一次（60 / 70）
    final refsExcludingSelf = await workoutRepo.lastPerformanceMap(latestId, [
      benchId,
    ]);
    expect(refsExcludingSelf[benchId]!.first.$1, 60);
    expect(refsExcludingSelf[benchId]!.first.$2, 12);
  });

  test('最近使用动作：按最近一次训练出现顺序去重返回', () async {
    final benchId = await seededId('杠铃卧推');
    final curlId = await seededId('哑铃弯举');
    final squatId = await seededId('深蹲');

    Future<void> quickSession(List<int> exerciseIds) async {
      final sessionId = await workoutRepo.createInProgressSession();
      await workoutRepo.saveDraftContent(
        sessionId,
        WorkoutDraft(
          sessionDbId: sessionId,
          isInProgress: true,
          startTime: DateTime.now(),
          exercises: [
            for (final id in exerciseIds)
              DraftExercise(
                exerciseId: id,
                name: '动作$id',
                muscleGroup: '胸',
                sets: [DraftSet(weight: 10, reps: 10)],
              ),
          ],
        ),
      );
      await workoutRepo.completeSession(
        sessionId,
        WorkoutDraft(
          sessionDbId: sessionId,
          isInProgress: true,
          startTime: DateTime.now(),
          exercises: [
            for (final id in exerciseIds)
              DraftExercise(
                exerciseId: id,
                name: '动作$id',
                muscleGroup: '胸',
                sets: [DraftSet(weight: 10, reps: 10)],
              ),
          ],
        ),
      );
    }

    await quickSession([benchId, curlId]);
    await quickSession([squatId, benchId]);

    final recent = await exerciseRepo.getRecentUsed(limit: 5);
    // 第二次训练中 bench 是最后插入的动作 → 最新使用
    expect(recent.map((e) => e.id).toList(), [benchId, squatId, curlId]);
  });
}
