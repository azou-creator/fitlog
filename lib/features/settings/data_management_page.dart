import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/data_change_provider.dart';
import '../../core/providers/shared_prefs_provider.dart';
import '../../database/backup_repository.dart';
import '../../database/database_provider.dart';
import '../../shared/widgets/confirm_dialog.dart';
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
class DataManagementPage extends ConsumerWidget {
  const DataManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dataStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
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
                  title: const Text('导出数据（JSON）'),
                  subtitle: const Text('通过分享面板保存到文件 / iCloud / AirDrop'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _export(context, ref),
                ),
                const Divider(indent: 16),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导入备份'),
                  subtitle: const Text('选择之前导出的 JSON，覆盖当前数据'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _import(context, ref),
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
            onPressed: () => _clearAll(context, ref),
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

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(backupRepositoryProvider);
      final themeMode = ref.read(sharedPrefsProvider).getString('theme_mode');
      final json = await repo.exportToJson(themeMode: themeMode);

      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'fitlog_backup_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(repo.encodePretty(json), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '训练日志 数据备份 $fileName',
          subject: '训练日志 数据备份',
        ),
      );
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  // ============ 导入 ============

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (pickedFiles.isEmpty) return;
    final picked = pickedFiles.first;

    final repo = ref.read(backupRepositoryProvider);

    Map<String, dynamic> json;
    try {
      json = repo.decode(utf8.decode(await picked.readAsBytes()));
      repo.validateSchema(json);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '无法读取备份文件：${e is FormatException ? e.message : '格式不正确'}',
          ),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final nSessions = (json['workoutSessions'] as List?)?.length ?? 0;
    final nRuns = (json['runningRecords'] as List?)?.length ?? 0;
    final nSets = (json['workoutSets'] as List?)?.length ?? 0;

    final confirmed = await showConfirmDialog(
      context,
      title: '导入并覆盖当前数据？',
      content:
          '备份包含 $nSessions 次力量训练（$nSets 组）和 $nRuns 次跑步。\n\n注意：当前本机的全部记录将被替换，且无法恢复。',
      confirmText: '覆盖导入',
    );
    if (!confirmed) return;

    try {
      repo.onThemeRestored = (mode) {
        final theme = ThemeMode.values.asNameMap()[mode];
        if (theme != null) {
          ref.read(themeModeProvider.notifier).set(theme);
        }
      };
      await repo.importFromJson(json);
      messenger.showSnackBar(const SnackBar(content: Text('导入完成')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('导入失败，当前数据未变更')));
    }
  }

  // ============ 清空 ============

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final confirmed = await showConfirmDialog(
      context,
      title: '清空所有数据？',
      content: '训练、跑步、动作数据将全部删除，且无法恢复。请确认你已经不需要这些数据。',
      confirmText: '全部删除',
    );
    if (!confirmed || !context.mounted) return;

    final confirmedAgain = await showConfirmDialog(
      context,
      title: '再次确认',
      content: '真的要删除全部数据吗？此操作不可撤销。',
      confirmText: '确认删除',
    );
    if (!confirmedAgain) return;

    try {
      final db = ref.read(appDatabaseProvider);
      await db.transaction(() async {
        await db.delete(db.workoutSets).go();
        await db.delete(db.workoutExercises).go();
        await db.delete(db.workoutSessions).go();
        await db.delete(db.runningRecords).go();
        await db.delete(db.exercises).go();
      });
      messenger.showSnackBar(const SnackBar(content: Text('已清空全部数据')));
      router.pop();
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('清空失败，请重试')));
    }
  }
}
