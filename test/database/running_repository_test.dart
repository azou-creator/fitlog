import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/running_repository.dart';

void main() {
  late AppDatabase db;
  late RunningRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RunningRepository(db);
  });

  tearDown(() => db.close());

  test('保存跑步记录：心率与备注可空', () async {
    final id = await repo.save(
      date: DateTime(2026, 9, 28),
      distanceKm: 5.2,
      durationSeconds: 28 * 60 + 32,
    );
    final record = await repo.getById(id);
    expect(record, isNotNull);
    expect(record!.distanceKm, 5.2);
    expect(record.durationSeconds, 28 * 60 + 32);
    expect(record.averageHeartRate, isNull);
    expect(record.note, isNull);
  });

  test('更新跑步记录', () async {
    final id = await repo.save(
      date: DateTime(2026, 9, 28),
      distanceKm: 5.0,
      durationSeconds: 1800,
    );
    await repo.update(
      id,
      date: DateTime(2026, 9, 29),
      distanceKm: 10.0,
      durationSeconds: 3600,
      averageHeartRate: 152,
      note: '周末长距离',
    );
    final record = await repo.getById(id);
    expect(record!.distanceKm, 10.0);
    expect(record.averageHeartRate, 152);
    expect(record.note, '周末长距离');
  });

  test('删除跑步记录', () async {
    final id = await repo.save(
      date: DateTime(2026, 9, 28),
      distanceKm: 5.0,
      durationSeconds: 1800,
    );
    await repo.delete(id);
    expect(await repo.getById(id), isNull);
  });

  test('getBetween：按日期区间查询', () async {
    await repo.save(
        date: DateTime(2026, 9, 1), distanceKm: 3, durationSeconds: 1000);
    await repo.save(
        date: DateTime(2026, 9, 15), distanceKm: 5, durationSeconds: 1700);
    await repo.save(
        date: DateTime(2026, 10, 1), distanceKm: 8, durationSeconds: 2800);

    final sep = await repo.getBetween(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
    expect(sep.length, 2);
    expect(sep.map((r) => r.distanceKm), [3, 5]); // 按日期升序
  });
}
