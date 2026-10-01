import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 照片存储业务异常。message 面向用户，不暴露技术细节。
class PhotoStorageException implements Exception {
  const PhotoStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 保存结果：数据库只存这两个相对路径。
class SavedPhotoPaths {
  const SavedPhotoPaths({
    required this.relativePath,
    this.thumbnailRelativePath,
  });

  final String relativePath;
  final String? thumbnailRelativePath;
}

/// 照片文件存储服务（照片功能中唯一允许接触文件系统的组件）。
///
/// 目录结构：`ApplicationSupport/fitlog/photos/YYYY/MM/<uuid>.jpg`（+ `_thumb.jpg`）。
/// - 文件名使用 UUID，不使用用户原始文件名，避免冲突与信息泄漏；
/// - DB 只存相对路径（相对媒体根目录 fitlog/），沙盒路径变化、备份恢复、
///   换机迁移都不受影响；
/// - 在后台 isolate 中校正方向、压缩并重新编码 JPEG；
///   主图长边 ≤2048 / q85，缩略图长边 ≤480 / q80，不放大小图；
/// - 显式移除 EXIF / GPS / 文本元数据，文件操作集中在本服务。
class PhotoStorageService {
  PhotoStorageService([this._rootOverride]);

  final Directory? _rootOverride;

  Future<void> _pending = Future.value();

  /// 同一媒体目录的增删、备份与覆盖恢复串行执行，避免维护误删正在保存的文件。
  Future<T> runExclusive<T>(Future<T> Function() operation) {
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        done.complete();
      }
    }();
  }

  static void validateRelativePath(String relativePath) {
    final parts = relativePath.split('/');
    if (parts.length < 2 ||
        parts.first != 'photos' ||
        parts.any((p) => p.isEmpty || p == '.' || p == '..') ||
        relativePath.contains('\\') ||
        relativePath.contains(':') ||
        relativePath.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('备份包含非法照片路径，已拒绝恢复');
    }
  }

  String? _cachedRootPath;

  /// 媒体根目录（fitlog/），测试可注入临时目录。
  Future<String> _rootPath() async {
    final cached = _cachedRootPath;
    if (cached != null) return cached;
    if (_rootOverride != null) {
      _cachedRootPath = _rootOverride.path;
      return _cachedRootPath!;
    }
    final support = await getApplicationSupportDirectory();
    _cachedRootPath = '${support.path}/fitlog';
    return _cachedRootPath!;
  }

  /// 从 image_picker 的临时文件保存主图 + 缩略图。
  /// 任一步骤失败时清理已生成文件并抛出 [PhotoStorageException]。
  Future<SavedPhotoPaths> saveFromTemp(String tempPath) async {
    File? mainFile;
    File? thumbFile;
    try {
      final temp = File(tempPath);
      if (!await temp.exists()) {
        throw const PhotoStorageException('照片处理失败，请重新选择。');
      }

      final now = DateTime.now();
      final uuid = const Uuid().v4();
      final month = now.month.toString().padLeft(2, '0');
      final relativeDir = 'photos/${now.year}/$month';
      final absDir = Directory('${await _rootPath()}/$relativeDir');
      await absDir.create(recursive: true);

      final encoded = await compute(_encodePhotos, await temp.readAsBytes());
      mainFile = File('${absDir.path}/$uuid.jpg');
      await mainFile.writeAsBytes(encoded.main, flush: true);

      // 两张 JPEG 均已显式剥离元数据。
      thumbFile = File('${absDir.path}/${uuid}_thumb.jpg');
      await thumbFile.writeAsBytes(encoded.thumbnail, flush: true);

      return SavedPhotoPaths(
        relativePath: '$relativeDir/$uuid.jpg',
        thumbnailRelativePath: '$relativeDir/${uuid}_thumb.jpg',
      );
    } on PhotoStorageException {
      await _cleanupQuietly(mainFile, thumbFile);
      rethrow;
    } catch (e) {
      debugPrint('照片保存失败: $e');
      await _cleanupQuietly(mainFile, thumbFile);
      throw const PhotoStorageException('照片处理失败，请重新选择。');
    }
  }

  /// 相对路径 → 实际文件。
  Future<File> fileFor(String relativePath) async {
    validateRelativePath(relativePath);
    return File('${await _rootPath()}/$relativePath');
  }

  /// 恢复备份时写入文件（创建父目录）。路径必须是媒体目录内的相对路径。
  Future<void> writeFile(String relativePath, Uint8List bytes) async {
    final file = await fileFor(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<bool> exists(String relativePath) async {
    return (await fileFor(relativePath)).exists();
  }

  /// 尽力删除主图与缩略图。文件不存在时静默忽略，其他删除失败只记日志，
  /// 绝不抛出（DB 是元数据 source of truth，文件清理是尽力而为）。
  Future<void> deletePhotoFiles(
    String relativePath,
    String? thumbnailPath,
  ) async {
    for (final rel in [relativePath, ?thumbnailPath]) {
      try {
        final f = await fileFor(rel);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (e) {
        debugPrint('照片文件删除失败（忽略）: $rel, $e');
      }
    }
  }

  /// 清空全部照片目录（清空数据时调用）。
  Future<void> deleteAllPhotos() async {
    try {
      final dir = Directory('${await _rootPath()}/photos');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('照片目录清理失败: $e');
      rethrow;
    }
  }

  /// 媒体目录下全部文件的相对路径（孤儿文件清理用）。
  Future<List<String>> listAllRelativePaths() async {
    final root = await _rootPath();
    final photosDir = Directory('$root/photos');
    if (!await photosDir.exists()) return [];
    final result = <String>[];
    await for (final entity in photosDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final abs = entity.path;
        if (abs.startsWith('$root/')) {
          result.add(abs.substring(root.length + 1));
        }
      }
    }
    return result;
  }

  /// 照片占用磁盘空间（字节）。
  Future<int> photosDiskUsage() async {
    var total = 0;
    for (final rel in await listAllRelativePaths()) {
      final f = File('${await _rootPath()}/$rel');
      try {
        total += await f.length();
      } catch (e) {
        debugPrint('照片文件维护失败: $e');
      }
    }
    return total;
  }

  /// picker 产生的临时文件在保存结束后释放，页面不操作文件系统。
  Future<void> releasePickedFile(String tempPath) async {
    try {
      final file = File(tempPath);
      // 桌面 picker 可能返回用户原文件；只释放临时目录中的副本。
      bool inside(Directory dir) =>
          file.absolute.path.startsWith('${dir.absolute.path}/');
      if (!inside(Directory.systemTemp) &&
          !inside(await getTemporaryDirectory())) {
        return;
      }
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('临时照片清理失败: $e');
    }
  }

  Future<PhotoStorageService> createStagingStorage() async {
    final root = Directory(await _rootPath());
    await root.create(recursive: true);
    return PhotoStorageService(await root.createTemp('.restore_'));
  }

  Future<void> discardStagingStorage() async {
    if (_rootOverride == null) throw StateError('仅可清理临时媒体目录');
    try {
      if (await _rootOverride.exists()) {
        await _rootOverride.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('临时媒体目录清理失败: $e');
    }
  }

  /// 临时照片准备成功后，整目录替换；数据库事务失败时还原原目录。
  /// 调用方需持有 runExclusive；临时目录与目标位于同一文件系统。
  Future<void> replacePhotosFrom(
    PhotoStorageService staged,
    Future<void> Function() replaceMetadata,
  ) async {
    final root = await _rootPath();
    final current = Directory('$root/photos');
    final incoming = Directory('${await staged._rootPath()}/photos');
    final previous = Directory('$root/.previous_${const Uuid().v4()}');
    await incoming.create(recursive: true);
    var movedOld = false;
    var movedNew = false;
    try {
      if (await current.exists()) {
        await current.rename(previous.path);
        movedOld = true;
      }
      await incoming.rename(current.path);
      movedNew = true;
      await replaceMetadata();
    } catch (e) {
      if (movedNew) await current.rename(incoming.path);
      if (movedOld) await previous.rename(current.path);
      rethrow;
    }
    // 提交成功后旧文件不再被引用；清理失败留作重试，不将成功误报为恢复失败。
    if (movedOld) {
      try {
        await previous.delete(recursive: true);
      } catch (e) {
        debugPrint('旧媒体备份清理失败: $e');
      }
    }
  }

  Future<void> _cleanupQuietly(File? mainFile, File? thumbFile) async {
    for (final f in [mainFile, thumbFile]) {
      try {
        if (f != null && await f.exists()) {
          await f.delete();
        }
      } catch (e) {
        debugPrint('照片文件维护失败: $e');
      }
    }
  }
}

({Uint8List main, Uint8List thumbnail}) _encodePhotos(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const PhotoStorageException('照片处理失败，请重新选择。');
  }
  final oriented = img.bakeOrientation(decoded);
  oriented.exif = img.ExifData();
  oriented.textData = null;
  // 保留颜色配置以免肤色变化；GPS、设备和拍摄时间均已删除。
  img.Image resize(int maxEdge) {
    if (oriented.width <= maxEdge && oriented.height <= maxEdge) {
      return oriented;
    }
    return img.copyResize(
      oriented,
      width: oriented.width >= oriented.height ? maxEdge : null,
      height: oriented.height > oriented.width ? maxEdge : null,
    );
  }

  return (
    main: Uint8List.fromList(img.encodeJpg(resize(2048), quality: 85)),
    thumbnail: Uint8List.fromList(img.encodeJpg(resize(480), quality: 80)),
  );
}
