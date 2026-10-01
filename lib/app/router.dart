import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../database/app_database.dart' show Exercise;
import '../features/history/history_page.dart';
import '../features/home/home_page.dart';
import '../features/me/me_page.dart';
import '../features/record/record_page.dart';
import '../features/running/running_detail_page.dart';
import '../features/running/running_editor_page.dart';
import '../features/settings/data_management_page.dart';
import '../features/stats/stats_page.dart';
import '../features/tools/weight_converter_page.dart';
import '../features/workout/exercise_picker_page.dart';
import '../features/workout/workout_detail_page.dart';
import '../features/workout/workout_editor_page.dart';
import '../features/workout/workout_summary_page.dart';

int? _parseId(String? raw) => int.tryParse(raw ?? '');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      // 底部 4 个 Tab
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const HomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/record', builder: (_, _) => const RecordPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/me', builder: (_, _) => const MePage()),
          ]),
        ],
      ),

      // 力量训练
      GoRoute(
        path: '/workout/new',
        builder: (_, state) =>
            WorkoutEditorPage(seed: state.extra is Exercise ? state.extra as Exercise : null),
      ),
      GoRoute(
        path: '/workout/summary',
        builder: (_, state) =>
            WorkoutSummaryPage(sessionId: _parseId(state.uri.queryParameters['id']) ?? -1),
      ),
      GoRoute(
        path: '/workout/:id',
        builder: (_, state) =>
            WorkoutDetailPage(sessionId: _parseId(state.pathParameters['id']) ?? -1),
      ),
      GoRoute(
        path: '/workout/:id/edit',
        builder: (_, state) => WorkoutEditorPage(
          editSessionId: _parseId(state.pathParameters['id']),
        ),
      ),

      // 跑步
      GoRoute(path: '/running/new', builder: (_, _) => const RunningEditorPage()),
      GoRoute(
        path: '/running/:id',
        builder: (_, state) =>
            RunningDetailPage(recordId: _parseId(state.pathParameters['id']) ?? -1),
      ),
      GoRoute(
        path: '/running/:id/edit',
        builder: (_, state) => RunningEditorPage(
          editRecordId: _parseId(state.pathParameters['id']),
        ),
      ),

      // 其他
      GoRoute(path: '/exercises', builder: (_, _) => const ExercisePickerPage()),
      GoRoute(path: '/stats', builder: (_, _) => const StatsPage()),
      GoRoute(path: '/data', builder: (_, _) => const DataManagementPage()),
      GoRoute(
        path: '/tools/weight-converter',
        builder: (_, _) => const WeightConverterPage(),
      ),
    ],
  );
});

class _MainShell extends StatelessWidget {
  const _MainShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center_rounded),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: '历史',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
