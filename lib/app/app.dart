import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/theme_controller.dart';
import '../features/workout/active_workout.dart';
import 'router.dart';
import 'theme.dart';

class FitLogApp extends ConsumerStatefulWidget {
  const FitLogApp({super.key});

  @override
  ConsumerState<FitLogApp> createState() => _FitLogAppState();
}

class _FitLogAppState extends ConsumerState<FitLogApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // P0：输入后立刻锁屏 / 切后台时，把尚未落库的修改尽快写入数据库。
    // 没有 pending 内容时 flush 是空操作，不会造成重复写入。
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(
        ref.read(activeWorkoutProvider.notifier).flushPendingChanges(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: '训练日志',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
