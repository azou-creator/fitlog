import 'package:drift/drift.dart';

/// 动作库：系统内置动作 + 用户自定义动作。
class Exercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get muscleGroup => text().withLength(min: 1, max: 20)();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 一次力量训练（一次训练 = 一个 session）。
/// status: inProgress（进行中草稿，支持意外退出恢复）/ completed（已完成）。
class WorkoutSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  IntColumn get durationSeconds => integer()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 一次训练中包含的动作（排序用 sortOrder）。
@TableIndex(name: 'idx_we_session', columns: {#workoutSessionId})
class WorkoutExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workoutSessionId =>
      integer().references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer().references(Exercises, #id)();
  IntColumn get sortOrder => integer()();
  TextColumn get note => text().nullable()();
}

/// 某个动作下的训练组。rpe / note 预留，UI 第一阶段不展示。
@TableIndex(name: 'idx_sets_exercise', columns: {#workoutExerciseId})
class WorkoutSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workoutExerciseId => integer().references(
    WorkoutExercises,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get setOrder => integer()();
  RealColumn get weight => real()();
  IntColumn get reps => integer()();
  RealColumn get rpe => real().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// 跑步记录。平均配速不落库，用时/距离动态计算。
class RunningRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  RealColumn get distanceKm => real()();
  IntColumn get durationSeconds => integer()();
  IntColumn get averageHeartRate => integer().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// 照片元数据（v4）。文件本体存在 App 私有媒体目录，DB 只存相对路径。
///
/// photoType 使用稳定字符串（workout / body_front / body_side / body_back /
/// body_other），不用 enum index，避免未来枚举顺序变化导致旧数据错乱。
/// - 训练照片：photoType = 'workout' 且 workoutSessionId != null
/// - 身体照片：photoType = body_* 且 workoutSessionId == null
@TableIndex(name: 'idx_photos_session', columns: {#workoutSessionId})
class Photos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workoutSessionId => integer().nullable().references(
    WorkoutSessions,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get photoType => text().withLength(min: 1, max: 20)();
  TextColumn get relativePath => text()();
  TextColumn get thumbnailRelativePath => text().nullable()();
  DateTimeColumn get takenAt => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
