import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'database_provider.dart';
import 'workout_repository.dart' show SessionStatus, WorkoutRepository;

/// 本地备份 / 恢复（V1.1）。
/// 导出为带 schemaVersion 的 JSON；导入为「完整覆盖恢复」（不做合并）。
class BackupRepository {
  BackupRepository(this._db);

  final AppDatabase _db;

  /// 导出文件的 schema 版本。未来字段变化时 +1，导入端据此兼容。
  static const int exportSchemaVersion = 1;

  String _iso(DateTime? d) => d?.toIso8601String() ?? '';
  DateTime _parseDate(dynamic v) => DateTime.parse(v as String);
  DateTime? _parseDateOrNull(dynamic v) =>
      (v == null || (v as String).isEmpty) ? null : DateTime.parse(v);

  Future<Map<String, dynamic>> exportToJson({String? themeMode}) async {
    final exercises = await (_db.select(
      _db.exercises,
    )..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
    final sessions = await WorkoutRepository(_db).getAllSessionsForExport();
    final wes = await (_db.select(
      _db.workoutExercises,
    )..orderBy([(u) => OrderingTerm.asc(u.id)])).get();
    final sets = await (_db.select(
      _db.workoutSets,
    )..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
    final runs = await (_db.select(
      _db.runningRecords,
    )..orderBy([(r) => OrderingTerm.asc(r.id)])).get();

    return {
      'schemaVersion': exportSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': {'themeMode': ?themeMode},
      'exercises': [
        for (final e in exercises)
          {
            'id': e.id,
            'name': e.name,
            'muscleGroup': e.muscleGroup,
            'isCustom': e.isCustom,
            'createdAt': _iso(e.createdAt),
          },
      ],
      'workoutSessions': [
        for (final s in sessions)
          {
            'id': s.id,
            'name': s.name,
            'startTime': _iso(s.startTime),
            'endTime': _iso(s.endTime),
            'durationSeconds': s.durationSeconds,
            'status': s.status,
            'note': s.note,
            'createdAt': _iso(s.createdAt),
            'updatedAt': _iso(s.updatedAt),
          },
      ],
      'workoutExercises': [
        for (final u in wes)
          {
            'id': u.id,
            'workoutSessionId': u.workoutSessionId,
            'exerciseId': u.exerciseId,
            'sortOrder': u.sortOrder,
            'note': u.note,
          },
      ],
      'workoutSets': [
        for (final s in sets)
          {
            'id': s.id,
            'workoutExerciseId': s.workoutExerciseId,
            'setOrder': s.setOrder,
            'weight': s.weight,
            'reps': s.reps,
            'rpe': s.rpe,
            'note': s.note,
            'createdAt': _iso(s.createdAt),
          },
      ],
      'runningRecords': [
        for (final r in runs)
          {
            'id': r.id,
            'date': _iso(r.date),
            'distanceKm': r.distanceKm,
            'durationSeconds': r.durationSeconds,
            'averageHeartRate': r.averageHeartRate,
            'note': r.note,
            'createdAt': _iso(r.createdAt),
            'updatedAt': _iso(r.updatedAt),
          },
      ],
    };
  }

  String encodePretty(Map<String, dynamic> json) =>
      const JsonEncoder.withIndent('  ').convert(json);

  Map<String, dynamic> decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份文件格式不正确');
    }
    return decoded;
  }

  /// 校验 schema 版本。过高（新版本导出的文件）则拒绝导入。
  void validateSchema(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version is! int || version > exportSchemaVersion) {
      throw const FormatException('备份文件来自更新版本的应用，请先升级 App 再导入');
    }
  }

  /// 完整恢复：清空现有数据后写入备份内容（在一个事务中，失败即整体回滚）。
  Future<void> importFromJson(Map<String, dynamic> json) async {
    validateSchema(json);
    final settings = json['settings'];
    final themeMode = settings is Map ? settings['themeMode'] as String? : null;

    await _db.transaction(() async {
      await _db.delete(_db.workoutSets).go();
      await _db.delete(_db.workoutExercises).go();
      await _db.delete(_db.workoutSessions).go();
      await _db.delete(_db.runningRecords).go();
      await _db.delete(_db.exercises).go();

      for (final raw in (json['exercises'] as List? ?? [])) {
        final e = raw as Map<String, dynamic>;
        await _db
            .into(_db.exercises)
            .insert(
              ExercisesCompanion.insert(
                id: Value(e['id'] as int),
                name: e['name'] as String,
                muscleGroup: e['muscleGroup'] as String,
                isCustom: Value(e['isCustom'] as bool? ?? false),
                createdAt: Value(
                  _parseDateOrNull(e['createdAt']) ?? DateTime.now(),
                ),
              ),
            );
      }

      // P0 唯一约束兜底：合法备份至多一个 inProgress；异常/手改的备份若含
      // 多个，保留最新一场，其余降级为 completed，避免导入被唯一索引拒绝。
      final sessionList = (json['workoutSessions'] as List? ?? []);
      final activeEntries =
          sessionList
              .whereType<Map<String, dynamic>>()
              .where(
                (s) => (s['status'] as String?) == SessionStatus.inProgress,
              )
              .toList()
            ..sort(
              (a, b) =>
                  _parseDate(b['startTime'])
                      .compareTo(_parseDate(a['startTime'])),
            );
      final demotedIds = {
        for (final s in activeEntries.skip(1)) s['id'] as int,
      };
      if (demotedIds.isNotEmpty) {
        // ignore: avoid_print
        print('备份包含多个进行中训练，已将 ${demotedIds.length} 场旧记录标记为已完成');
      }

      for (final raw in sessionList) {
        final s = raw as Map<String, dynamic>;
        final requestedStatus =
            (s['status'] as String?) ?? SessionStatus.completed;
        await _db
            .into(_db.workoutSessions)
            .insert(
              WorkoutSessionsCompanion.insert(
                id: Value(s['id'] as int),
                name: s['name'] as String,
                startTime: _parseDate(s['startTime']),
                endTime: Value(_parseDateOrNull(s['endTime'])),
                durationSeconds: s['durationSeconds'] as int? ?? 0,
                status: Value(
                  demotedIds.contains(s['id'])
                      ? SessionStatus.completed
                      : requestedStatus,
                ),
                note: Value(s['note'] as String?),
                createdAt: Value(
                  _parseDateOrNull(s['createdAt']) ?? DateTime.now(),
                ),
                updatedAt: Value(
                  _parseDateOrNull(s['updatedAt']) ?? DateTime.now(),
                ),
              ),
            );
      }

      for (final raw in (json['workoutExercises'] as List? ?? [])) {
        final u = raw as Map<String, dynamic>;
        await _db
            .into(_db.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                id: Value(u['id'] as int),
                workoutSessionId: u['workoutSessionId'] as int,
                exerciseId: u['exerciseId'] as int,
                sortOrder: u['sortOrder'] as int? ?? 0,
                note: Value(u['note'] as String?),
              ),
            );
      }

      for (final raw in (json['workoutSets'] as List? ?? [])) {
        final s = raw as Map<String, dynamic>;
        await _db
            .into(_db.workoutSets)
            .insert(
              WorkoutSetsCompanion.insert(
                id: Value(s['id'] as int),
                workoutExerciseId: s['workoutExerciseId'] as int,
                setOrder: s['setOrder'] as int? ?? 0,
                weight: (s['weight'] as num?)?.toDouble() ?? 0,
                reps: s['reps'] as int? ?? 0,
                rpe: Value((s['rpe'] as num?)?.toDouble()),
                note: Value(s['note'] as String?),
                createdAt: Value(
                  _parseDateOrNull(s['createdAt']) ?? DateTime.now(),
                ),
              ),
            );
      }

      for (final raw in (json['runningRecords'] as List? ?? [])) {
        final r = raw as Map<String, dynamic>;
        await _db
            .into(_db.runningRecords)
            .insert(
              RunningRecordsCompanion.insert(
                id: Value(r['id'] as int),
                date: _parseDate(r['date']),
                distanceKm: (r['distanceKm'] as num?)?.toDouble() ?? 0,
                durationSeconds: r['durationSeconds'] as int? ?? 0,
                averageHeartRate: Value(r['averageHeartRate'] as int?),
                note: Value(r['note'] as String?),
                createdAt: Value(
                  _parseDateOrNull(r['createdAt']) ?? DateTime.now(),
                ),
                updatedAt: Value(
                  _parseDateOrNull(r['updatedAt']) ?? DateTime.now(),
                ),
              ),
            );
      }
    });

    if (themeMode != null) {
      _onThemeRestored?.call(themeMode);
    }
  }

  /// 导入完成后恢复外观设置用（由 UI 注入，避免 backup 依赖 UI 层）。
  void Function(String themeMode)? _onThemeRestored;
  set onThemeRestored(void Function(String) callback) =>
      _onThemeRestored = callback;
}

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => BackupRepository(ref.watch(appDatabaseProvider)),
);
