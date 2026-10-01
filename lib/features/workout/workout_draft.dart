import '../../core/utils/calc.dart';

/// 草稿对象本地自增 id，只用于列表 Key 稳定性，不落库。
int _idSeq = 0;
int _genId() {
  _idSeq += 1;
  return _idSeq;
}

/// 一组训练。
class DraftSet {
  DraftSet({int? id, required this.weight, this.reps}) : id = id ?? _genId();

  final int id;
  double weight;
  int? reps;

  /// reps 有效（>0）才算一条完整记录；weight 允许 0（自重动作）。
  bool get isValid => reps != null && reps! > 0;

  DraftSet copyWith({double? weight, int? reps}) =>
      DraftSet(id: id, weight: weight ?? this.weight, reps: reps ?? this.reps);
}

/// 训练中的一个动作（含其所有组）。
class DraftExercise {
  DraftExercise({
    int? id,
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    this.note = '',
    List<DraftSet>? sets,
  }) : id = id ?? _genId(),
       sets = sets ?? [];

  final int id;
  final int exerciseId;
  final String name;
  final String muscleGroup;
  String note;
  List<DraftSet> sets;

  DraftExercise copyWith({String? note, List<DraftSet>? sets}) => DraftExercise(
    id: id,
    exerciseId: exerciseId,
    name: name,
    muscleGroup: muscleGroup,
    note: note ?? this.note,
    sets: sets ?? this.sets,
  );
}

/// 一次力量训练草稿。
class WorkoutDraft {
  WorkoutDraft({
    this.sessionDbId,
    this.isInProgress = false,
    this.name = '',
    this.note = '',
    DateTime? startTime,
    List<DraftExercise>? exercises,
  }) : startTime = startTime ?? DateTime.now(),
       exercises = exercises ?? [];

  /// 已落库的进行中/被编辑 session 的 id；null 表示尚未落库（旧编辑路径）。
  final int? sessionDbId;

  /// true = 训练进行中（自动落库、实时计时、右上角完成）。
  final bool isInProgress;
  final DateTime startTime;
  String name;
  String note;
  List<DraftExercise> exercises;

  WorkoutDraft copyWith({
    String? name,
    String? note,
    List<DraftExercise>? exercises,
  }) => WorkoutDraft(
    sessionDbId: sessionDbId,
    isInProgress: isInProgress,
    name: name ?? this.name,
    note: note ?? this.note,
    startTime: startTime,
    exercises: exercises ?? this.exercises,
  );

  /// 是否有实质内容（用于返回前确认放弃）。
  bool get hasContent =>
      name.trim().isNotEmpty ||
      note.trim().isNotEmpty ||
      exercises.any((e) => e.sets.any((s) => s.isValid || s.weight != 0));

  /// 有效组数（reps > 0）。
  int get validSetCount =>
      exercises.fold(0, (n, e) => n + e.sets.where((s) => s.isValid).length);

  /// 是否至少有一条有效训练组。
  bool get hasValidSet => exercises.any((e) => e.sets.any((s) => s.isValid));

  /// 总训练容量（kg）。
  double get totalVolume => calcTotalVolume([
    for (final e in exercises)
      for (final s in e.sets)
        if (s.isValid) (weight: s.weight, reps: s.reps!),
  ]);
}
