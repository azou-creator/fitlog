import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide Column, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:fitlog/core/storage/photo_storage_service.dart';
import 'package:fitlog/database/app_database.dart';
import 'package:fitlog/database/database_provider.dart';
import 'package:fitlog/database/photo_repository.dart';
import 'package:fitlog/features/body/body_photos_page.dart';
import 'package:fitlog/features/photos/photo_viewer_page.dart';
import 'package:fitlog/features/photos/photo_providers.dart';
import 'package:fitlog/features/photos/photo_actions.dart';
import 'package:fitlog/features/photos/widgets/add_photo_sheet.dart';
import 'package:fitlog/features/photos/workout_photos_section.dart';
import 'package:fitlog/core/constants/photo_types.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late PhotoStorageService storage;
  late List<Photo> photos;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('fitlog_ui');
    storage = PhotoStorageService(root);
    for (var i = 0; i < 3; i++) {
      await db
          .into(db.photos)
          .insert(
            PhotosCompanion.insert(
              photoType: 'body_front',
              relativePath: 'photos/$i.jpg',
              thumbnailRelativePath: Value('photos/${i}_thumb.jpg'),
              takenAt: DateTime(2026, 10, 1),
            ),
          );
    }
    photos = await db.select(db.photos).get();
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pump();
  }

  Future<void> open(
    WidgetTester tester,
    Widget page, {
    ThemeMode mode = ThemeMode.light,
  }) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => page)],
    );
    addTearDown(router.dispose);
    final bodyRows = await db.select(db.photos).get();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          photoStorageServiceProvider.overrideWithValue(storage),
          bodyPhotosProvider.overrideWith((ref) => Stream.value(bodyRows)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          themeMode: mode,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('查看器翻页更新编号，删除末页后索引有效且 DB 更新', (tester) async {
    await open(
      tester,
      PhotoViewerPage(args: (photos: photos, initialIndex: 0)),
    );
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await settle(tester);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await settle(tester);
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('删除'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await settle(tester);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(await db.select(db.photos).get(), hasLength(2));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('查看器夹紧非法初始页，缺失原图显示占位', (tester) async {
    await open(
      tester,
      PhotoViewerPage(args: (photos: photos, initialIndex: 99)),
    );
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('照片文件不存在'), findsWidgets);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('身体记录空状态在深色模式显示隐私提示和添加入口', (tester) async {
    await db.delete(db.photos).go();
    await open(tester, const BodyPhotosPage(), mode: ThemeMode.dark);
    expect(find.text('还没有身体记录'), findsOneWidget);
    expect(find.text('添加第一张照片'), findsOneWidget);
    expect(find.text('照片仅保存在此设备，不会上传服务器。'), findsOneWidget);
    await tester.tap(find.text('添加第一张照片'));
    await settle(tester);
    for (final label in ['正面', '侧面', '背面', '其他']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('图库保存等待期间退出页面，完成后没有访问已销毁 WidgetRef', (tester) async {
    final actions = _ControlledActions(PhotoRepository(db, storage), storage);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoActionsProvider.overrideWithValue(actions),
          workoutPhotosProvider(1).overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WorkoutPhotosSection(sessionId: 1)),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('添加照片'));
    await settle(tester);
    await tester.tap(find.text('从照片图库选择'));
    await settle(tester);
    expect(actions.started, isTrue);
    await finish(tester);
    actions.result.complete((saved: 1, failed: 1));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同日大量身体照片使用缩略图行，窄屏不溢出', (tester) async {
    for (var i = 3; i < 60; i++) {
      await db
          .into(db.photos)
          .insert(
            PhotosCompanion.insert(
              photoType: 'body_front',
              relativePath: 'photos/$i.jpg',
              thumbnailRelativePath: Value('photos/${i}_thumb.jpg'),
              takenAt: DateTime(2026, 10, 1),
            ),
          );
    }
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, const BodyPhotosPage());
    expect(find.text('正面'), findsOneWidget);
    expect(find.byType(Image).evaluate().length, lessThan(30));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}

class _ControlledActions extends PhotoActions {
  _ControlledActions(PhotoRepository repository, PhotoStorageService storage)
    : super(repository, storage, ImagePicker());
  final result = Completer<({int saved, int failed})>();
  bool started = false;
  @override
  Future<({int saved, int failed})> addPhotos({
    required PhotoSource source,
    required PhotoType type,
    int? workoutSessionId,
  }) {
    started = true;
    return result.future;
  }
}
