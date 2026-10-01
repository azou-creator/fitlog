import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../database/app_database.dart' show Photo;
import '../../../database/photo_repository.dart';

/// 照片缩略图：从相对路径解析实际文件，加载失败显示占位（不 Crash）。
/// 列表只用 thumbnail；主图只在 Viewer 加载。
class PhotoThumbnail extends ConsumerStatefulWidget {
  const PhotoThumbnail({
    super.key,
    required this.photo,
    this.borderRadius = 12,
  });

  final Photo photo;
  final double borderRadius;

  @override
  ConsumerState<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends ConsumerState<PhotoThumbnail> {
  Future<File>? _file;
  String? _path;
  Object? _storage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final storage = ref.watch(photoStorageServiceProvider);

    final path = widget.photo.thumbnailRelativePath;
    if (path != _path || !identical(storage, _storage)) {
      _path = path;
      _storage = storage;
      _file = path == null ? null : storage.fileFor(path);
    }
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: path == null
            ? _placeholder(scheme)
            : FutureBuilder<File>(
                future: _file,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _placeholder(scheme);
                  if (!snapshot.hasData) {
                    return _placeholder(scheme, loading: true);
                  }
                  return Image.file(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    cacheWidth: 480,
                    errorBuilder: (_, _, _) => _placeholder(scheme),
                  );
                },
              ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme, {bool loading = false}) {
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              '照片文件不存在',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
    );
  }
}
