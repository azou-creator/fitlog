import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/core/constants/photo_types.dart';
import 'package:fitlog/core/storage/photo_storage_service.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/database/photo_repository.dart';
import 'package:fitlog/database/workout_repository.dart';
import 'package:fitlog/features/workout/workout_draft.dart';
import 'package:image/image.dart' as img;

/// PhotoRepository 测试：内存 DB + 真实临时媒体目录 + 真实 JPEG 文件。
void main() {
  late AppDatabase db;
  late Directory mediaRoot;
  late Directory tempPickDir;
  late PhotoStorageService storage;
  late PhotoRepository photoRepo;
  late WorkoutRepository workoutRepo;

  /// 生成真实的小 JPEG 文件（120×80）。
  File makeJpeg(String name) {
    final image = img.Image(width: 120, height: 80);
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 119,
      y2: 79,
      color: img.ColorRgb8(20, 90, 180),
    );
    final bytes = img.encodeJpg(image, quality: 90);
    return File('${tempPickDir.path}/$name')..writeAsBytesSync(bytes);
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mediaRoot = await Directory.systemTemp.createTemp('fitlog_photo_repo');
    tempPickDir = await Directory.systemTemp.createTemp('fitlog_pick');
    storage = PhotoStorageService(mediaRoot);
    photoRepo = PhotoRepository(db, storage);
    workoutRepo = WorkoutRepository(db, storage);
    await ExerciseRepository(db).ensureSeeded();
  });

  tearDown(() async {
    await db.close();
    await mediaRoot.delete(recursive: true);
    await tempPickDir.delete(recursive: true);
  });

  /// 建一场已完成的训练，返回 session id。
  Future<int> completedSession(String name) async {
    final sessionId = await workoutRepo.createInProgressSession(name: name);
    await workoutRepo.completeSession(
      sessionId,
      WorkoutDraft(
        sessionDbId: sessionId,
        isInProgress: true,
        name: name,
        startTime: DateTime.now(),
        exercises: const [],
      ),
    );
    return sessionId;
  }

  group('训练照片', () {
    test('add → 按 session 查询 → delete（DB 与文件同步清理）', () async {
      final sessionId = await completedSession('练胸');
      final temp = makeJpeg('w1.jpg');

      final photo = await photoRepo.addWorkoutPhoto(
        workoutSessionId: sessionId,
        tempPath: temp.path,
        note: '充血不错',
      );

      expect(photo.photoType, PhotoType.workout.dbValue);
      expect(photo.workoutSessionId, sessionId);
      expect(photo.relativePath.startsWith('photos/'), isTrue);
      expect(photo.thumbnailRelativePath, isNotNull);
      // 不含临时文件名、不含绝对路径
      expect(photo.relativePath.contains('w1.jpg'), isFalse);
      expect(photo.relativePath.contains(mediaRoot.path), isFalse);

      // 文件真实存在
      expect(await storage.exists(photo.relativePath), isTrue);
      expect(await storage.exists(photo.thumbnailRelativePath!), isTrue);

      // 按 session 查询
      final list = await photoRepo.getWorkoutPhotos(sessionId);
      expect(list.length, 1);

      // 删除：DB 记录 + 两个文件都没了
      await photoRepo.deletePhoto(photo);
      expect(await photoRepo.getWorkoutPhotos(sessionId), isEmpty);
      expect(await storage.exists(photo.relativePath), isFalse);
      expect(await storage.exists(photo.thumbnailRelativePath!), isFalse);
    });

    test('添加多张：按添加顺序稳定返回', () async {
      final sessionId = await completedSession('练背');
      final ids = <int>[];
      for (var i = 0; i < 3; i++) {
        final temp = makeJpeg('w$i.jpg');
        final p = await photoRepo.addWorkoutPhoto(
          workoutSessionId: sessionId,
          tempPath: temp.path,
        );
        ids.add(p.id);
      }
      final list = await photoRepo.getWorkoutPhotos(sessionId);
      expect(list.map((p) => p.id).toList(), ids);
    });
  });

  group('身体照片', () {
    test('add bodyFront + bodySide，按日期读取（最新在前 + 部位固定顺序）', () async {
      final oldDay = DateTime(2026, 9, 1, 10);
      final newDay = DateTime(2026, 10, 1, 10);

      final front = await photoRepo.addBodyPhoto(
        type: PhotoType.bodyFront,
        tempPath: makeJpeg('f.jpg').path,
        takenAt: newDay,
      );
      final side = await photoRepo.addBodyPhoto(
        type: PhotoType.bodySide,
        tempPath: makeJpeg('s.jpg').path,
        takenAt: newDay.add(const Duration(hours: 1)),
      );
      await photoRepo.addBodyPhoto(
        type: PhotoType.bodyBack,
        tempPath: makeJpeg('b.jpg').path,
        takenAt: oldDay,
      );

      final list = await photoRepo.getBodyPhotos();
      expect(list.length, 3);
      // 最新日期优先（back 是旧日期，排最后）；
      // 同日内按固定部位顺序：正面 → 侧面（spec §48，不按时间排）
      expect(list[0].id, front.id);
      expect(list[1].id, side.id);
      expect(list[2].photoType, PhotoType.bodyBack.dbValue);
    });

    test('身体照片不能关联 session；训练照片必须关联 session（Repository 校验）', () async {
      final temp = makeJpeg('x.jpg');
      // 合法：身体照片不关联 session（必须 await，避免悬挂 async）
      final ok = await photoRepo.addBodyPhoto(
        type: PhotoType.bodyFront,
        tempPath: temp.path,
      );
      expect(ok.photoType, PhotoType.bodyFront.dbValue);

      // 非法组合：同步抛 ArgumentError（不产生任何文件/记录副作用）
      await expectLater(
        photoRepo.addPhoto(
          type: PhotoType.bodyFront,
          workoutSessionId: 1,
          tempPath: temp.path,
        ),
        throwsArgumentError,
      );
      await expectLater(
        photoRepo.addPhoto(type: PhotoType.workout, tempPath: temp.path),
        throwsArgumentError,
      );
    });
  });

  group('删除训练的照片清理', () {
    test('deleteForSession：DB 级联删 metadata + 文件尽力清理', () async {
      final sessionId = await completedSession('带照片的训练');
      final temp = makeJpeg('d1.jpg');
      final photo = await photoRepo.addWorkoutPhoto(
        workoutSessionId: sessionId,
        tempPath: temp.path,
      );

      // Repository 直接删除入口也必须清理照片。
      await workoutRepo.deleteSession(sessionId);

      // metadata 级联删除（FK cascade）
      final remaining = await (db.select(
        db.photos,
      )..where((p) => p.workoutSessionId.equals(sessionId))).get();
      expect(remaining, isEmpty);
      // session 本身删除
      expect(await workoutRepo.getDetail(sessionId), isNull);
      // 文件也删除
      expect(await storage.exists(photo.relativePath), isFalse);
      expect(await storage.exists(photo.thumbnailRelativePath!), isFalse);
    });
  });

  group('孤儿文件清理', () {
    test('cleanupOrphanFiles：删除无 DB 引用的文件，保留有引用的', () async {
      final sessionId = await completedSession('孤儿测试');
      final kept = await photoRepo.addWorkoutPhoto(
        workoutSessionId: sessionId,
        tempPath: makeJpeg('keep.jpg').path,
      );

      // 手工放一个孤儿文件
      await storage.writeFile(
        'photos/2026/01/orphan.jpg',
        Uint8List.fromList([1, 2, 3]),
      );

      final removed = await photoRepo.cleanupOrphanFiles();
      expect(removed, 1);
      expect(await storage.exists('photos/2026/01/orphan.jpg'), isFalse);
      // 有引用的保留
      expect(await storage.exists(kept.relativePath), isTrue);
      expect(await storage.exists(kept.thumbnailRelativePath!), isTrue);
    });
  });

  test('身体记录订阅随增删更新，不保留过期照片列表', () async {
    final iterator = StreamIterator(photoRepo.watchBodyPhotos());
    try {
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isEmpty);
      final photo = await photoRepo.addBodyPhoto(
        type: PhotoType.bodyFront,
        tempPath: makeJpeg('stream.jpg').path,
      );
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.single.id, photo.id);
      await photoRepo.deletePhoto(photo);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isEmpty);
    } finally {
      await iterator.cancel();
    }
  });

  test('关联训练不存在时插入失败：回滚全部新文件', () async {
    await expectLater(
      photoRepo.addWorkoutPhoto(
        workoutSessionId: 99999,
        tempPath: makeJpeg('invalid.jpg').path,
      ),
      throwsA(isA<Exception>()),
    );
    expect(await storage.listAllRelativePaths(), isEmpty);
    expect(await photoRepo.photoCount(), 0);
  });

  test('照片源文件丢失仍可删除元数据', () async {
    final photo = await photoRepo.addBodyPhoto(
      type: PhotoType.bodyOther,
      tempPath: makeJpeg('gone.jpg').path,
    );
    await storage.deletePhotoFiles(
      photo.relativePath,
      photo.thumbnailRelativePath,
    );
    await photoRepo.deletePhoto(photo);
    expect(await photoRepo.photoCount(), 0);
  });

  test('deleteAllPhotos：DB + 文件全清（清空数据用）', () async {
    final sessionId = await completedSession('清空测试');
    await photoRepo.addWorkoutPhoto(
      workoutSessionId: sessionId,
      tempPath: makeJpeg('all.jpg').path,
    );
    await photoRepo.addBodyPhoto(
      type: PhotoType.bodyFront,
      tempPath: makeJpeg('body.jpg').path,
    );

    await photoRepo.deleteAllPhotos();
    expect(await photoRepo.photoCount(), 0);
    expect(await storage.listAllRelativePaths(), isEmpty);
  });
}
