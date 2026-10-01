import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/photo_types.dart';
import '../../core/utils/formatters.dart';
import '../../database/app_database.dart' show Photo;
import '../../shared/widgets/empty_state.dart';
import '../photos/photo_actions.dart';
import '../photos/photo_providers.dart';
import '../photos/widgets/add_photo_sheet.dart';
import '../photos/widgets/photo_thumbnail.dart';

/// 身体记录独立于训练，按月、日期和部位展示，只构建可见的缩略图行。
class BodyPhotosPage extends ConsumerStatefulWidget {
  const BodyPhotosPage({super.key});
  @override
  ConsumerState<BodyPhotosPage> createState() => _BodyPhotosPageState();
}

class _BodyPhotosPageState extends ConsumerState<BodyPhotosPage> {
  bool _adding = false;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(bodyPhotosProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('身体记录')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adding ? null : _addPhoto,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(_saving ? '保存中' : '添加照片'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '照片仅保存在此设备，不会上传服务器。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: photosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => EmptyState(
                icon: Icons.error_outline_rounded,
                title: '加载失败',
                actionLabel: '重试',
                onAction: () => ref.invalidate(bodyPhotosProvider),
              ),
              data: (photos) {
                if (photos.isEmpty) {
                  return EmptyState(
                    icon: Icons.accessibility_new_outlined,
                    title: '还没有身体记录',
                    subtitle: '定期在相似光线、角度和距离下拍照，更容易观察长期变化。',
                    actionLabel: '添加第一张照片',
                    onAction: _adding ? null : _addPhoto,
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 600 ? 3 : 2;
                    final entries =
                        <({String? title, int level, List<Photo> photos})>[];
                    String? month;
                    String? day;
                    String? type;
                    var chunk = <Photo>[];
                    void flush() {
                      if (chunk.isNotEmpty) {
                        entries.add((title: null, level: 0, photos: chunk));
                        chunk = [];
                      }
                    }

                    for (final photo in photos) {
                      final nextMonth = formatMonthTitle(photo.takenAt);
                      final nextDay =
                          '${photo.takenAt.year}-${photo.takenAt.month}-${photo.takenAt.day}';
                      if (nextDay != day || type != photo.photoType) flush();
                      if (month != nextMonth) {
                        entries.add((title: nextMonth, level: 0, photos: []));
                        month = nextMonth;
                      }
                      if (day != nextDay) {
                        entries.add((
                          title: formatMonthDay(photo.takenAt),
                          level: 1,
                          photos: [],
                        ));
                        day = nextDay;
                        type = null;
                      }
                      if (type != photo.photoType) {
                        entries.add((
                          title: PhotoType.fromDb(photo.photoType).label,
                          level: 2,
                          photos: [],
                        ));
                        type = photo.photoType;
                      }
                      chunk.add(photo);
                      if (chunk.length == columns) flush();
                    }
                    flush();
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry.title != null) {
                          return Padding(
                            padding: EdgeInsets.only(
                              top: entry.level == 0 ? 20 : 12,
                              bottom: 8,
                            ),
                            child: Text(
                              entry.title!,
                              style: TextStyle(
                                fontSize: entry.level == 1 ? 16 : 14,
                                fontWeight: entry.level == 2
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                                color: entry.level == 1
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < columns; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: i >= entry.photos.length
                                      ? const SizedBox.shrink()
                                      : Semantics(
                                          button: true,
                                          label:
                                              '查看${PhotoType.fromDb(entry.photos[i].photoType).label}照片',
                                          child: GestureDetector(
                                            onTap: () => _openViewer(
                                              photos,
                                              entry.photos[i],
                                            ),
                                            child: PhotoThumbnail(
                                              photo: entry.photos[i],
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openViewer(List<Photo> photos, Photo target) {
    context.push(
      '/photo-viewer',
      extra: (
        photos: photos,
        initialIndex: photos.indexWhere((p) => p.id == target.id),
      ),
    );
  }

  Future<void> _addPhoto() async {
    if (_adding) return;
    final actions = ref.read(photoActionsProvider);
    setState(() => _adding = true);
    try {
      final type = await _pickBodyType();
      if (type == null || !mounted) return;
      final source = await showAddPhotoSheet(context);
      if (source == null || !mounted) return;
      setState(() => _saving = true);
      final result = await actions.addPhotos(source: source, type: type);
      if (mounted && result.failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.saved > 0
                  ? '已保存 ${result.saved} 张，${result.failed} 张处理失败，请重新选择。'
                  : '照片处理失败，请重新选择。',
            ),
          ),
        );
      }
    } on PhotoActionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      debugPrint('身体照片添加失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('照片处理失败，请重新选择。')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _adding = false;
          _saving = false;
        });
      }
    }
  }

  Future<PhotoType?> _pickBodyType() => showModalBottomSheet<PhotoType>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                '选择照片类型',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final type in PhotoType.values.where((t) => t.isBody))
              ListTile(
                leading: const Icon(Icons.accessibility_new_outlined),
                title: Text(type.label),
                onTap: () => Navigator.of(ctx).pop(type),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}
