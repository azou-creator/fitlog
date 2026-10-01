import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/backup_repository.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/database/running_repository.dart';
import 'package:fitlog/database/workout_repository.dart';
import 'package:fitlog/features/workout/workout_draft.dart';

/// 备份/恢复基础测试：导出 JSON → 导入到全新数据库 → 数据一致。
void main() {
  late AppDatabase sourceDb;
  late AppDatabase targetDb;
  late BackupRepository sourceBackup;
  late BackupRepository targetBackup;

  setUp(() async {
    sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
    targetDb = AppDatabase.forTesting(NativeDatabase.memory());
    sourceBackup = BackupRepository(sourceDb);
    targetBackup = BackupRepository(targetDb);
    await ExerciseRepository(sourceDb).ensureSeeded();
  });

  tearDown(() async {
    await sourceDb.close();
    await targetDb.close();
  });

  test('导出 → 导入后数据一致', () async {
    final all = await ExerciseRepository(sourceDb).getAll();
    final benchId = all.firstWhere((e) => e.name == '杠铃卧推').id;

    // 一场已完成的力量训练
    final sessionId = await WorkoutRepository(sourceDb).createInProgressSession(
      name: '胸 + 肩',
      startTime: DateTime(2026, 10, 1, 18, 0),
    );
    final draft = WorkoutDraft(
      sessionDbId: sessionId,
      isInProgress: true,
      name: '胸 + 肩',
      startTime: DateTime(2026, 10, 1, 18, 0),
      note: '状态好',
      exercises: [
        DraftExercise(
          exerciseId: benchId,
          name: '杠铃卧推',
          muscleGroup: '胸',
          sets: [
            DraftSet(weight: 60, reps: 12),
            DraftSet(weight: 80, reps: 10),
          ],
        ),
      ],
    );
    await WorkoutRepository(sourceDb).saveDraftContent(sessionId, draft);
    await WorkoutRepository(sourceDb).completeSession(sessionId, draft);

    // 一条跑步记录
    await RunningRepository(sourceDb).save(
      date: DateTime(2026, 10, 2),
      distanceKm: 5.2,
      durationSeconds: 28 * 60 + 32,
      averageHeartRate: 152,
      note: '状态不错',
    );

    // 导出 → 字符串 → 解析 → 导入
    final json = await sourceBackup.exportToJson(themeMode: 'dark');
    final raw = sourceBackup.encodePretty(json);
    final restored = targetBackup.decode(raw);
    await targetBackup.importFromJson(restored);

    // 数据库层面对比
    final srcSessions = await sourceDb.select(sourceDb.workoutSessions).get();
    final dstSessions = await targetDb.select(targetDb.workoutSessions).get();
    expect(dstSessions.length, srcSessions.length);
    expect(dstSessions.first.name, '胸 + 肩');
    expect(dstSessions.first.status, SessionStatus.completed);

    final srcSets = await sourceDb.select(sourceDb.workoutSets).get();
    final dstSets = await targetDb.select(targetDb.workoutSets).get();
    expect(dstSets.length, srcSets.length);
    expect(dstSets.map((s) => s.weight), srcSets.map((s) => s.weight));
    expect(dstSets.map((s) => s.reps), srcSets.map((s) => s.reps));

    final srcRuns = await sourceDb.select(sourceDb.runningRecords).get();
    final dstRuns = await targetDb.select(targetDb.runningRecords).get();
    expect(dstRuns.length, 1);
    expect(dstRuns.length, srcRuns.length);
    expect(dstRuns.first.distanceKm, 5.2);
    expect(dstRuns.first.averageHeartRate, 152);

    final srcEx = await sourceDb.select(sourceDb.exercises).get();
    final dstEx = await targetDb.select(targetDb.exercises).get();
    expect(dstEx.length, srcEx.length);

    // schemaVersion 存在
    expect(json['schemaVersion'], BackupRepository.exportSchemaVersion);
    expect(jsonDecode(raw), isA<Map<String, dynamic>>());
  });

  test('schema 版本过高时拒绝导入', () async {
    await expectLater(
      targetBackup.importFromJson({'schemaVersion': 999}),
      throwsFormatException,
    );
  });

  test('损坏的 JSON 抛出 FormatException', () {
    expect(() => targetBackup.decode('not a json {'), throwsFormatException);
  });
}
