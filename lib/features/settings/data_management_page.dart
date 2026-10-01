import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/data_change_provider.dart';
import '../../core/providers/shared_prefs_provider.dart';
import '../../database/backup_repository.dart';
import '../../database/database_provider.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../database/workout_repository.dart';
import '../workout/active_workout.dart';
import 'theme_controller.dart';

class DataStats {
  const DataStats({
    required this.exercises,
    required this.customExercises,
    required this.workouts,
    required this.sets,
    required this.runs,
  });

  final int exercises;
  final int customExercises;
  final int workouts;
  final int sets;
  final int runs;
}

final dataStatsProvider = FutureProvider<DataStats>((ref) async {
  ref.watch(dataChangeProvider);
  final db = ref.watch(appDatabaseProvider);

  Future<int> tableCount(TableInfo table, Expression<int> exp) async {
    final q = db.selectOnly(table)..addColumns([exp]);
    final row = await q.getSingle();
    return row.read(exp) ?? 0;
  }

  final exp = countAll();

  final customExp = countAll();
  final customQuery = db.selectOnly(db.exercises)
    ..addColumns([customExp])
    ..where(db.exercises.isCustom.equals(true));
  final customRow = await customQuery.getSingle();

  return DataStats(
    exercises: await tableCount(db.exercises, exp),
    customExercises: customRow.read(customExp) ?? 0,
    workouts: await tableCount(db.workoutSessions, exp),
    sets: await tableCount(db.workoutSets, exp),
    runs: await tableCount(db.runningRecords, exp),
  );
});

/// 数据管理：数据规模 + 备份/恢复 + 清空。
class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(dataStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          statsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => const Text('加载失败'),
            data: (s) => Card(
              child: Column(
                children: [
                  _row(
                    context,
                    '动作',
                    '${s.exercises} 个（自定义 ${s.customExercises} 个）',
                  ),
                  const Divider(indent: 16),
                  _row(context, '力量训练', '${s.workouts} 次 · ${s.sets} 组'),
                  const Divider(indent: 16),
                  _row(context, '跑步记录', '${s.runs} 次'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('导出备份（ZIP）'),
                  subtitle: const Text('包含训练和照片，可保存到文件 / iCloud'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : _export,
                ),
                const Divider(indent: 16),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导入备份'),
                  subtitle: const Text('支持 ZIP 和旧 JSON，替换当前记录和照片'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : _import,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _busy ? null : _clearAll,
            child: const Text('清空所有数据'),
          ),
          const SizedBox(height: 8),
          Text(
            '所有数据仅保存在本机 App 沙盒中。建议定期导出备份；卸载 App 或清空数据后无法恢复。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ============ 导出 ============

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    final repo = ref.read(backupRepositoryProvider);
    final themeMode = ref.read(sharedPrefsProvider).getString('theme_mode');
    final active = ref.read(activeWorkoutProvider.notifier);
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox == null
        ? null
        : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    setState(() => _busy = true);
    try {
      await active.flushPendingChanges();
      final (file, skipped) = await repo.exportBackupZip(themeMode: themeMode);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '训练日志 数据备份',
          subject: '训练日志 数据备份',
          sharePositionOrigin: origin,
        ),
      );
      if (skipped > 0) _message('备份完成，但有 $skipped 个缺失照片文件未包含。');
    } catch (e) {
      debugPrint('备份导出失败: $e');
      _message('导出失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ============ 导入 ============

  Future<void> _import() async {
    if (_busy) return;
    final repo = ref.read(backupRepositoryProvider);
    final active = ref.read(activeWorkoutProvider.notifier);
    final themeController = ref.read(themeModeProvider.notifier);
    PreparedBackup? prepared;
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'json'],
      );
      if (files.isEmpty || files.first.path == null || !mounted) return;
      prepared = await repo.prepareBackup(File(files.first.path!));
      if (!mounted) return;
      final summary = prepared.summary;
      final confirmed = await showConfirmDialog(
        context,
        title: '恢复备份并替换当前数据？',
        content:
            '备份包含：训练 ${summary.workouts} 次、跑步 ${summary.runs} 次、照片 ${summary.photos} 张。'
            '${summary.legacy ? "\n这是旧 JSON 备份，不包含照片。" : ""}'
            '${summary.photoFilesSkipped > 0 ? "\n有 ${summary.photoFilesSkipped} 个照片文件缺失，恢复后将显示占位。" : ""}'
            '\n\n恢复备份将替换当前本地训练记录和照片。建议先导出当前数据备份。',
        confirmText: '恢复备份',
      );
      if (!confirmed || !mounted) return;
      await active.flushPendingChanges();
      final result = await repo.restorePrepared(
        prepared,
        onThemeRestored: (mode) {
          final theme = ThemeMode.values.asNameMap()[mode];
          if (theme != null) themeController.set(theme);
        },
      );
      active.reset();
      if (mounted) {
        ref.invalidate(sessionDetailProvider);
        _message(
          '恢复完成：训练 ${result.workouts} 次 · 跑步 ${result.runs} 次 · 照片 ${result.photos} 张'
          '${result.photoFilesSkipped > 0 ? "（缺失 ${result.photoFilesSkipped} 个照片文件）" : ""}',
        );
      }
    } on FormatException catch (e) {
      _message(e.message);
    } catch (e) {
      debugPrint('备份恢复失败: $e');
      _message('恢复失败，请检查备份文件或设备存储空间后重试');
    } finally {
      await prepared?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  // ============ 清空 ============

  Future<void> _clearAll() async {
    if (_busy) return;
    final repo = ref.read(backupRepositoryProvider);
    final active = ref.read(activeWorkoutProvider.notifier);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: '清空所有数据？',
        content: '训练、跑步、动作和所有照片将全部删除，且无法恢复。请先导出需要保留的数据备份。',
        confirmText: '全部删除',
      );
      if (!confirmed || !mounted) return;
      final confirmedAgain = await showConfirmDialog(
        context,
        title: '再次确认',
        content: '真的要删除全部记录和照片吗？此操作不可撤销。',
        confirmText: '确认删除',
      );
      if (!confirmedAgain || !mounted) return;
      await active.flushPendingChanges();
      await repo.clearAllData();
      active.reset();
      if (mounted) {
        ref.invalidate(sessionDetailProvider);
        _message('已清空全部数据和照片');
        if (router.canPop()) router.pop();
      }
    } catch (e) {
      debugPrint('清空数据失败: $e');
      _message('清空失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
