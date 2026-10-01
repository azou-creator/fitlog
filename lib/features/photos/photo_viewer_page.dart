import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../database/app_database.dart' show Photo;
import '../../database/photo_repository.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'photo_providers.dart';

/// 按页加载主图，翻页、缩放及确认删除；查看器使用独立深色主题。
class PhotoViewerPage extends ConsumerStatefulWidget {
  const PhotoViewerPage({super.key, required this.args});
  final PhotoViewerArgs args;

  @override
  ConsumerState<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends ConsumerState<PhotoViewerPage> {
  late final PageController _pageController;
  late List<Photo> _photos;
  late int _index;
  bool _deleting = false;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _photos = [...widget.args.photos];
    _index = _photos.isEmpty
        ? 0
        : widget.args.initialIndex.clamp(0, _photos.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Theme.of(context).colorScheme.primary,
          brightness: Brightness.dark,
        ),
      ),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surface,
            appBar: AppBar(
              title: Text(
                _photos.isEmpty ? '暂无照片' : '${_index + 1} / ${_photos.length}',
              ),
              actions: [
                IconButton(
                  tooltip: '删除',
                  icon: _removing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                  onPressed: _deleting || _photos.isEmpty
                      ? null
                      : () => _deleteCurrent(context),
                ),
              ],
            ),
            body: _photos.isEmpty
                ? const Center(child: Text('暂无照片'))
                : PageView.builder(
                    controller: _pageController,
                    itemCount: _photos.length,
                    physics: _deleting
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (_, i) => _PhotoPage(
                      key: ValueKey(_photos[i].relativePath),
                      photo: _photos[i],
                    ),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _deleteCurrent(BuildContext dialogContext) async {
    final photo = _photos[_index];
    final repository = ref.read(photoRepositoryProvider);
    // 从弹出确认起禁用翻页和重复删除，确保删除的是正在确认的照片。
    setState(() => _deleting = true);
    try {
      final confirmed = await showConfirmDialog(
        dialogContext,
        title: '删除这张照片？',
        content: '删除后无法恢复。',
        confirmText: '删除',
      );
      if (!confirmed || !mounted) return;
      setState(() => _removing = true);
      await repository.deletePhoto(photo);
      if (!mounted) return;
      setState(() {
        _photos.removeWhere((p) => p.id == photo.id);
        _index = _photos.isEmpty ? 0 : _index.clamp(0, _photos.length - 1);
      });
      if (_photos.isEmpty && context.canPop()) {
        context.pop();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients && _photos.isNotEmpty) {
            _pageController.jumpToPage(_index);
          }
        });
      }
    } catch (e) {
      debugPrint('照片删除失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
          _removing = false;
        });
      }
    }
  }
}

class _PhotoPage extends ConsumerStatefulWidget {
  const _PhotoPage({super.key, required this.photo});
  final Photo photo;
  @override
  ConsumerState<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends ConsumerState<_PhotoPage> {
  late final Future<File> _file;
  @override
  void initState() {
    super.initState();
    _file = ref
        .read(photoStorageServiceProvider)
        .fileFor(widget.photo.relativePath);
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    maxScale: 5,
    child: Center(
      child: FutureBuilder<File>(
        future: _file,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('照片文件不存在');
          if (!snapshot.hasData) return const CircularProgressIndicator();
          return Image.file(
            snapshot.data!,
            fit: BoxFit.contain,
            cacheWidth: 2048,
            errorBuilder: (_, _, _) => const Text('照片文件不存在'),
          );
        },
      ),
    ),
  );
}
