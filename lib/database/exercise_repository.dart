import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'database_provider.dart';
import 'seed_exercises.dart';

class ExerciseRepository {
  ExerciseRepository(this._db);

  final AppDatabase _db;

  /// 首次启动插入内置动作库。幂等：按「部位|名称」去重，重复启动不会重复插入。
  Future<void> ensureSeeded() async {
    final existing = await _db.select(_db.exercises).get();
    final keys = existing.map((e) => '${e.muscleGroup}|${e.name}').toSet();

    final missing = <ExercisesCompanion>[];
    seedExercises.forEach((group, names) {
      for (final name in names) {
        final key = '$group|$name';
        if (!keys.contains(key)) {
          missing.add(
            ExercisesCompanion.insert(name: name, muscleGroup: group),
          );
        }
      }
    });
    if (missing.isEmpty) return;
    await _db.batch((b) => b.insertAll(_db.exercises, missing));
  }

  Future<List<Exercise>> getAll() {
    return (_db.select(
      _db.exercises,
    )..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
  }

  Stream<List<Exercise>> watchAll() {
    return (_db.select(
      _db.exercises,
    )..orderBy([(e) => OrderingTerm.asc(e.id)])).watch();
  }

  Future<Exercise?> getById(int id) {
    return (_db.select(
      _db.exercises,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  /// 创建自定义动作。同名同部位已存在时直接返回已有 id（避免重复）。
  Future<int> createCustom({
    required String name,
    required String muscleGroup,
  }) async {
    final trimmed = name.trim();
    final dup =
        await (_db.select(_db.exercises)..where(
              (e) => e.name.equals(trimmed) & e.muscleGroup.equals(muscleGroup),
            ))
            .getSingleOrNull();
    if (dup != null) return dup.id;

    return _db
        .into(_db.exercises)
        .insert(
          ExercisesCompanion.insert(
            name: trimmed,
            muscleGroup: muscleGroup,
            isCustom: const Value(true),
          ),
        );
  }

  Future<List<Exercise>> getByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    return (_db.select(_db.exercises)..where((e) => e.id.isIn(ids))).get();
  }

  /// 最近使用过的动作（按最近一次训练出现顺序，去重）。
  Future<List<Exercise>> getRecentUsed({int limit = 12}) async {
    final rows = await (_db.select(
      _db.workoutExercises,
    )..orderBy([(u) => OrderingTerm.desc(u.id)])).get();

    final seen = <int>{};
    final orderedIds = <int>[];
    for (final r in rows) {
      if (seen.add(r.exerciseId)) {
        orderedIds.add(r.exerciseId);
        if (orderedIds.length >= limit) break;
      }
    }
    if (orderedIds.isEmpty) return [];

    final byId = {for (final e in await getByIds(orderedIds)) e.id: e};
    return [
      for (final id in orderedIds)
        if (byId[id] != null) byId[id]!,
    ];
  }
}

final exerciseRepositoryProvider = Provider<ExerciseRepository>(
  (ref) => ExerciseRepository(ref.watch(appDatabaseProvider)),
);
