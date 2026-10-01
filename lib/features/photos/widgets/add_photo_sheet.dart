import 'package:flutter/material.dart';

/// 添加照片的来源。
enum PhotoSource { camera, gallery }

/// 底部弹窗：拍照 / 从照片图库选择 / 取消。
/// 用户取消或下滑返回 null。
Future<PhotoSource?> showAddPhotoSheet(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<PhotoSource>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '添加照片',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(ctx).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从照片图库选择'),
              onTap: () => Navigator.of(ctx).pop(PhotoSource.gallery),
            ),
            ListTile(
              leading: Icon(
                Icons.close_rounded,
                color: scheme.onSurfaceVariant,
              ),
              title: const Text('取消'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
