import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Exercises, WorkoutSessions, WorkoutExercises, WorkoutSets, RunningRecords],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用：允许注入内存数据库。
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v2: 增加 session status 字段（进行中草稿 / 已完成）。
          // 旧数据全部视为已完成。
          if (from < 2) {
            await m.addColumn(workoutSessions, workoutSessions.status);
          }
        },
        beforeOpen: (details) async {
          // 级联删除依赖外键约束，必须显式开启。
          await customStatement('PRAGMA foreign_keys = ON');
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
