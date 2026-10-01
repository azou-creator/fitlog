import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// 在 main() 中通过 overrideWithValue 注入全局唯一实例。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider 必须在 main() 中 override');
});
