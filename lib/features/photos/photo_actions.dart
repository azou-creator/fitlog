import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/photo_types.dart';
import '../../core/storage/photo_storage_service.dart';
import '../../database/photo_repository.dart';
import 'widgets/add_photo_sheet.dart';

class PhotoActionException implements Exception {
  const PhotoActionException(this.message);
  final String message;
}

/// 页面只持有添加状态；picker 与文件释放由此协调，离开页面后仍可安全完成保存。
class PhotoActions {
  PhotoActions(this._repository, this._storage, this._picker);

  final PhotoRepository _repository;
  final PhotoStorageService _storage;
  final ImagePicker _picker;

  Future<({int saved, int failed})> addPhotos({
    required PhotoSource source,
    required PhotoType type,
    int? workoutSessionId,
  }) async {
    final List<XFile> picked;
    try {
      if (source == PhotoSource.camera) {
        final file = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
          requestFullMetadata: false,
        );
        picked = [?file];
      } else {
        picked = await _picker.pickMultiImage(
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
          requestFullMetadata: false,
        );
      }
    } on PlatformException catch (e) {
      debugPrint('照片选择失败: ${e.code}');
      final denied =
          e.code.contains('denied') ||
          e.code.contains('restricted') ||
          e.code.contains('access');
      throw PhotoActionException(
        denied
            ? source == PhotoSource.camera
                  ? '无法访问相机，请在系统设置中允许 Fitlog 使用相机。'
                  : '无法访问照片，请在系统设置中允许 Fitlog 访问照片图库。'
            : source == PhotoSource.camera
            ? '无法使用相机，请重试或从照片图库选择。'
            : '照片选择失败，请重新选择。',
      );
    } catch (e) {
      debugPrint('照片选择失败: $e');
      throw const PhotoActionException('照片选择失败，请重新选择。');
    }

    var saved = 0;
    var failed = 0;
    for (final file in picked) {
      try {
        await _repository.addPhoto(
          type: type,
          workoutSessionId: workoutSessionId,
          tempPath: file.path,
        );
        saved++;
      } catch (e) {
        failed++;
        debugPrint('照片保存失败: $e');
      } finally {
        await _storage.releasePickedFile(file.path);
      }
    }
    return (saved: saved, failed: failed);
  }
}

final photoActionsProvider = Provider<PhotoActions>(
  (ref) => PhotoActions(
    ref.watch(photoRepositoryProvider),
    ref.watch(photoStorageServiceProvider),
    ImagePicker(),
  ),
);
