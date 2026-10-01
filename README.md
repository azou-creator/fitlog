# 训练日志（fitlog）

个人健身 / 跑步训练日记。**纯本地应用**：无登录、无服务器、无网络请求，训练与跑步记录保存在手机本机 SQLite 中，照片文件保存在 App 私有媒体目录。

- 技术栈：Flutter · Dart · Riverpod · go_router · Drift (SQLite) · fl_chart · SharedPreferences · share_plus · file_picker · image_picker · image · archive
- 首发平台：iOS（同样兼容 Android）
- 当前版本：**V1.2（本地训练照片与身体记录）**

## 运行

```bash
flutter pub get
flutter run                 # 需要连接设备或已启动模拟器
```

iOS 构建需要完整版 Xcode。

## V1.1 核心体验

- **训练进行中**（而不是"创建表单"）：进入训练即落库（session `status = inProgress`），实时计时、右上角完成、标题点击改名、每组紧凑输入行（重量 → Next → 次数 → Done）、**添加一组自动继承上一组重量**、左滑删组、动作 ⋯ 菜单（备注/删除）、每个动作显示「上次」参考数据。
- **训练中断保护**：每次修改自动保存；App 意外退出/被杀后，首页顶部出现「正在进行 · 继续训练」横幅，接着练，不会丢数据，也不会重复创建。
- **再练一次**：首页/记录页一键复制上次训练的名称与动作结构（不复制组数据），第二天照着练。
- **动作选择**：肌群筛选 chips（默认「最近」）、整行点选、底部固定「添加 N 个动作」、右上角 + 自定义动作。
- **跑步录入**：大数字距离/时分秒、实时配速、心率备注弱化到「更多信息」。
- **数据备份**：导出 ZIP（backup.json + 训练照片 + 身体照片，经 iOS 分享面板存到文件/iCloud），恢复前展示摘要，确认后完整替换；兼容旧 JSON。
- 设计 Token（AppSpacing/AppRadius）统一视觉；深色模式三档（外观 → Bottom Sheet）。

## 结构

```
lib/
├── app/          # app.dart（入口）、router.dart（路由）、theme.dart（主题）
├── core/         # calc.dart（容量/配速）、formatters.dart、providers、常量
├── database/     # Drift 表（schema v4：photos）、Repository、ZIP backup / restore
├── features/
│   ├── home/     # 首页：进行中横幅 + 快速开始 + 最近训练（再练一次）+ 本周概览
│   ├── workout/  # 进行中编辑器、动作选择、详情、总结、草稿状态（activeWorkoutProvider）
│   ├── running/  # 跑步录入、详情
│   ├── history/  # 按月分组历史
│   ├── stats/    # 统计 + fl_chart 图表（统一空状态）
│   ├── photos/   # 添加、缩略图、查看器与照片动作协调
│   ├── body/     # 身体记录（按月、日期、部位）
│   └── settings/ # 外观 BottomSheet、数据管理（统计/备份/清空）
├── shared/       # BigActionButton、RecentWorkoutCard、EmptyState、确认弹窗、设计 Token
└── main.dart
```

数据流：UI → Riverpod → Repository → Drift / PhotoStorageService。schema v1→v2 增加训练 status，v2→v3 增加进行中训练唯一索引，v3→v4 增加 photos 元数据表和照片关联索引；支持 v2 直接升级到 v4。

## 测试

```bash
flutter test    # 123 个测试
```

覆盖：容量/配速/格式化（含 <1分钟）、动作库幂等、自定义动作去重、草稿落库→完成、进行中恢复、「再练一次」只复制结构、「上次」参考查询、级联删除、跑步 CRUD、备份导出导入往返、动作多选、两个入口防崩溃回归。

## 本地照片

- 训练详情可拍照或从图库多选；照片浏览支持翻页、双指缩放与确认删除。
- 我的 → 身体记录，按日期记录正面、侧面、背面与其他照片。
- 文件保存在 `Application Support/fitlog/photos/YYYY/MM/<uuid>.jpg`，数据库只保存相对路径。
- 主图 JPEG 长边不超过 2048px / 质量 85，缩略图不超过 480px / 质量 80；后台处理并移除 EXIF / GPS。
- 删除照片、训练以及清空数据均清理媒体。照片增删与备份维护共享串行队列。
- ZIP 恢复先验证版本、结构、关联、路径与 CRC 并暂存文件，再确认恢复；数据库异常会回滚，媒体目录同时还原。
- Drift / drift_dev 2.35.1 与 sqlite3 3.x 支持当前 Dart SDK；SQLite 使用 native assets，不再需要 sqlite3_flutter_libs。

详细修改、测试与真机验收清单见 [照片功能交付说明](docs/photos_implementation.md)。

## 后续可扩展（刻意未做）

训练模板、PR 纪录、体重/围度、HealthKit / Apple Watch、GPS 轨迹、iCloud 自动同步、AI 分析。
