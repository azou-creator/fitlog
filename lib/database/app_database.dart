import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Exercises,
    WorkoutSessions,
    WorkoutExercises,
    WorkoutSets,
    RunningRecords,
    Photos,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用：允许注入内存数据库。
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

  /// P0：数据库级保证「同一时间最多一个进行中的力量训练」。
  /// 使用 SQLite partial unique index；若老数据中已存在多个 inProgress
  /// （正常使用几乎不可能），为保护用户数据，跳过建索引并仅记录日志，
  /// 不变量由 Repository 层事务保证。
  static const _activeSessionIndexSql =
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_workout_sessions_active "
      "ON workout_sessions (status) WHERE status = 'inProgress'";

  Future<void> _createActiveSessionIndexSafely() async {
    try {
      await customStatement(_activeSessionIndexSql);
    } catch (e) {
      // ignore: avoid_print
      print('跳过进行中训练唯一索引（已存在多个 inProgress 数据，未做改动）: $e');
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createActiveSessionIndexSafely();
    },
    onUpgrade: (m, from, to) async {
      // v2: 增加 session status 字段（进行中草稿 / 已完成）。
      // 旧数据全部视为已完成。
      if (from < 2) {
        await m.addColumn(workoutSessions, workoutSessions.status);
      }
      // v3: 进行中训练的数据库级唯一约束。
      if (from < 3) {
        await _createActiveSessionIndexSafely();
      }
      // v4: 照片元数据表（训练照片 / 身体进度照片）。
      if (from < 4) {
        await m.createTable(photos);
        // createTable 不会自动创建 @TableIndex 声明的独立索引。
        await m.createIndex(idxPhotosSession);
      }
    },
    beforeOpen: (details) async {
      // 级联删除依赖外键约束，必须显式开启。
      await customStatement('PRAGMA foreign_keys = ON');
      // 修复早期 v4 增量实现中升级用户缺失的照片索引。
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_photos_session '
        'ON photos (workout_session_id)',
      );
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/fitlog.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}
