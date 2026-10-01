import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/database/workout_repository.dart';
import 'package:fitlog/features/workout/workout_draft.dart';
import 'package:sqlite3/sqlite3.dart';

/// Migration 测试：v3 → v4（新增 photos 表）。
///
/// 方法（最接近真实条件）：
/// 1. 在临时文件上以 v4 正常建库 → 插入旧数据
/// 2. 用 sqlite3 直连模拟旧版本：DROP photos 表 + user_version 回退到 3
/// 3. 重新以 AppDatabase 打开 → drift 执行 v3→v4 迁移（createTable photos）
/// 4. 验证：旧数据 100% 完整、photos 表存在
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fitlog_migration_test');
    dbFile = File('${tempDir.path}/fitlog.sqlite');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('真实 v2 表结构 → v4：训练、动作、组、跑步及旧 ID 保留', () async {
    final raw = sqlite3.open(dbFile.path);
    // 独立旧版 DDL，避免用新版本建库掩盖 migration 的遗漏。
    raw.execute('''
      CREATE TABLE exercises (id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, muscle_group TEXT NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE workout_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, start_time INTEGER NOT NULL, end_time INTEGER,
        duration_seconds INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'completed',
        note TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE workout_exercises (id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_session_id INTEGER NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
        exercise_id INTEGER NOT NULL REFERENCES exercises(id), sort_order INTEGER NOT NULL, note TEXT);
      CREATE TABLE workout_sets (id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_exercise_id INTEGER NOT NULL REFERENCES workout_exercises(id) ON DELETE CASCADE,
        set_order INTEGER NOT NULL, weight REAL NOT NULL, reps INTEGER NOT NULL,
        rpe REAL, note TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE running_records (id INTEGER PRIMARY KEY AUTOINCREMENT,
        date INTEGER NOT NULL, distance_km REAL NOT NULL, duration_seconds INTEGER NOT NULL,
        average_heart_rate INTEGER, note TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE INDEX idx_we_session ON workout_exercises(workout_session_id);
      CREATE INDEX idx_sets_exercise ON workout_sets(workout_exercise_id);
      INSERT INTO exercises VALUES (41, '旧动作', '胸', 1, 1700000000);
      INSERT INTO workout_sessions VALUES (51, '旧训练', 1700000000, 1700003600,
        3600, 'completed', '保留备注', 1700000000, 1700003600);
      INSERT INTO workout_exercises VALUES (61, 51, 41, 0, '动作备注');
      INSERT INTO workout_sets VALUES (71, 61, 0, 62.5, 12, 8, '组备注', 1700000000);
      INSERT INTO running_records VALUES (81, 1700000000, 5.2, 1712, 140,
        '跑步备注', 1700000000, 1700000000);
      PRAGMA user_version = 2;
    ''');
    raw.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
    try {
      final detail = (await WorkoutRepository(migrated).getDetail(51))!;
      expect(detail.session.note, '保留备注');
      expect(detail.exercises.single.exercise.id, 41);
      expect(detail.exercises.single.sets.single.id, 71);
      expect(detail.exercises.single.sets.single.weight, 62.5);
      expect(detail.exercises.single.sets.single.reps, 12);
      final run = await migrated.select(migrated.runningRecords).getSingle();
      expect(run.id, 81);
      expect(run.distanceKm, 5.2);
      expect(run.averageHeartRate, 140);
      expect(await migrated.select(migrated.photos).get(), isEmpty);
      final index = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'idx_workout_sessions_active'",
          )
          .get();
      expect(index, hasLength(1));
      final photoIndex = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'idx_photos_session'",
          )
          .get();
      expect(photoIndex, hasLength(1));
    } finally {
      await migrated.close();
    }
  });

  test('v3 → v4：旧数据完整保留，photos 表正确创建', () async {
    // ===== 1. 以 v4 打开一次（建全部表），写入旧版本时代的数据 =====
    final setup = AppDatabase.forTesting(NativeDatabase(dbFile));
    await ExerciseRepository(setup).ensureSeeded();
    final workoutRepo = WorkoutRepository(setup);
    final sessionId = await workoutRepo.createInProgressSession(name: '练胸');
    final bench = await (setup.select(
      setup.exercises,
    )..where((e) => e.name.equals('杠铃卧推'))).getSingle();
    final draft = WorkoutDraft(
      sessionDbId: sessionId,
      isInProgress: true,
      name: '练胸',
      startTime: DateTime(2026, 9, 1, 18),
      exercises: [
        DraftExercise(
          exerciseId: bench.id,
          name: bench.name,
          muscleGroup: bench.muscleGroup,
          sets: [
            DraftSet(weight: 60, reps: 12),
            DraftSet(weight: 80, reps: 10),
          ],
        ),
      ],
    );
    await workoutRepo.saveDraftContent(sessionId, draft);
    await workoutRepo.completeSession(sessionId, draft);
    final runId = await setup
        .into(setup.runningRecords)
        .insert(
          RunningRecordsCompanion.insert(
            date: DateTime(2026, 9, 2),
            distanceKm: 5.2,
            durationSeconds: 28 * 60 + 32,
          ),
        );
    await setup.close();

    // ===== 2. 模拟 v3：删 photos 表 + 回退 user_version =====
    final raw = sqlite3.open(dbFile.path);
    raw.execute('DROP TABLE photos');
    raw.execute('PRAGMA user_version = 3');
    expect(raw.select('PRAGMA user_version').first['user_version'], 3);
    raw.close();

    // ===== 3. 重新打开 → drift 执行 v3→v4 迁移 =====
    final migrated = AppDatabase.forTesting(NativeDatabase(dbFile));
    expect(migrated.schemaVersion, 4);

    // photos 表存在（能查询、能写入）
    final photosBefore = await migrated.select(migrated.photos).get();
    expect(photosBefore, isEmpty);
    final photoIndex = await migrated
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'idx_photos_session'",
        )
        .get();
    expect(photoIndex, hasLength(1));
    final newPhotoId = await migrated
        .into(migrated.photos)
        .insert(
          PhotosCompanion.insert(
            workoutSessionId: Value(sessionId),
            photoType: 'workout',
            relativePath: 'photos/2026/10/migration_test.jpg',
            takenAt: DateTime.now(),
          ),
        );
    expect(newPhotoId, greaterThan(0));

    // ===== 4. 旧数据 100% 完整 =====
    final detail = await WorkoutRepository(migrated).getDetail(sessionId);
    expect(detail, isNotNull);
    expect(detail!.session.name, '练胸');
    expect(detail.session.status, SessionStatus.completed);
    expect(detail.exercises.first.sets.length, 2);
    expect(detail.exercises.first.sets[0].weight, 60);
    expect(detail.exercises.first.sets[1].weight, 80);

    final run = await (migrated.select(
      migrated.runningRecords,
    )..where((r) => r.id.equals(runId))).getSingle();
    expect(run.distanceKm, 5.2);
    expect(run.durationSeconds, 28 * 60 + 32);

    final exercises = await migrated.select(migrated.exercises).get();
    expect(exercises, isNotEmpty);

    await migrated.close();
  });

  test('已有 v4 用户缺失照片索引时自动修复，不改动照片记录', () async {
    final setup = AppDatabase.forTesting(NativeDatabase(dbFile));
    await setup
        .into(setup.photos)
        .insert(
          PhotosCompanion.insert(
            photoType: 'body_front',
            relativePath: 'photos/existing.jpg',
            takenAt: DateTime(2026, 10, 1),
          ),
        );
    await setup.close();
    final raw = sqlite3.open(dbFile.path);
    raw.execute('DROP INDEX idx_photos_session');
    raw.close();
    final reopened = AppDatabase.forTesting(NativeDatabase(dbFile));
    try {
      expect(
        (await reopened.select(reopened.photos).getSingle()).relativePath,
        'photos/existing.jpg',
      );
      final index = await reopened
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'idx_photos_session'",
          )
          .get();
      expect(index, hasLength(1));
    } finally {
      await reopened.close();
    }
  });

  test('v4 全新安装：photos 表直接存在（onCreate 路径）', () async {
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    expect(db.schemaVersion, 4);
    // photos 表可查询
    final photos = await db.select(db.photos).get();
    expect(photos, isEmpty);
    // 与 photos 相关的索引存在
    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
          variables: [Variable.withString('idx_photos_session')],
        )
        .get();
    expect(indexes, hasLength(1));
    await db.close();
  });
}
