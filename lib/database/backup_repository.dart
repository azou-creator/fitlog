import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/photo_storage_service.dart';
import '../core/constants/photo_types.dart';
import 'photo_repository.dart' show photoStorageServiceProvider;
import 'app_database.dart';
import 'database_provider.dart';
import 'workout_repository.dart' show SessionStatus;

/// 备份格式版本（V1.2 起为 ZIP）：
/// - v1：纯 JSON，无照片（Legacy，仍可恢复）
/// - v2：ZIP（backup.json + photos/ 目录全部照片文件）
const int backupFormatVersion = 2;

/// 恢复结果摘要（UI 展示用）。
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.workouts,
    required this.runs,
    required this.photos,
    required this.photoFilesCopied,
    required this.photoFilesSkipped,
    required this.legacy,
  });

  final int workouts;
  final int runs;
  final int photos;
  final int photoFilesCopied;
  final int photoFilesSkipped;
  final bool legacy;
}

/// 已通过结构、版本、路径校验且文件已暂存的备份。确认或取消后必须 dispose。
class PreparedBackup {
  PreparedBackup._(this._json, this._staged, this.summary);
  final Map<String, dynamic> _json;
  final PhotoStorageService _staged;
  final BackupRestoreResult summary;
  bool _consumed = false;
  Future<void> dispose() async {
    _consumed = true;
    try {
      await _staged.discardStagingStorage();
    } catch (e) {
      debugPrint('恢复临时文件清理失败: $e');
    }
  }
}

/// 本地备份 / 恢复。
/// 导出：JSON（元数据，含 photos 表）+ 照片二进制 → ZIP。
/// 导入：兼容 Legacy JSON（无照片）与 ZIP；「完整覆盖」语义不变。
class BackupRepository {
  BackupRepository(this._db, this._storage, [this._tempDirOverride]);

  final AppDatabase _db;
  final PhotoStorageService _storage;

  /// 测试注入：备份 ZIP 的输出目录（默认系统临时目录）。
  final Directory? _tempDirOverride;

  /// 导出 JSON 的 schema 版本（v2 起包含 photos 表）。
  static const int exportSchemaVersion = 2;

  String _iso(DateTime? d) => d?.toIso8601String() ?? '';
  DateTime _parseDate(dynamic v) => DateTime.parse(v as String);
  DateTime? _parseDateOrNull(dynamic v) =>
      (v == null || (v as String).isEmpty) ? null : DateTime.parse(v);

  // ============ JSON 构建 / 解析 ============

  Future<Map<String, dynamic>> exportToJson({String? themeMode}) =>
      _db.transaction(() => _exportToJson(themeMode: themeMode));

  Future<Map<String, dynamic>> _exportToJson({String? themeMode}) async {
    final exercises = await (_db.select(
      _db.exercises,
    )..orderBy([(e) => OrderingTerm.asc(e.id)])).get();
    final sessions = await (_db.select(
      _db.workoutSessions,
    )..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
    final wes = await (_db.select(
      _db.workoutExercises,
    )..orderBy([(u) => OrderingTerm.asc(u.id)])).get();
    final sets = await (_db.select(
      _db.workoutSets,
    )..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
    final runs = await (_db.select(
      _db.runningRecords,
    )..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
    final photos = await (_db.select(
      _db.photos,
    )..orderBy([(p) => OrderingTerm.asc(p.id)])).get();

    return {
      'backupFormatVersion': backupFormatVersion,
      'databaseSchemaVersion': _db.schemaVersion,
      'schemaVersion': exportSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': {'themeMode': ?themeMode},
      'exercises': [
        for (final e in exercises)
          {
            'id': e.id,
            'name': e.name,
            'muscleGroup': e.muscleGroup,
            'isCustom': e.isCustom,
            'createdAt': _iso(e.createdAt),
          },
      ],
      'workoutSessions': [
        for (final s in sessions)
          {
            'id': s.id,
            'name': s.name,
            'startTime': _iso(s.startTime),
            'endTime': _iso(s.endTime),
            'durationSeconds': s.durationSeconds,
            'status': s.status,
            'note': s.note,
            'createdAt': _iso(s.createdAt),
            'updatedAt': _iso(s.updatedAt),
          },
      ],
      'workoutExercises': [
        for (final u in wes)
          {
            'id': u.id,
            'workoutSessionId': u.workoutSessionId,
            'exerciseId': u.exerciseId,
            'sortOrder': u.sortOrder,
            'note': u.note,
          },
      ],
      'workoutSets': [
        for (final s in sets)
          {
            'id': s.id,
            'workoutExerciseId': s.workoutExerciseId,
            'setOrder': s.setOrder,
            'weight': s.weight,
            'reps': s.reps,
            'rpe': s.rpe,
            'note': s.note,
            'createdAt': _iso(s.createdAt),
          },
      ],
      'runningRecords': [
        for (final r in runs)
          {
            'id': r.id,
            'date': _iso(r.date),
            'distanceKm': r.distanceKm,
            'durationSeconds': r.durationSeconds,
            'averageHeartRate': r.averageHeartRate,
            'note': r.note,
            'createdAt': _iso(r.createdAt),
            'updatedAt': _iso(r.updatedAt),
          },
      ],
      'photos': [
        for (final p in photos)
          {
            'id': p.id,
            'workoutSessionId': p.workoutSessionId,
            'photoType': p.photoType,
            'relativePath': p.relativePath,
            'thumbnailRelativePath': p.thumbnailRelativePath,
            'takenAt': _iso(p.takenAt),
            'note': p.note,
            'createdAt': _iso(p.createdAt),
            'updatedAt': _iso(p.updatedAt),
          },
      ],
    };
  }

  String encodePretty(Map<String, dynamic> json) =>
      const JsonEncoder.withIndent('  ').convert(json);

  Map<String, dynamic> decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份文件格式不正确');
    }
    return decoded;
  }

  /// 校验 schema 版本。过高（新版本导出的文件）则拒绝导入。
  void validateSchema(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version is! int || version < 1 || version > exportSchemaVersion) {
      throw const FormatException('备份文件来自更新版本的应用，请先升级 App 再导入');
    }
  }

  // ============ ZIP 导出 ============

  /// 按文件写 ZIP，避免一次把所有照片二进制读入内存。
  Future<(File, int)> exportBackupZip({
    String? themeMode,
  }) => _storage.runExclusive(() async {
    final json = await exportToJson(themeMode: themeMode);
    final dir = _tempDirOverride ?? await getTemporaryDirectory();
    final output = await dir.createTemp('fitlog_backup_');
    final now = DateTime.now();
    final file = File(
      '${output.path}/fitlog_backup_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(file.path);
    var skipped = 0;
    try {
      encoder.addArchiveFile(
        ArchiveFile.string('backup.json', encodePretty(json)),
      );
      for (final rel in _photoPaths(json)) {
        final photo = await _storage.fileFor(rel);
        if (!await photo.exists()) {
          skipped++;
          continue;
        }
        // 文件存在但读写失败属于导出失败，不能产生不可用 ZIP 并误报成功。
        await encoder.addFile(photo, rel);
      }
    } catch (e) {
      await encoder.close();
      await output.delete(recursive: true);
      rethrow;
    }
    await encoder.close();
    return (file, skipped);
  });

  // ============ 预检 / 暂存 / 确认恢复 ============

  Future<BackupRestoreResult> importBackup(
    File file, {
    void Function(String themeMode)? onThemeRestored,
  }) async {
    final prepared = await prepareBackup(file);
    try {
      return await restorePrepared(prepared, onThemeRestored: onThemeRestored);
    } finally {
      await prepared.dispose();
    }
  }

  Future<BackupRestoreResult> importFromZip(
    File file, {
    void Function(String themeMode)? onThemeRestored,
  }) => importBackup(file, onThemeRestored: onThemeRestored);

  /// 在用户确认前校验完整元数据并暂存文件，当前 DB / photos 不受影响。
  Future<PreparedBackup> prepareBackup(File file) async {
    final staged = await _storage.createStagingStorage();
    InputFileStream? input;
    try {
      final legacy = !file.path.toLowerCase().endsWith('.zip');
      late final Map<String, dynamic> json;
      Archive? archive;
      if (legacy) {
        json = decode(await file.readAsString());
      } else {
        input = InputFileStream(file.path);
        final decoder = ZipDecoder();
        archive = decoder.decodeStream(input);
        // archive 会合并重复名字，因此必须检查原始 ZIP headers。
        final names = <String>{};
        for (final header in decoder.directory.fileHeaders) {
          if (!names.add(header.file!.filename)) {
            throw const FormatException('备份包含重复文件路径，已拒绝恢复');
          }
        }
        _validateZipEntries(archive);
        final entry = archive.findFile('backup.json');
        if (entry == null || !entry.isFile) {
          throw const FormatException('备份缺少 backup.json，已拒绝恢复');
        }
        json = decode(utf8.decode(_readEntry(entry)));
        entry.clear();
      }
      _validatePayload(json, legacy: legacy);
      var copied = 0;
      var skipped = 0;
      for (final path in _photoPaths(json)) {
        final entry = archive?.findFile(path);
        if (entry == null || !entry.isFile) {
          skipped++;
          continue;
        }
        await staged.writeFile(path, _readEntry(entry));
        entry.clear();
        copied++;
      }
      return PreparedBackup._(
        json,
        staged,
        BackupRestoreResult(
          workouts: (json['workoutSessions'] as List).length,
          runs: (json['runningRecords'] as List).length,
          photos: (json['photos'] as List? ?? []).length,
          photoFilesCopied: copied,
          photoFilesSkipped: skipped,
          legacy: legacy,
        ),
      );
    } catch (e) {
      try {
        await staged.discardStagingStorage();
      } catch (cleanupError) {
        debugPrint('恢复暂存清理失败: $cleanupError');
      }
      if (e is FormatException || e is FileSystemException) rethrow;
      debugPrint('备份校验失败: $e');
      throw const FormatException('备份文件已损坏或格式不正确，无法恢复');
    } finally {
      await input?.close();
    }
  }

  Uint8List _readEntry(ArchiveFile entry) {
    // 在解压前拒绝异常大单文件，防止损坏备份耗尽内存；总照片按张处理。
    if (entry.size > 64 * 1024 * 1024) {
      throw const FormatException('备份中的单个文件过大，无法恢复');
    }
    final bytes = Uint8List.fromList(entry.content as List<int>);
    if (bytes.length != entry.size ||
        (entry.crc32 != null && getCrc32(bytes) != entry.crc32)) {
      throw const FormatException('备份文件已损坏，无法恢复');
    }
    return bytes;
  }

  void _validateZipEntries(Archive archive) {
    for (final entry in archive.files) {
      final name = entry.name;
      final segments =
          (name.endsWith('/') ? name.substring(0, name.length - 1) : name)
              .split('/');
      if (name.contains('\\') ||
          name.contains(':') ||
          name.contains(RegExp(r'[\x00-\x1f]')) ||
          segments.any((s) => s.isEmpty || s == '.' || s == '..') ||
          entry.isSymbolicLink ||
          (entry.mode & 0xf000) == 0xa000) {
        throw const FormatException('备份包含非法路径，已拒绝恢复');
      }
    }
  }

  Set<String> _photoPaths(Map<String, dynamic> json) => {
    for (final raw in (json['photos'] as List? ?? [])) ...[
      (raw as Map<String, dynamic>)['relativePath'] as String,
      ?raw['thumbnailRelativePath'] as String?,
    ],
  };

  Future<BackupRestoreResult> restorePrepared(
    PreparedBackup prepared, {
    void Function(String themeMode)? onThemeRestored,
  }) => _storage.runExclusive(() async {
    if (prepared._consumed) throw StateError('备份已恢复或已取消');
    prepared._consumed = true;
    await _storage.replacePhotosFrom(
      prepared._staged,
      () => _restoreDatabase(prepared._json),
    );
    _notifyTheme(prepared._json, onThemeRestored);
    return prepared.summary;
  });

  void _notifyTheme(
    Map<String, dynamic> json,
    void Function(String)? callback,
  ) {
    final theme = (json['settings'] as Map?)?['themeMode'] as String?;
    if (theme != null) {
      try {
        callback?.call(theme);
      } catch (e) {
        debugPrint('外观设置恢复失败: $e');
      }
    }
  }

  void _validatePayload(Map<String, dynamic> json, {required bool legacy}) {
    validateSchema(json);
    for (final (key, max) in [
      ('backupFormatVersion', backupFormatVersion),
      ('databaseSchemaVersion', _db.schemaVersion),
    ]) {
      final value = json[key];
      if ((!legacy || value != null) &&
          (value is! int || value < 1 || value > max)) {
        throw const FormatException('备份来自更新版本或版本无效，请检查文件或升级 App');
      }
    }
    final settings = json['settings'];
    if (settings != null &&
        (settings is! Map ||
            (settings['themeMode'] != null &&
                ![
                  'light',
                  'dark',
                  'system',
                ].contains(settings['themeMode'])))) {
      throw const FormatException('备份中的设置格式不正确');
    }
    const tables = [
      'exercises',
      'workoutSessions',
      'workoutExercises',
      'workoutSets',
      'runningRecords',
      'photos',
    ];
    final ids = <String, Set<int>>{};
    final rows = <String, List<Map<String, dynamic>>>{};
    void invalid() => throw const FormatException('备份数据结构不完整或字段无效，已拒绝恢复');
    for (final table in tables) {
      final list = json[table];
      if (list == null && table == 'photos' && legacy) {
        rows[table] = [];
        ids[table] = {};
        continue;
      }
      if (list is! List) invalid();
      rows[table] = [];
      ids[table] = {};
      for (final item in list as List) {
        if (item is! Map<String, dynamic>) invalid();
        final row = item as Map<String, dynamic>;
        final id = row['id'];
        if (id is! int || id <= 0 || !ids[table]!.add(id)) invalid();
        for (final key in ['note']) {
          if (row[key] != null && row[key] is! String) invalid();
        }
        for (final key in ['createdAt', 'updatedAt', 'endTime']) {
          final date = row[key];
          if (date != null &&
              (date is! String ||
                  (date.isNotEmpty && DateTime.tryParse(date) == null))) {
            invalid();
          }
        }
        rows[table]!.add(row);
      }
    }
    void text(
      Map<String, dynamic> r,
      String key, {
      int? max,
      bool allowEmpty = false,
    }) {
      final value = r[key];
      if (value is! String ||
          (!allowEmpty && value.isEmpty) ||
          (max != null && value.length > max)) {
        invalid();
      }
    }

    void date(Map<String, dynamic> r, String key) {
      if (r[key] is! String || DateTime.tryParse(r[key] as String) == null) {
        invalid();
      }
    }

    void number(Map<String, dynamic> r, String key, {bool integer = false}) {
      final v = r[key];
      if (v != null &&
          (v is! num || !v.isFinite || v < 0 || (integer && v is! int))) {
        invalid();
      }
    }

    void reference(Map<String, dynamic> r, String key, String table) {
      if (r[key] is! int || !ids[table]!.contains(r[key])) invalid();
    }

    for (final r in rows['exercises']!) {
      text(r, 'name', max: 50);
      text(r, 'muscleGroup', max: 20);
      if (r['isCustom'] != null && r['isCustom'] is! bool) invalid();
    }
    for (final r in rows['workoutSessions']!) {
      text(r, 'name', allowEmpty: true);
      date(r, 'startTime');
      number(r, 'durationSeconds', integer: true);
      if (r['status'] != null &&
          ![
            SessionStatus.inProgress,
            SessionStatus.completed,
          ].contains(r['status'])) {
        invalid();
      }
    }
    for (final r in rows['workoutExercises']!) {
      reference(r, 'workoutSessionId', 'workoutSessions');
      reference(r, 'exerciseId', 'exercises');
      number(r, 'sortOrder', integer: true);
    }
    for (final r in rows['workoutSets']!) {
      reference(r, 'workoutExerciseId', 'workoutExercises');
      number(r, 'setOrder', integer: true);
      number(r, 'weight');
      number(r, 'reps', integer: true);
      number(r, 'rpe');
    }
    for (final r in rows['runningRecords']!) {
      date(r, 'date');
      number(r, 'distanceKm');
      number(r, 'durationSeconds', integer: true);
      number(r, 'averageHeartRate', integer: true);
    }
    if (legacy && rows['photos']!.isNotEmpty) {
      throw const FormatException('JSON 备份缺少照片文件，请选择包含照片的 ZIP 备份');
    }
    final paths = <String>{};
    for (final r in rows['photos']!) {
      if (!PhotoType.values.any((t) => t.dbValue == r['photoType'])) invalid();
      final type = PhotoType.fromDb(r['photoType'] as String);
      if (type.isWorkout) {
        reference(r, 'workoutSessionId', 'workoutSessions');
      } else if (r['workoutSessionId'] != null) {
        invalid();
      }
      date(r, 'takenAt');
      for (final key in ['relativePath', 'thumbnailRelativePath']) {
        final value = r[key];
        if (value == null && key == 'thumbnailRelativePath') continue;
        if (value is! String || !paths.add(value)) invalid();
        PhotoStorageService.validateRelativePath(value as String);
      }
    }
  }

  // ============ 覆盖恢复（DB） ============

  /// 完整恢复：清空现有数据后写入备份内容（在一个事务中，失败即整体回滚）。
  Future<void> importFromJson(
    Map<String, dynamic> json, {
    void Function(String themeMode)? onThemeRestored,
  }) => _storage.runExclusive(() async {
    _validatePayload(json, legacy: true);
    final staged = await _storage.createStagingStorage();
    try {
      await _storage.replacePhotosFrom(staged, () => _restoreDatabase(json));
      _notifyTheme(json, onThemeRestored);
    } finally {
      await staged.discardStagingStorage();
    }
  });

  /// 清空数据使用与恢复相同的媒体替换与数据库回滚协调。
  Future<void> clearAllData() => _storage.runExclusive(() async {
    final staged = await _storage.createStagingStorage();
    try {
      await _storage.replacePhotosFrom(
        staged,
        () => _db.transaction(_clearDatabase),
      );
    } finally {
      await staged.discardStagingStorage();
    }
  });

  Future<void> _clearDatabase() async {
    await _db.delete(_db.workoutSets).go();
    await _db.delete(_db.workoutExercises).go();
    await _db.delete(_db.photos).go();
    await _db.delete(_db.workoutSessions).go();
    await _db.delete(_db.runningRecords).go();
    await _db.delete(_db.exercises).go();
  }

  Future<void> _restoreDatabase(Map<String, dynamic> json) async {
    await _db.transaction(() async {
      await _clearDatabase();

      for (final raw in (json['exercises'] as List? ?? [])) {
        final e = raw as Map<String, dynamic>;
        await _db
            .into(_db.exercises)
            .insert(
              ExercisesCompanion.insert(
                id: Value(e['id'] as int),
                name: e['name'] as String,
                muscleGroup: e['muscleGroup'] as String,
                isCustom: Value(e['isCustom'] as bool? ?? false),
                createdAt: Value(
                  _parseDateOrNull(e['createdAt']) ?? DateTime.now(),
                ),
              ),
            );
      }

      // P0 唯一约束兜底：异常备份若含多个 inProgress，
      // 保留最新一场，其余降级为 completed，避免导入被唯一索引拒绝。
      final sessionList = (json['workoutSessions'] as List? ?? []);
      final activeEntries =
          sessionList
              .whereType<Map<String, dynamic>>()
              .where(
                (s) => (s['status'] as String?) == SessionStatus.inProgress,
              )
              .toList()
            ..sort(
              (a, b) =>
                  _parseDate(b['startTime'])
                      .compareTo(_parseDate(a['startTime'])),
            );
      final demotedIds = {
        for (final s in activeEntries.skip(1)) s['id'] as int,
      };

      for (final raw in sessionList) {
        final s = raw as Map<String, dynamic>;
        final requestedStatus =
            (s['status'] as String?) ?? SessionStatus.completed;
        await _db
            .into(_db.workoutSessions)
            .insert(
              WorkoutSessionsCompanion.insert(
                id: Value(s['id'] as int),
                name: s['name'] as String,
                startTime: _parseDate(s['startTime']),
                endTime: Value(_parseDateOrNull(s['endTime'])),
                durationSeconds: s['durationSeconds'] as int? ?? 0,
                status: Value(
                  demotedIds.contains(s['id'])
                      ? SessionStatus.completed
                      : requestedStatus,
                ),
                note: Value(s['note'] as String?),
                createdAt: Value(
                  _parseDateOrNull(s['createdAt']) ?? DateTime.now(),
                ),
                updatedAt: Value(
                  _parseDateOrNull(s['updatedAt']) ?? DateTime.now(),
                ),
              ),
            );
      }

      for (final raw in (json['workoutExercises'] as List? ?? [])) {
        final u = raw as Map<String, dynamic>;
        await _db
            .into(_db.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                id: Value(u['id'] as int),
                workoutSessionId: u['workoutSessionId'] as int,
                exerciseId: u['exerciseId'] as int,
                sortOrder: u['sortOrder'] as int? ?? 0,
                note: Value(u['note'] as String?),
              ),
            );
      }

      for (final raw in (json['workoutSets'] as List? ?? [])) {
        final s = raw as Map<String, dynamic>;
        await _db
            .into(_db.workoutSets)
            .insert(
              WorkoutSetsCompanion.insert(
                id: Value(s['id'] as int),
                workoutExerciseId: s['workoutExerciseId'] as int,
                setOrder: s['setOrder'] as int? ?? 0,
                weight: (s['weight'] as num?)?.toDouble() ?? 0,
                reps: s['reps'] as int? ?? 0,
                rpe: Value((s['rpe'] as num?)?.toDouble()),
                note: Value(s['note'] as String?),
                createdAt: Value(
                  _parseDateOrNull(s['createdAt']) ?? DateTime.now(),
                ),
              ),
            );
      }

      for (final raw in (json['runningRecords'] as List? ?? [])) {
        final r = raw as Map<String, dynamic>;
        await _db
            .into(_db.runningRecords)
            .insert(
              RunningRecordsCompanion.insert(
                id: Value(r['id'] as int),
                date: _parseDate(r['date']),
                distanceKm: (r['distanceKm'] as num?)?.toDouble() ?? 0,
                durationSeconds: r['durationSeconds'] as int? ?? 0,
                averageHeartRate: Value(r['averageHeartRate'] as int?),
                note: Value(r['note'] as String?),
                createdAt: Value(
                  _parseDateOrNull(r['createdAt']) ?? DateTime.now(),
                ),
                updatedAt: Value(
                  _parseDateOrNull(r['updatedAt']) ?? DateTime.now(),
                ),
              ),
            );
      }

      // 照片元数据（Legacy JSON 无此 key → 照片为空）
      for (final raw in (json['photos'] as List? ?? [])) {
        final p = raw as Map<String, dynamic>;
        await _db
            .into(_db.photos)
            .insert(
              PhotosCompanion.insert(
                id: Value(p['id'] as int),
                workoutSessionId: Value(p['workoutSessionId'] as int?),
                photoType: p['photoType'] as String,
                relativePath: p['relativePath'] as String,
                thumbnailRelativePath: Value(
                  p['thumbnailRelativePath'] as String?,
                ),
                takenAt: _parseDate(p['takenAt']),
                note: Value(p['note'] as String?),
                createdAt: Value(
                  _parseDateOrNull(p['createdAt']) ?? DateTime.now(),
                ),
                updatedAt: Value(_parseDateOrNull(p['updatedAt'])),
              ),
            );
      }
    });
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

final backupRepositoryProvider = Provider<BackupRepository>(
  (ref) => BackupRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(photoStorageServiceProvider),
  ),
);
