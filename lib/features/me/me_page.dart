import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../settings/theme_controller.dart';

/// 我的：统计入口 / 数据管理 / 设置 / 关于。
class MePage extends ConsumerWidget {
  const MePage({super.key});

  String _modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.insights_rounded),
                  title: const Text('数据统计'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/stats'),
                ),
                const Divider(indent: 16),
                ListTile(
                  leading: const Icon(Icons.storage_rounded),
                  title: const Text('数据管理'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/data'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 工具
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '工具',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.monitor_weight_outlined),
                  title: const Text('重量换算'),
                  subtitle: const Text('lb ↔ kg 辅助计算器'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/tools/weight-converter'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: const Text('外观'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _modeLabel(themeMode),
                        style: TextStyle(
                            fontSize: 15, color: scheme.onSurfaceVariant),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () => _showAppearanceSheet(context, ref, themeMode),
                ),
                const Divider(indent: 16),
                ListTile(
                  leading: const Icon(Icons.fitness_center_rounded),
                  title: const Text('重量单位'),
                  trailing: Text('kg',
                      style: TextStyle(
                          fontSize: 15, color: scheme.onSurfaceVariant)),
                ),
                const Divider(indent: 16),
                ListTile(
                  leading: const Icon(Icons.straighten_rounded),
                  title: const Text('距离单位'),
                  trailing: Text('km',
                      style: TextStyle(
                          fontSize: 15, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: '训练日志',
                applicationVersion: '1.1.0',
                applicationIcon: Icon(
                  Icons.fitness_center_rounded,
                  size: 40,
                  color: scheme.primary,
                ),
                children: const [
                  Text('个人健身 / 跑步训练日记。\n所有数据保存在本机，无需联网。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAppearanceSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('外观',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final mode in ThemeMode.values)
              ListTile(
                title: Text(_modeLabelStatic(mode)),
                trailing: mode == current
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(themeModeProvider.notifier).set(mode);
                  Navigator.of(ctx).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _modeLabelStatic(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
    }
  }
}
