import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/core/constants/photo_types.dart';
import 'package:fitlog/core/storage/photo_storage_service.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/backup_repository.dart';
import 'package:fitlog/database/exercise_repository.dart';
import 'package:fitlog/database/photo_repository.dart';
import 'package:fitlog/database/workout_repository.dart';
import 'package:fitlog/features/workout/workout_draft.dart';
import 'package:image/image.dart' as img;

/// 备份 / 恢复测试：JSON round-trip、ZIP（含照片）、Legacy 兼容、路径安全。
void main() {
  late AppDatabase sourceDb;
  late AppDatabase targetDb;
  late BackupRepository sourceBackup;
  late BackupRepository targetBackup;
  late PhotoStorageService sourceStorage;
  late PhotoStorageService targetStorage;
  late WorkoutRepository sourceWorkoutRepo;
  late WorkoutRepository targetWorkoutRepo;
  late Directory sourceMediaRoot;
  late Directory targetMediaRoot;
  late Directory tempPickDir;

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
    sourceDb = AppDatabase.forTesting(NativeDatabase.memory());
    targetDb = AppDatabase.forTesting(NativeDatabase.memory());
    sourceMediaRoot = await Directory.systemTemp.createTemp('fitlog_src_media');
    targetMediaRoot = await Directory.systemTemp.createTemp('fitlog_dst_media');
    tempPickDir = await Directory.systemTemp.createTemp('fitlog_zip_pick');
    sourceStorage = PhotoStorageService(sourceMediaRoot);
    targetStorage = PhotoStorageService(targetMediaRoot);
    sourceBackup = BackupRepository(sourceDb, sourceStorage, sourceMediaRoot);
    targetBackup = BackupRepository(targetDb, targetStorage, targetMediaRoot);
    sourceWorkoutRepo = WorkoutRepository(sourceDb, sourceStorage);
    targetWorkoutRepo = WorkoutRepository(targetDb, targetStorage);
    await ExerciseRepository(sourceDb).ensureSeeded();
  });

  tearDown(() async {
    await sourceDb.close();
    await targetDb.close();
    await tempPickDir.delete(recursive: true);
    await sourceMediaRoot.delete(recursive: true);
    await targetMediaRoot.delete(recursive: true);
  });

  /// 建一场已完成的训练（source 库），返回 session id。
  Future<int> completedSession(String name) async {
    final sessionId = await sourceWorkoutRepo.createInProgressSession(
      name: name,
    );
    await sourceWorkoutRepo.completeSession(
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

  test('导出 → 导入后数据一致', () async {
    final benchId = (await ExerciseRepository(
      sourceDb,
    ).getAll()).firstWhere((e) => e.name == '杠铃卧推').id;

    final sessionId = await completedSession('胸 + 肩');
    final draft = WorkoutDraft(
      sessionDbId: sessionId,
      isInProgress: true,
      name: '胸 + 肩',
      startTime: DateTime(2026, 10, 1, 18),
      exercises: [
        DraftExercise(
          exerciseId: benchId,
          name: '杠铃卧推',
          muscleGroup: '胸',
          sets: [
            DraftSet(weight: 60, reps: 12),
            DraftSet(weight: 80, reps: 10),
          ],
        ),
      ],
    );
    await sourceWorkoutRepo.saveDraftContent(sessionId, draft);
    await sourceWorkoutRepo.completeSession(sessionId, draft);

    final json = await sourceBackup.exportToJson();
    final legacyFile = File('${sourceMediaRoot.path}/legacy.json')
      ..writeAsStringSync(sourceBackup.encodePretty(json));
    final restored = await targetBackup.importBackup(legacyFile);

    expect(restored.legacy, isTrue);
    expect(restored.workouts, 1);
    final detail = await targetWorkoutRepo.getDetail(sessionId);
    expect(detail!.exercises.first.sets.length, 2);
    expect(detail.exercises.first.sets.last.weight, 80);
  });

  test('schema 版本过高时拒绝导入', () async {
    final json = await sourceBackup.exportToJson();
    json['schemaVersion'] = 999;
    final bad = File('${sourceMediaRoot.path}/future.json')
      ..writeAsStringSync(jsonEncode(json));
    await expectLater(
      targetBackup.importBackup(bad),
      throwsA(isA<FormatException>()),
    );
  });

  test('损坏的 JSON 抛出 FormatException', () {
    expect(() => targetBackup.decode('not a json {'), throwsFormatException);
  });

  group('ZIP 备份（V1.2）', () {
    test('round-trip：训练 + 照片（DB metadata + 文件）完整恢复', () async {
      final sessionId = await completedSession('练胸');
      final sourcePhotoRepo = PhotoRepository(sourceDb, sourceStorage);
      await sourcePhotoRepo.addWorkoutPhoto(
        workoutSessionId: sessionId,
        tempPath: makeJpeg('w.jpg').path,
      );
      await sourcePhotoRepo.addBodyPhoto(
        type: PhotoType.bodyFront,
        tempPath: makeJpeg('b.jpg').path,
      );

      final (zipFile, skipped) = await sourceBackup.exportBackupZip();
      expect(skipped, 0);

      final restored = await targetBackup.importBackup(zipFile);
      expect(restored.legacy, isFalse);
      expect(restored.workouts, 1);
      expect(restored.photos, 2);

      final targetPhotoRepo = PhotoRepository(targetDb, targetStorage);
      expect(await targetPhotoRepo.photoCount(), 2);
      final workoutPhotos = await targetPhotoRepo.getWorkoutPhotos(sessionId);
      expect(workoutPhotos.length, 1);
      for (final p in workoutPhotos) {
        expect(await targetStorage.exists(p.relativePath), isTrue);
        expect(await targetStorage.exists(p.thumbnailRelativePath!), isTrue);
      }
      final bodyPhotos = await targetPhotoRepo.getBodyPhotos();
      expect(bodyPhotos.length, 1);
      expect(await targetStorage.exists(bodyPhotos.first.relativePath), isTrue);
      expect(
        await targetStorage.exists(bodyPhotos.first.thumbnailRelativePath!),
        isTrue,
      );
    });

    test('Legacy JSON（v1 无照片）仍可恢复：训练恢复，photos 为空', () async {
      final sessionId = await completedSession('旧备份');

      final json = await sourceBackup.exportToJson();
      json['schemaVersion'] = 1;
      json['photos'] = null; // 模拟 legacy 无此 key
      final legacyFile = File('${sourceMediaRoot.path}/legacy.json')
        ..writeAsStringSync(jsonEncode(json));

      final restored = await targetBackup.importBackup(legacyFile);
      expect(restored.legacy, isTrue);
      expect(restored.workouts, 1);
      expect(await PhotoRepository(targetDb, targetStorage).photoCount(), 0);
      expect(await targetWorkoutRepo.getDetail(sessionId), isNotNull);
    });

    test('ZIP 缺少 backup.json → 拒绝恢复', () async {
      final junk = Uint8List.fromList(utf8.encode('{}'));
      final archive = Archive()
        ..addFile(ArchiveFile('not_backup.json', junk.length, junk));
      final zipPath = '${sourceMediaRoot.path}/no_json.zip';
      File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));

      await expectLater(
        targetBackup.importBackup(File(zipPath)),
        throwsA(isA<FormatException>()),
      );
    });

    test('backupFormatVersion 太新 → 拒绝', () async {
      final json = await sourceBackup.exportToJson();
      json['backupFormatVersion'] = 999;
      final jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      final archive = Archive()
        ..addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
      final zipPath = '${sourceMediaRoot.path}/future.zip';
      File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));

      await expectLater(
        targetBackup.importBackup(File(zipPath)),
        throwsA(isA<FormatException>()),
      );
    });

    test('databaseSchemaVersion 太新 → 拒绝', () async {
      final json = await sourceBackup.exportToJson();
      json['databaseSchemaVersion'] = 999;
      final jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      final archive = Archive()
        ..addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));
      final zipPath = '${sourceMediaRoot.path}/future_db.zip';
      File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));

      await expectLater(
        targetBackup.importBackup(File(zipPath)),
        throwsA(isA<FormatException>()),
      );
    });

    test('ZIP 路径穿越（../../evil.jpg）→ 拒绝恢复', () async {
      final json = await sourceBackup.exportToJson();
      final jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      final archive = Archive()
        ..addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes))
        ..addFile(ArchiveFile('../../evil.jpg', 3, [1, 2, 3]));
      final zipPath = '${sourceMediaRoot.path}/evil.zip';
      File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));

      await expectLater(
        targetBackup.importBackup(File(zipPath)),
        throwsA(isA<FormatException>()),
      );
      // 目标媒体目录没有被写入恶意文件
      expect(await targetStorage.listAllRelativePaths(), isEmpty);
    });

    test('ZIP 中缺失照片文件 → 不 Crash，元数据保留并计数', () async {
      final sessionId = await completedSession('缺图');
      final sourcePhotoRepo = PhotoRepository(sourceDb, sourceStorage);
      await sourcePhotoRepo.addWorkoutPhoto(
        workoutSessionId: sessionId,
        tempPath: makeJpeg('missing.jpg').path,
      );

      final (zipFile, _) = await sourceBackup.exportBackupZip();
      // 从 ZIP 中移除照片文件（模拟文件丢失）
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
      final partial = Archive();
      for (final f in archive.files) {
        if (f.name.startsWith('photos/')) continue;
        partial.addFile(f);
      }
      final partialPath = '${sourceMediaRoot.path}/partial.zip';
      File(partialPath).writeAsBytesSync(ZipEncoder().encode(partial));

      final restored = await targetBackup.importBackup(File(partialPath));
      expect(restored.legacy, isFalse);
      expect(restored.photos, 1); // metadata 保留
      expect(restored.photoFilesCopied, 0);
      expect(restored.photoFilesSkipped, greaterThanOrEqualTo(1));

      // metadata 在、文件缺 → UI 显示占位（不 Crash 的前提）
      final targetPhotoRepo = PhotoRepository(targetDb, targetStorage);
      expect(await targetPhotoRepo.photoCount(), 1);
      final photos = await targetPhotoRepo.getWorkoutPhotos(sessionId);
      expect(await targetStorage.exists(photos.first.relativePath), isFalse);
    });
  });
  File writeZip(
    Map<String, dynamic> json, {
    List<ArchiveFile> extra = const [],
  }) {
    final archive = Archive()
      ..addFile(ArchiveFile.string('backup.json', jsonEncode(json)));
    for (final file in extra) {
      archive.addFile(file);
    }
    return File('${sourceMediaRoot.path}/fixture.zip')
      ..writeAsBytesSync(ZipEncoder().encode(archive));
  }

  Future<Photo> existingTargetPhoto() =>
      PhotoRepository(targetDb, targetStorage).addBodyPhoto(
        type: PhotoType.bodyBack,
        tempPath: makeJpeg('existing.jpg').path,
      );

  test('恢复预检只给出摘要，取消后当前数据与照片不变', () async {
    final old = await existingTargetPhoto();
    await completedSession('待恢复');
    final (zip, _) = await sourceBackup.exportBackupZip();
    final prepared = await targetBackup.prepareBackup(zip);
    expect(prepared.summary.workouts, 1);
    expect(await PhotoRepository(targetDb, targetStorage).photoCount(), 1);
    expect(await targetStorage.exists(old.relativePath), isTrue);
    await prepared.dispose();
    expect(await targetStorage.exists(old.relativePath), isTrue);
    await expectLater(targetBackup.restorePrepared(prepared), throwsStateError);
  });

  test('不完整 JSON 拒绝覆盖，保留当前数据和照片', () async {
    final old = await existingTargetPhoto();
    await expectLater(
      targetBackup.importFromJson({'schemaVersion': 1}),
      throwsFormatException,
    );
    expect(await PhotoRepository(targetDb, targetStorage).photoCount(), 1);
    expect(await targetStorage.exists(old.relativePath), isTrue);
  });

  test('ZIP 元数据路径穿越、绝对路径及未知分类均在覆盖前拒绝', () async {
    final old = await existingTargetPhoto();
    await PhotoRepository(sourceDb, sourceStorage).addBodyPhoto(
      type: PhotoType.bodyFront,
      tempPath: makeJpeg('source.jpg').path,
    );
    for (final path in [
      'photos/../../evil.jpg',
      '/tmp/evil.jpg',
      r'photos\evil.jpg',
      'other/evil.jpg',
    ]) {
      final json = await sourceBackup.exportToJson();
      (json['photos'] as List).first['relativePath'] = path;
      await expectLater(
        targetBackup.importBackup(writeZip(json)),
        throwsFormatException,
      );
    }
    final unknown = await sourceBackup.exportToJson();
    (unknown['photos'] as List).first['photoType'] = 'new_unknown_type';
    await expectLater(
      targetBackup.importBackup(writeZip(unknown)),
      throwsFormatException,
    );
    final wrongOwner = await sourceBackup.exportToJson();
    (wrongOwner['photos'] as List).first['workoutSessionId'] = 7;
    await expectLater(
      targetBackup.importBackup(writeZip(wrongOwner)),
      throwsFormatException,
    );
    expect(await PhotoRepository(targetDb, targetStorage).photoCount(), 1);
    expect(await targetStorage.exists(old.relativePath), isTrue);
  });

  test('ZIP 符号链接拒绝恢复', () async {
    final json = await sourceBackup.exportToJson();
    final link = ArchiveFile.string('photos/link.jpg', '../../evil.jpg')
      ..mode = 0xa1ff;
    await expectLater(
      targetBackup.importBackup(writeZip(json, extra: [link])),
      throwsFormatException,
    );
  });

  test('旧 JSON 也校验 databaseSchemaVersion，拒绝新版本数据库', () async {
    final json = await sourceBackup.exportToJson();
    json['databaseSchemaVersion'] = 999;
    await expectLater(targetBackup.importFromJson(json), throwsFormatException);
  });

  test('旧 JSON 恢复成功后清理全部旧媒体', () async {
    final old = await existingTargetPhoto();
    final id = await completedSession('旧备份训练');
    final json = await sourceBackup.exportToJson();
    json.remove('photos');
    json.remove('backupFormatVersion');
    json.remove('databaseSchemaVersion');
    json['schemaVersion'] = 1;
    await targetBackup.importFromJson(json);
    expect(await targetWorkoutRepo.getDetail(id), isNotNull);
    expect(await targetStorage.exists(old.relativePath), isFalse);
    expect(await targetStorage.listAllRelativePaths(), isEmpty);
  });

  test('导出缺失照片文件安全跳过并计数', () async {
    final photo = await PhotoRepository(sourceDb, sourceStorage).addBodyPhoto(
      type: PhotoType.bodyFront,
      tempPath: makeJpeg('export_missing.jpg').path,
    );
    await sourceStorage.deletePhotoFiles(photo.relativePath, null);
    final (zip, skipped) = await sourceBackup.exportBackupZip();
    expect(skipped, 1);
    final result = await targetBackup.importBackup(zip);
    expect(result.photos, 1);
    expect(result.photoFilesCopied, 1);
    expect(result.photoFilesSkipped, 1);
  });

  test('缺失的新备份文件不复用当前目录同路径的旧照片', () async {
    final photo = await PhotoRepository(sourceDb, sourceStorage).addBodyPhoto(
      type: PhotoType.bodyFront,
      tempPath: makeJpeg('missing_source.jpg').path,
    );
    await targetStorage.writeFile(
      photo.relativePath,
      Uint8List.fromList([9, 9, 9]),
    );
    final json = await sourceBackup.exportToJson();
    final result = await targetBackup.importBackup(writeZip(json));
    expect(result.photoFilesSkipped, 2);
    expect(await targetStorage.exists(photo.relativePath), isFalse);
  });

  test('文件暂存复制中途失败，原数据库和原照片完全保留', () async {
    final old = await existingTargetPhoto();
    final before = await (await targetStorage.fileFor(old.relativePath))
        .readAsBytes();
    await PhotoRepository(sourceDb, sourceStorage).addBodyPhoto(
      type: PhotoType.bodyFront,
      tempPath: makeJpeg('copy_failure.jpg').path,
    );
    final (zip, _) = await sourceBackup.exportBackupZip();
    final failing = BackupRepository(
      targetDb,
      _FailingStorage(targetMediaRoot),
    );
    await expectLater(
      failing.importBackup(zip),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      (await targetDb.select(targetDb.photos).getSingle()).relativePath,
      old.relativePath,
    );
    expect(
      await (await targetStorage.fileFor(old.relativePath)).readAsBytes(),
      before,
    );
    expect(await targetStorage.exists(old.thumbnailRelativePath!), isTrue);
  });

  test('数据库插入失败，回滚旧 DB 并还原已经替换的照片目录', () async {
    final old = await existingTargetPhoto();
    final before = await (await targetStorage.fileFor(old.relativePath))
        .readAsBytes();
    await completedSession('会触发数据库错误的备份');
    await PhotoRepository(sourceDb, sourceStorage).addBodyPhoto(
      type: PhotoType.bodyFront,
      tempPath: makeJpeg('db_failure.jpg').path,
    );
    final (zip, _) = await sourceBackup.exportBackupZip();
    await targetDb.customStatement(
      "CREATE TRIGGER reject_restore BEFORE INSERT ON workout_sessions BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(
      targetBackup.importBackup(zip),
      throwsA(isA<Exception>()),
    );
    expect(
      (await targetDb.select(targetDb.photos).getSingle()).relativePath,
      old.relativePath,
    );
    expect(
      await (await targetStorage.fileFor(old.relativePath)).readAsBytes(),
      before,
    );
    expect(await targetStorage.exists(old.thumbnailRelativePath!), isTrue);
    expect(await targetStorage.listAllRelativePaths(), hasLength(2));
  });

  test('清空全部数据同时删除训练照片、身体照片和孤立媒体文件', () async {
    final id = await completedSession('清空训练');
    final photoRepo = PhotoRepository(sourceDb, sourceStorage);
    await photoRepo.addWorkoutPhoto(
      workoutSessionId: id,
      tempPath: makeJpeg('workout_clear.jpg').path,
    );
    await photoRepo.addBodyPhoto(
      type: PhotoType.bodyBack,
      tempPath: makeJpeg('body_clear.jpg').path,
    );
    await sourceStorage.writeFile(
      'photos/orphan.jpg',
      Uint8List.fromList([1, 2, 3]),
    );
    await sourceBackup.clearAllData();
    expect(await sourceDb.select(sourceDb.workoutSessions).get(), isEmpty);
    expect(await sourceDb.select(sourceDb.exercises).get(), isEmpty);
    expect(await photoRepo.photoCount(), 0);
    expect(await sourceStorage.listAllRelativePaths(), isEmpty);
  });

  test('清空数据库失败时原照片和元数据一并恢复', () async {
    final photo = await existingTargetPhoto();
    await targetDb.customStatement(
      "CREATE TRIGGER reject_clear BEFORE DELETE ON photos BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(targetBackup.clearAllData(), throwsA(isA<Exception>()));
    expect(await PhotoRepository(targetDb, targetStorage).photoCount(), 1);
    expect(await targetStorage.exists(photo.relativePath), isTrue);
    expect(await targetStorage.exists(photo.thumbnailRelativePath!), isTrue);
  });

  test('ZIP CRC 损坏拒绝恢复', () async {
    final json = await sourceBackup.exportToJson();
    final bytes = utf8.encode(jsonEncode(json));
    final archive = Archive()
      ..addFile(ArchiveFile.noCompress('backup.json', bytes.length, bytes));
    final encoded = ZipEncoder().encode(archive);
    // local file header 后第一个 payload 字节；CRC 保持不变。
    final nameLength = encoded[26] | (encoded[27] << 8);
    final extraLength = encoded[28] | (encoded[29] << 8);
    encoded[30 + nameLength + extraLength] ^= 1;
    final bad = File('${sourceMediaRoot.path}/bad_crc.zip')
      ..writeAsBytesSync(encoded);
    await expectLater(targetBackup.importBackup(bad), throwsFormatException);
  });
}

class _FailingStorage extends PhotoStorageService {
  _FailingStorage(this.root) : super(root);
  final Directory root;
  @override
  Future<PhotoStorageService> createStagingStorage() async =>
      _FailingStaged(await root.createTemp('.test_stage_'));
}

class _FailingStaged extends PhotoStorageService {
  _FailingStaged(super.root);
  int writes = 0;
  @override
  Future<void> writeFile(String relativePath, Uint8List bytes) async {
    if (++writes == 2) throw const FileSystemException('simulated disk full');
    await super.writeFile(relativePath, bytes);
  }
}
