import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/photo_types.dart';
import '../core/storage/photo_storage_service.dart';
import 'app_database.dart';
import 'database_provider.dart';

/// 照片元数据仓库。文件生命周期由 [PhotoStorageService] 负责，
/// 本仓库负责业务校验与「文件 / DB」一致性协调。
class PhotoRepository {
  PhotoRepository(this._db, this._storage);

  final AppDatabase _db;
  final PhotoStorageService _storage;

  /// 类型与归属一致性校验（Repository 层兜底，不依赖 UI 自觉传对）：
  /// - 训练照片：photoType = workout 且 workoutSessionId != null
  /// - 身体照片：photoType = body_* 且 workoutSessionId == null
  void _validateType(PhotoType type, int? workoutSessionId) {
    if (type.isWorkout && workoutSessionId == null) {
      throw ArgumentError('训练照片必须关联 workoutSessionId');
    }
    if (type.isBody && workoutSessionId != null) {
      throw ArgumentError('身体照片不能关联 workoutSessionId');
    }
  }

  /// 添加照片。流程（文件系统与 SQLite 不是同一个事务，需手动协调）：
  /// 1. 文件落盘（main + thumbnail）
  /// 2. 插入元数据
  /// 3. 元数据失败 → 删除刚生成的文件，避免孤儿文件长期泄漏
  Future<Photo> addPhoto({
    required PhotoType type,
    int? workoutSessionId,
    required String tempPath,
    String? note,
    DateTime? takenAt,
  }) => _storage.runExclusive(() async {
    _validateType(type, workoutSessionId);
    final capturedAt = takenAt ?? DateTime.now();
    final paths = await _storage.saveFromTemp(tempPath);
    try {
      return await _db.transaction(() async {
        final id = await (_db
            .into(_db.photos)
            .insert(
              PhotosCompanion.insert(
                workoutSessionId: Value(workoutSessionId),
                photoType: type.dbValue,
                relativePath: paths.relativePath,
                thumbnailRelativePath: Value(paths.thumbnailRelativePath),
                takenAt: capturedAt,
                note: Value(note),
              ),
            ));
        return await (_db.select(
          _db.photos,
        )..where((p) => p.id.equals(id))).getSingle();
      });
    } catch (e) {
      debugPrint('照片元数据保存失败，回滚文件: $e');
      await _storage.deletePhotoFiles(
        paths.relativePath,
        paths.thumbnailRelativePath,
      );
      rethrow;
    }
  });

  Future<Photo> addWorkoutPhoto({
    required int workoutSessionId,
    required String tempPath,
    String? note,
  }) {
    return addPhoto(
      type: PhotoType.workout,
      workoutSessionId: workoutSessionId,
      tempPath: tempPath,
      note: note,
    );
  }

  Future<Photo> addBodyPhoto({
    required PhotoType type,
    required String tempPath,
    String? note,
    DateTime? takenAt,
  }) {
    return addPhoto(
      type: type,
      tempPath: tempPath,
      note: note,
      takenAt: takenAt,
    );
  }

  /// 训练照片（详情页）：按添加顺序稳定展示。
  Stream<List<Photo>> watchWorkoutPhotos(int workoutSessionId) {
    return (_db.select(_db.photos)
          ..where((p) => p.workoutSessionId.equals(workoutSessionId))
          ..orderBy([
            (p) => OrderingTerm.asc(p.createdAt),
            (p) => OrderingTerm.asc(p.id),
          ]))
        .watch();
  }

  Future<List<Photo>> getWorkoutPhotos(int workoutSessionId) {
    return (_db.select(_db.photos)
          ..where((p) => p.workoutSessionId.equals(workoutSessionId))
          ..orderBy([
            (p) => OrderingTerm.asc(p.createdAt),
            (p) => OrderingTerm.asc(p.id),
          ]))
        .get();
  }

  Stream<List<Photo>> watchBodyPhotos() {
    return (_db.select(_db.photos)
          ..where((p) => p.photoType.isIn(bodyPhotoDbValues)))
        .watch()
        .map(_sortBodyPhotos);
  }

  /// 身体照片：takenAt 倒序（最新优先）；同日内按固定部位顺序。
  Future<List<Photo>> getBodyPhotos() {
    return (_db.select(_db.photos)
          ..where((p) => p.photoType.isIn(bodyPhotoDbValues))
          ..orderBy([
            (p) => OrderingTerm.desc(p.takenAt),
            (p) => OrderingTerm.desc(p.id),
          ]))
        .get()
        .then(_sortBodyPhotos);
  }

  List<Photo> _sortBodyPhotos(List<Photo> photos) {
    final sorted = [...photos]
      ..sort((a, b) {
        final byDay = _dayKey(b.takenAt).compareTo(_dayKey(a.takenAt));
        if (byDay != 0) return byDay;
        final byType = PhotoType.fromDb(a.photoType).bodyOrder
            .compareTo(PhotoType.fromDb(b.photoType).bodyOrder);
        if (byType != 0) return byType;
        final byTime = b.takenAt.compareTo(a.takenAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return sorted;
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 删除单张照片：DB 先删（元数据 source of truth），文件尽力清理。
  Future<void> deletePhoto(Photo photo) => _storage.runExclusive(() async {
    // 防止恢复备份后旧 Viewer 中的同 ID 照片误删新记录。
    final query = _db.select(_db.photos)
      ..where(
        (p) =>
            p.id.equals(photo.id) & p.relativePath.equals(photo.relativePath),
      );
    final current = await query.getSingleOrNull();
    if (current == null) return;
    await (_db.delete(_db.photos)..where((p) => p.id.equals(current.id))).go();
    await _storage.deletePhotoFiles(
      current.relativePath,
      current.thumbnailRelativePath,
    );
  });

  /// 收集某训练全部照片的相对路径（删训练前调用，级联删 metadata 前留底）。
  Future<List<(String, String?)>> collectPathsForSession(
    int workoutSessionId,
  ) async {
    final photos = await (_db.select(
      _db.photos,
    )..where((p) => p.workoutSessionId.equals(workoutSessionId))).get();
    return [for (final p in photos) (p.relativePath, p.thumbnailRelativePath)];
  }

  /// 删除训练时的照片清理协调（文件系统与 DB 级联不是同一事务）：
  /// 1. 收集该训练全部照片路径
  /// 2. 执行传入的 session 删除动作（FK 级联删 photo metadata）
  /// 3. 尽力清理文件（失败仅记日志，绝不抛出）
  Future<void> deleteForSession(
    int workoutSessionId, {
    required Future<void> Function() deleteSession,
  }) => _storage.runExclusive(() async {
    final paths = await _db.transaction(() async {
      final collected = await collectPathsForSession(workoutSessionId);
      await deleteSession();
      return collected;
    });
    for (final (main, thumb) in paths) {
      await _storage.deletePhotoFiles(main, thumb);
    }
  });

  /// 孤儿文件清理：扫描媒体目录，删除没有 DB 引用的文件。返回删除数量。
  /// 不在启动时自动执行，作为数据管理维护手段。
  Future<int> cleanupOrphanFiles() => _storage.runExclusive(() async {
    final referenced = <String>{};
    final rows = await _db.select(_db.photos).get();
    for (final p in rows) {
      referenced.add(p.relativePath);
      if (p.thumbnailRelativePath != null) {
        referenced.add(p.thumbnailRelativePath!);
      }
    }
    var removed = 0;
    for (final rel in await _storage.listAllRelativePaths()) {
      if (!referenced.contains(rel)) {
        await _storage.deletePhotoFiles(rel, null);
        if (!await _storage.exists(rel)) removed += 1;
      }
    }
    return removed;
  });

  /// 清空全部照片（清空数据时调用）：DB + 文件。
  Future<void> deleteAllPhotos() => _storage.runExclusive(() async {
    final staged = await _storage.createStagingStorage();
    try {
      await _storage.replacePhotosFrom(
        staged,
        () => _db.transaction(() async {
          await _db.delete(_db.photos).go();
        }),
      );
    } finally {
      await staged.discardStagingStorage();
    }
  });

  Future<int> photoCount() async {
    final count = countAll();
    final query = _db.selectOnly(_db.photos)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// 照片占用磁盘空间（字节）。
  Future<int> photosDiskUsage() => _storage.photosDiskUsage();
}

final photoStorageServiceProvider = Provider<PhotoStorageService>(
  (ref) => PhotoStorageService(),
);

final photoRepositoryProvider = Provider<PhotoRepository>(
  (ref) => PhotoRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(photoStorageServiceProvider),
  ),
);
