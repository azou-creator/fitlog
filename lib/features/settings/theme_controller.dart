import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/shared_prefs_provider.dart';

class ThemeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_key);
    return ThemeMode.values.asNameMap()[raw] ?? ThemeMode.system;
  }

  void set(ThemeMode mode) {
    ref.read(sharedPrefsProvider).setString(_key, mode.name);
    state = mode;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
