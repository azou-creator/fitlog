import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/photo_types.dart';
import '../../database/app_database.dart' show Photo;
import '../../database/photo_repository.dart';

/// 训练照片流（详情页）。照片增删由 dataChangeProvider 驱动刷新亦可，
/// 这里直接 watch DB stream，保证多端一致。
final workoutPhotosProvider = StreamProvider.family<List<Photo>, int>((
  ref,
  workoutSessionId,
) {
  return ref
      .watch(photoRepositoryProvider)
      .watchWorkoutPhotos(workoutSessionId);
});

/// 身体照片直接订阅 DB，增删及恢复后刷新，错误交给页面展示。
final bodyPhotosProvider = StreamProvider<List<Photo>>((ref) {
  return ref.watch(photoRepositoryProvider).watchBodyPhotos();
});

/// 照片相关 UI 状态共享：viewer 传参使用。
typedef PhotoViewerArgs = ({List<Photo> photos, int initialIndex});

/// 类型选择结果（添加身体照片：先选类型）。
typedef BodyPhotoTypeSelection = PhotoType;
