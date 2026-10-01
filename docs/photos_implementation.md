# Fitlog 本地照片功能交付说明

本次基于已有照片代码增量完善，保留 Flutter、Riverpod、go_router、Drift 和纯本地架构。没有新增服务器、登录、云同步或图片分析。原工作区已有未提交修改，均在其基础上继续完善，没有创建新项目或提交 Git commit。

## 功能与可靠性

训练详情支持拍照、图库多选、缩略图、左右翻页、双指缩放与确认删除。身体记录位于“我的”，按月、日期、正面 / 侧面 / 背面 / 其他分类展示，使用按需构建的缩略图行。空状态、隐私说明、缺失文件占位与深色主题均保留。

添加期间退出页面后，已启动的保存流程继续完成，不再访问已销毁的 WidgetRef。取消选择没有副作用，多选部分失败会保留成功照片并给出数量提示。相机与图库权限错误分别显示中文说明。文件释放集中在存储服务中，只删除临时目录中的 picker 副本，不删除用户原文件。

## 修改文件

| 范围 | 文件 |
| --- | --- |
| 数据库与迁移 | `lib/database/app_database.dart`、通过 build_runner 生成的 `app_database.g.dart`、`tables.dart` |
| 照片业务与删除入口 | `lib/database/photo_repository.dart`、`workout_repository.dart` |
| 本地存储与类型 | `lib/core/storage/photo_storage_service.dart`、`lib/core/constants/photo_types.dart` |
| 照片 UI 与添加协调 | `lib/features/photos/photo_actions.dart`、`photo_providers.dart`、`photo_viewer_page.dart`、`workout_photos_section.dart`、`widgets/photo_thumbnail.dart`、`widgets/add_photo_sheet.dart` |
| 身体记录与入口 | `lib/features/body/body_photos_page.dart`、`lib/features/me/me_page.dart`、`lib/features/workout/workout_detail_page.dart`、`lib/app/router.dart` |
| 备份与数据管理 | `lib/database/backup_repository.dart`、`lib/features/settings/data_management_page.dart` |
| 平台与依赖 | `ios/Runner/Info.plist`、`pubspec.yaml`、`pubspec.lock`；Flutter 更新了 iOS SwiftPM 解析文件，移除了旧 SQLite 插件依赖 |
| 测试 | 下述六个照片相关测试文件 |
| 文档 | `README.md`、本文件 |

其中照片表、iOS 权限、照片依赖及多个页面在接手时已经存在。本次主要补齐迁移验证、正式生成器兼容性、图片重新编码、文件生命周期、恢复回滚和页面回归。

## 依赖

继续复用已有 `image_picker ^1.2.3`、`uuid ^4.6.0`、`archive ^4.3.0`、`image ^4.10.1`、`path_provider`，没有新增照片功能包。

当前 Dart SDK 与锁定的 Drift 2.31.0 生成器不兼容，重新生成会漏掉外键。因此将 `drift` 和 `drift_dev` 的约束更新为 `^2.35.1`，将测试直接使用的 `sqlite3` 更新为 `^3.4.0`，实际解析为 3.7.0。SQLite 3.x 使用 native assets，移除不再需要的 `sqlite3_flutter_libs`。相关 analyzer 等依赖随之更新；未升级 Riverpod、路由或图表库。

重新执行了 `dart run build_runner build --delete-conflicting-outputs`，确认外键与删除传播规则存在；没有手动编辑生成文件。当前 build_runner 提示该清理参数已移除并忽略，实际生成成功。

## Schema 与迁移

接手时 schemaVersion 已为 **4**，本次保留 **4**，没有降回 3：

- v2：训练进行中 / 已完成状态。
- v3：同一时间最多一场进行中训练的唯一索引。
- v4：photos 表。

修正了升级路径中只建 photos 表、没有创建独立照片索引的遗漏。`beforeOpen` 会修复已有 v4 库缺失的 `idx_photos_session`，并继续开启 SQLite 外键。

photos 字段：

| 字段 | 类型与用途 |
| --- | --- |
| id | INTEGER，自增主键 |
| photoType | TEXT，稳定字符串，UI 用统一 mapper 显示中文 |
| workoutSessionId | INTEGER，可空，外键引用 workout_sessions.id，ON DELETE CASCADE |
| relativePath | TEXT，主图相对路径 |
| thumbnailRelativePath | TEXT，可空，缩略图相对路径 |
| takenAt | DATETIME，App 保存的拍摄 / 添加时间 |
| note | TEXT，可空 |
| createdAt | DATETIME，默认当前时间 |
| updatedAt | DATETIME，可空 |

训练照片使用 `workout` 且必须关联训练；身体照片使用 `body_front`、`body_side`、`body_back`、`body_other` 且不可关联训练。Repository 与恢复校验都会检查这些组合。

## 照片位置与压缩

实际文件位于 `getApplicationSupportDirectory()/fitlog/photos/YYYY/MM/`。

数据库路径示例：

```text
photos/2026/10/550e8400-e29b-41d4-a716-446655440000.jpg
photos/2026/10/550e8400-e29b-41d4-a716-446655440000_thumb.jpg
```

不会保存 sandbox 绝对路径、picker 临时路径、BLOB 或长期 Base64。

picker 使用最大宽高 2048、质量 85，并关闭完整元数据请求。当前 iOS picker 的原生实现能将 HEIC / HEIF 转成可处理图片；存储服务再在后台 isolate 中解码、校正 EXIF 方向、明确删除 EXIF / GPS / 设备信息并重新编码。

- 主图：JPEG，长边最大 **2048px**，质量 **85**。
- 缩略图：JPEG，长边最大 **480px**，质量 **80**。
- 保持比例，不放大小图；保留颜色配置以减少肤色偏差。
- 列表只加载缩略图；缩略图缺失时显示占位，不回退加载原图。
- 查看器按页加载主图，限制解码尺寸。
- 不支持或损坏的输入会给出“照片处理失败，请重新选择。”，清理半成品。

## 删除与并发协调

保存先写主图和缩略图，再在数据库事务中插入元数据。插入失败时回滚新文件。

单张删除先检查 ID 与路径是否仍对应当前记录，避免旧查看器在恢复后误删复用 ID 的新照片；然后删元数据并清理文件。文件已丢失仍可删除记录，其他文件删除错误记录日志。提供孤儿文件清理 helper，不在每次启动时扫描。

`WorkoutRepository.deleteSession` 是统一删除入口，历史删除和放弃草稿均经过它：事务内收集照片路径并删除训练，SQLite 级联删元数据，之后清理主图和缩略图。UI 不再自行组合删除逻辑。

照片增删、孤儿清理、备份导出、恢复和清空数据使用同一个存储服务串行队列，避免维护操作与正在保存的照片互相覆盖。

清空数据会整体替换媒体目录并在事务中删除所有业务表；数据库清空失败时还原旧照片目录。成功后清除内存训练草稿，避免旧自动保存内容残留。

## 备份格式与恢复

默认导出 `fitlog_backup_YYYYMMDD_HHMMSS.zip`，包含：

```text
backup.json
photos/YYYY/MM/<uuid>.jpg
photos/YYYY/MM/<uuid>_thumb.jpg
```

JSON 保存照片元数据，不包含图片二进制。`backupFormatVersion = 2`、`databaseSchemaVersion = 4`，JSON 自身的 `schemaVersion = 2` 是序列化格式版本，与数据库版本分开。

导出从数据库事务读取一致快照，逐文件写 ZIP，避免一次加载全部照片。缺失文件会跳过并计数，UI 会提示缺失数量。

恢复顺序：选择 → 校验格式、版本、JSON 结构、字段、ID、关联、分类、路径和 CRC → 在媒体根目录内创建临时恢复目录 → 暂存文件 → 展示训练 / 跑步 / 照片摘要及缺失数量 → 用户确认 → 旧 photos 目录改名保留 → 新目录原子改名 → 数据库事务替换 → 成功后清理旧目录。

照片暂存中途失败时，原数据库和原目录均未更改。数据库事务失败时回滚数据库并把旧目录还原。缺失的新备份照片不会意外复用旧目录中的同路径文件；元数据会保留并显示占位。

拒绝绝对路径、`..`、`.`、反斜杠、控制字符、驱动器路径、重复 ZIP 条目、重复照片文件引用及符号链接。单个 ZIP 条目限制为 64 MB，并校验 CRC。

**Legacy JSON 仍兼容**，恢复旧训练 / 动作 / 组 / 跑步数据，照片为空，同时清理当前旧媒体。带照片元数据却没有图片文件的独立 JSON 会拒绝恢复，并提示选择 ZIP。

异常回滚已测试；数据库与文件系统无法组成单一跨系统事务，不承诺进程被强制终止在目录替换与数据库提交之间时的断电级原子性。替换期间会保留旧媒体目录副本。

## 自动化验证

`dart format .` 完成，`flutter analyze` **No issues found**，`flutter test` **123 个测试全部通过**。

| 测试文件 | 覆盖 |
| --- | --- |
| `test/database/migration_v4_test.dart` | 独立 v2 DDL 真实旧库直接升级 v4，训练 / 动作 / 组 / 跑步与原 ID 保留；v3→v4；已有 v4 索引修复；新安装建表 |
| `test/core/photo_storage_service_test.dart` | 主图与缩略图存在、相对路径、UUID 唯一、删除、丢失文件、尺寸限制、PNG→JPEG、小图不放大、方向与 EXIF / GPS 清理、非法路径、损坏图片回滚、释放 picker 副本时保留用户原文件 |
| `test/database/photo_repository_test.dart` | 训练多图 CRUD、身体分类与排序、关联校验、直接删除训练清理文件、失败插入回滚、丢失文件删除、身体记录流增删刷新、孤儿文件维护、清空照片 |
| `test/database/backup_repository_test.dart` | ZIP 往返、Legacy JSON、未来版本、缺少 JSON、缺失照片、目录外路径、未知分类、符号链接、CRC 损坏、取消预检、文件复制失败、数据库失败回滚、清空失败回滚 |
| `test/features/photo_actions_test.dart` | 取消、相机 / 图库拒绝权限的中文提示、多选部分失败、picker 临时文件释放、关闭完整元数据请求 |
| `test/features/photos_ui_test.dart` | 翻页编号、确认删除末页后的索引、非法初始索引、缺图占位、深色空状态、小屏类型选择、同日大量照片按需构建、等待图库保存时退出页面 |

`flutter build ios --simulator --debug` **成功**，产物为 `build/ios/iphonesimulator/Runner.app`。构建包含新版 SQLite native assets。

独立 bundle ID 的模拟器测试副本 `com.koa.fitlog.photosmoke` 已成功安装并启动。设备窗口工具超时，因此没有宣称已验证真实的系统图库选择界面；测试副本与原 Fitlog 数据隔离，验证后已清理测试副本。

## iPhone 手动验收

1. 相机首次授权、拒绝授权与系统设置重新授权；真机实际拍照。
2. 图库选择 JPEG / PNG / HEIC，横竖屏照片方向、多选和取消；确认不会上传服务器。
3. 训练详情保存多张照片，缩略图正常，查看器翻页和缩放正常，删除需要确认。
4. 添加四类身体照片，关闭并重新打开 App 后仍存在，日期与分类正确。
5. 深色 / 浅色 / 跟随系统及较大字体，观察布局和按钮。
6. 添加照片过程中退出页面；保存完成后重新进入可见。
7. 在含测试照片的训练上验证删除训练；验证清空数据同时删除媒体。请先导出需保留的数据。
8. 导出 ZIP 到 Files / iCloud，检查分享面板；在测试设备重新安装后恢复，核对训练、组、跑步、训练照片、身体照片和缩略图。
9. 导入旧 JSON，确认训练数据恢复、照片为空；损坏备份或存储不足时提示失败且原数据保留。
