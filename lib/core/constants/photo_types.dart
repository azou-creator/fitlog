/// 照片类型。数据库保存稳定字符串（不用 enum index），
/// 避免未来枚举顺序变化导致旧数据错乱（V1.2 设计约束）。
enum PhotoType {
  workout('workout', '训练照片'),
  bodyFront('body_front', '正面'),
  bodySide('body_side', '侧面'),
  bodyBack('body_back', '背面'),
  bodyOther('body_other', '其他');

  const PhotoType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static PhotoType fromDb(String value) => PhotoType.values.firstWhere(
    (t) => t.dbValue == value,
    orElse: () => PhotoType.bodyOther,
  );

  bool get isWorkout => this == workout;
  bool get isBody => !isWorkout;

  /// 身体照片在页面中的固定展示顺序（同一天：正面 → 侧面 → 背面 → 其他）。
  int get bodyOrder => switch (this) {
    bodyFront => 0,
    bodySide => 1,
    bodyBack => 2,
    bodyOther => 3,
    workout => 4,
  };
}

final bodyPhotoDbValues = [
  PhotoType.bodyFront.dbValue,
  PhotoType.bodySide.dbValue,
  PhotoType.bodyBack.dbValue,
  PhotoType.bodyOther.dbValue,
];
