import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/core/constants/photo_types.dart';
import 'package:fitlog/core/storage/photo_storage_service.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/photo_repository.dart';
import 'package:fitlog/features/photos/photo_actions.dart';
import 'package:fitlog/features/photos/widgets/add_photo_sheet.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late Directory picked;
  late PhotoStorageService storage;
  late PhotoRepository repository;
  late _Picker picker;
  late PhotoActions actions;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('fitlog_actions');
    picked = await Directory.systemTemp.createTemp('fitlog_picked');
    storage = PhotoStorageService(root);
    repository = PhotoRepository(db, storage);
    picker = _Picker();
    actions = PhotoActions(repository, storage, picker);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
    await picked.delete(recursive: true);
  });

  test('取消图库或相机均没有保存副作用', () async {
    for (final source in PhotoSource.values) {
      expect(
        await actions.addPhotos(source: source, type: PhotoType.bodyFront),
        (saved: 0, failed: 0),
      );
    }
    expect(await repository.photoCount(), 0);
    expect(await storage.listAllRelativePaths(), isEmpty);
  });

  test('相机和图库权限拒绝显示对应中文说明', () async {
    picker.error = PlatformException(code: 'camera_access_denied');
    await expectLater(
      actions.addPhotos(source: PhotoSource.camera, type: PhotoType.bodyFront),
      throwsA(
        isA<PhotoActionException>().having(
          (e) => e.message,
          'message',
          contains('允许 Fitlog 使用相机'),
        ),
      ),
    );
    picker.error = PlatformException(code: 'photo_access_denied');
    await expectLater(
      actions.addPhotos(source: PhotoSource.gallery, type: PhotoType.bodyFront),
      throwsA(
        isA<PhotoActionException>().having(
          (e) => e.message,
          'message',
          contains('访问照片图库'),
        ),
      ),
    );
  });

  test('多选部分失败保留成功记录，并释放全部 picker 临时文件', () async {
    final valid = File('${picked.path}/valid.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 80, height: 120)));
    final invalid = File('${picked.path}/invalid.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    picker.files = [XFile(valid.path), XFile(invalid.path)];
    final result = await actions.addPhotos(
      source: PhotoSource.gallery,
      type: PhotoType.bodyOther,
    );
    expect(result, (saved: 1, failed: 1));
    expect(await valid.exists(), isFalse);
    expect(await invalid.exists(), isFalse);
    expect(await repository.photoCount(), 1);
    expect(await storage.listAllRelativePaths(), hasLength(2));
    expect(picker.fullMetadataRequested, isFalse);
  });
}

class _Picker extends ImagePicker {
  List<XFile> files = [];
  PlatformException? error;
  bool? fullMetadataRequested;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    fullMetadataRequested = requestFullMetadata;
    if (error != null) throw error!;
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    fullMetadataRequested = requestFullMetadata;
    if (error != null) throw error!;
    return files;
  }
}
