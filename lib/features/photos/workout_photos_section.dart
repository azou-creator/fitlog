import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../database/app_database.dart' show Photo;
import '../../core/constants/photo_types.dart';
import 'photo_actions.dart';
import 'photo_providers.dart';
import 'widgets/add_photo_sheet.dart';
import 'widgets/photo_thumbnail.dart';

/// 训练详情页「训练照片」区：空状态引导 / 缩略图网格 / 添加 / 查看大图。
class WorkoutPhotosSection extends ConsumerStatefulWidget {
  const WorkoutPhotosSection({super.key, required this.sessionId});

  final int sessionId;

  @override
  ConsumerState<WorkoutPhotosSection> createState() =>
      _WorkoutPhotosSectionState();
}

class _WorkoutPhotosSectionState extends ConsumerState<WorkoutPhotosSection> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(workoutPhotosProvider(widget.sessionId));
    final scheme = Theme.of(context).colorScheme;

    return photosAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => TextButton.icon(
        onPressed: () =>
            ref.invalidate(workoutPhotosProvider(widget.sessionId)),
        icon: const Icon(Icons.refresh),
        label: const Text('训练照片加载失败，点击重试'),
      ),
      data: (photos) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '训练照片',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (photos.isNotEmpty)
                Text(
                  '${photos.length} 张',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (photos.isEmpty)
            // 空状态：不显示大片空白，引导添加
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '记录今天的训练状态。',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _addButton(context),
                  ],
                ),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < photos.length; i++)
                      GestureDetector(
                        onTap: () => _openViewer(photos, i),
                        child: SizedBox(
                          width: tileWidth,
                          child: PhotoThumbnail(photo: photos[i]),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            _addButton(context),
          ],
        ],
      ),
    );
  }

  Widget _addButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _adding ? null : _addPhoto,
      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
      label: const Text('添加照片'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
    );
  }

  void _openViewer(List<Photo> photos, int initialIndex) {
    context.push(
      '/photo-viewer',
      extra: (photos: photos, initialIndex: initialIndex),
    );
  }

  Future<void> _addPhoto() async {
    if (_adding) return;
    final actions = ref.read(photoActionsProvider);
    setState(() => _adding = true);
    try {
      final source = await showAddPhotoSheet(context);
      if (source == null || !mounted) return;
      final result = await actions.addPhotos(
        source: source,
        type: PhotoType.workout,
        workoutSessionId: widget.sessionId,
      );
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
      debugPrint('照片添加失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('照片处理失败，请重新选择。')));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }
}
