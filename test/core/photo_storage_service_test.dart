import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitlog/core/storage/photo_storage_service.dart';
import 'package:image/image.dart' as img;

/// PhotoStorageService 测试：真实临时目录 + 真实 JPEG 字节。
void main() {
  late Directory mediaRoot;
  late PhotoStorageService storage;
  late File tempImage;

  /// 生成一个真实的小 JPEG（120×80 蓝色块）。
  File makeJpeg(Directory dir, String name) {
    final image = img.Image(width: 120, height: 80);
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 119,
      y2: 79,
      color: img.ColorRgb8(10, 100, 200),
    );
    final bytes = img.encodeJpg(image, quality: 90);
    return File('${dir.path}/$name')..writeAsBytesSync(bytes);
  }

  setUp(() async {
    mediaRoot = await Directory.systemTemp.createTemp('fitlog_media_test');
    storage = PhotoStorageService(mediaRoot);
    tempImage = makeJpeg(
      await Directory.systemTemp.createTemp('pick'),
      'picker_tmp.jpg',
    );
  });

  tearDown(() async {
    await tempImage.parent.delete(recursive: true);
    await mediaRoot.delete(recursive: true);
  });

  test('保存后：主文件存在、thumbnail 存在、格式为相对路径', () async {
    final saved = await storage.saveFromTemp(tempImage.path);

    // 临时原文件名不应出现在 relativePath 中
    expect(saved.relativePath.contains('picker_tmp'), isFalse);
    expect(saved.relativePath.startsWith('photos/'), isTrue);
    expect(saved.relativePath.endsWith('.jpg'), isTrue);
    expect(saved.thumbnailRelativePath, isNotNull);
    expect(saved.thumbnailRelativePath!.endsWith('_thumb.jpg'), isTrue);

    // 不包含沙盒绝对路径
    expect(saved.relativePath.contains(mediaRoot.path), isFalse);
    expect(saved.relativePath.contains('/var/'), isFalse);

    // 两个文件都真实存在
    expect(await storage.exists(saved.relativePath), isTrue);
    expect(await storage.exists(saved.thumbnailRelativePath!), isTrue);
  });

  test('文件名 UUID 唯一：两次保存产生不同路径', () async {
    final a = await storage.saveFromTemp(tempImage.path);
    final b = await storage.saveFromTemp(tempImage.path);
    expect(a.relativePath, isNot(b.relativePath));
  });

  test('释放 picker 文件不会删除临时目录之外的用户原文件', () async {
    final originalDir = await Directory.current.createTemp('.fitlog_source_');
    try {
      final original = makeJpeg(originalDir, 'original.jpg');
      await storage.releasePickedFile(original.path);
      expect(await original.exists(), isTrue);
    } finally {
      await originalDir.delete(recursive: true);
    }
  });

  test('删除照片：main + thumbnail 都删除', () async {
    final saved = await storage.saveFromTemp(tempImage.path);
    await storage.deletePhotoFiles(
      saved.relativePath,
      saved.thumbnailRelativePath,
    );
    expect(await storage.exists(saved.relativePath), isFalse);
    expect(await storage.exists(saved.thumbnailRelativePath!), isFalse);
  });

  test('文件不存在时删除：不 Crash（静默忽略）', () async {
    await storage.deletePhotoFiles('photos/2099/01/nope.jpg', null);
    // 不抛异常即通过
  });

  test('临时文件不存在：抛出友好异常（不 Crash）', () async {
    await expectLater(
      storage.saveFromTemp('/nonexistent/path/xx.jpg'),
      throwsA(isA<PhotoStorageException>()),
    );
  });

  test('listAllRelativePaths / photosDiskUsage', () async {
    await storage.saveFromTemp(tempImage.path);
    await storage.saveFromTemp(tempImage.path);

    final paths = await storage.listAllRelativePaths();
    expect(paths.length, 4); // 2 × (main + thumb)

    final usage = await storage.photosDiskUsage();
    expect(usage, greaterThan(0));
  });

  test('存储层压缩长边，PNG 转 JPEG，且不放大小图', () async {
    final large = img.Image(width: 2400, height: 1200);
    final png = File('${tempImage.parent.path}/large.png')
      ..writeAsBytesSync(img.encodePng(large));
    final saved = await storage.saveFromTemp(png.path);
    final mainBytes = await (await storage.fileFor(saved.relativePath))
        .readAsBytes();
    final main = img.decodeJpg(mainBytes)!;
    final thumb = img.decodeJpg(
      await (await storage.fileFor(saved.thumbnailRelativePath!)).readAsBytes(),
    )!;
    expect(main.width, 2048);
    expect(main.height, 1024);
    expect(thumb.width, 480);
    expect(thumb.height, 240);
    final small = await storage.saveFromTemp(tempImage.path);
    final smallThumb = img.decodeJpg(
      await (await storage.fileFor(small.thumbnailRelativePath!)).readAsBytes(),
    )!;
    expect(smallThumb.width, 120);
  });

  test('主图和缩略图校正 EXIF 方向并删除设备、GPS 元数据', () async {
    final image = img.Image(width: 120, height: 80);
    image.exif.imageIfd.orientation = 6;
    image.exif.imageIfd[0x010f] = 'Private camera';
    image.exif.gpsIfd[1] = 'N';
    await tempImage.writeAsBytes(img.encodeJpg(image));
    final saved = await storage.saveFromTemp(tempImage.path);
    for (final path in [saved.relativePath, saved.thumbnailRelativePath!]) {
      final decoded = img.decodeJpg(
        await (await storage.fileFor(path)).readAsBytes(),
      )!;
      expect(decoded.width, 80);
      expect(decoded.height, 120);
      expect(decoded.exif.isEmpty, isTrue);
    }
  });

  test('所有读写入口拒绝照片目录外路径', () async {
    for (final path in [
      '../evil.jpg',
      'photos/../../evil.jpg',
      '/tmp/evil.jpg',
      'photos/./evil.jpg',
      r'photos\evil.jpg',
      'photos/C:/evil.jpg',
    ]) {
      await expectLater(storage.fileFor(path), throwsFormatException);
      await expectLater(
        storage.writeFile(path, Uint8List(0)),
        throwsFormatException,
      );
    }
  });

  test('损坏图片保存失败并清理半成品', () async {
    await tempImage.writeAsBytes([1, 2, 3]);
    await expectLater(
      storage.saveFromTemp(tempImage.path),
      throwsA(isA<PhotoStorageException>()),
    );
    expect(await storage.listAllRelativePaths(), isEmpty);
  });

  test('writeFile（恢复备份用）：创建目录并写入', () async {
    const rel = 'photos/2026/10/test_uuid.jpg';
    await storage.writeFile(rel, Uint8List.fromList([1, 2, 3, 4]));
    final f = await storage.fileFor(rel);
    expect(await f.exists(), isTrue);
    expect(await f.length(), 4);
  });
}
