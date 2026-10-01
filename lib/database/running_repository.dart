import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'database_provider.dart';

class RunningRepository {
  RunningRepository(this._db);

  final AppDatabase _db;

  Future<int> save({
    required DateTime date,
    required double distanceKm,
    required int durationSeconds,
    int? averageHeartRate,
    String? note,
  }) {
    return _db
        .into(_db.runningRecords)
        .insert(
          RunningRecordsCompanion.insert(
            date: date,
            distanceKm: distanceKm,
            durationSeconds: durationSeconds,
            averageHeartRate: Value(averageHeartRate),
            note: Value(_clean(note)),
          ),
        );
  }

  Future<void> update(
    int id, {
    required DateTime date,
    required double distanceKm,
    required int durationSeconds,
    int? averageHeartRate,
    String? note,
  }) {
    return (_db.update(
      _db.runningRecords,
    )..where((r) => r.id.equals(id))).write(
      RunningRecordsCompanion(
        date: Value(date),
        distanceKm: Value(distanceKm),
        durationSeconds: Value(durationSeconds),
        averageHeartRate: Value(averageHeartRate),
        note: Value(_clean(note)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> delete(int id) {
    return (_db.delete(_db.runningRecords)..where((r) => r.id.equals(id))).go();
  }

  Future<RunningRecord?> getById(int id) {
    return (_db.select(
      _db.runningRecords,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  Future<List<RunningRecord>> getAll() {
    return (_db.select(
      _db.runningRecords,
    )..orderBy([(r) => OrderingTerm.desc(r.date)])).get();
  }

  Stream<List<RunningRecord>> watchAll() {
    return (_db.select(
      _db.runningRecords,
    )..orderBy([(r) => OrderingTerm.desc(r.date)])).watch();
  }

  /// 某时间区间内的跑步记录（含头含尾），用于统计。
  Future<List<RunningRecord>> getBetween(DateTime start, DateTime end) {
    return (_db.select(_db.runningRecords)
          ..where(
            (r) =>
                r.date.isBiggerOrEqualValue(start) &
                r.date.isSmallerOrEqualValue(end),
          )
          ..orderBy([(r) => OrderingTerm.asc(r.date)]))
        .get();
  }

  String? _clean(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }
}

final runningRepositoryProvider = Provider<RunningRepository>(
  (ref) => RunningRepository(ref.watch(appDatabaseProvider)),
);
