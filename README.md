# 训练日志（fitlog）

个人健身 / 跑步训练日记。**纯本地应用**：无登录、无服务器、无网络请求，所有数据保存在手机本机 SQLite 中。

- 技术栈：Flutter · Dart · Riverpod · go_router · Drift (SQLite) · fl_chart · SharedPreferences · share_plus · file_picker
- 首发平台：iOS（同样兼容 Android）
- 当前版本：**V1.1（健身房体验优化版）**

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
- **数据备份**：导出 JSON（含 schemaVersion，经 iOS 分享面板存到文件/iCloud/AirDrop）、导入完整恢复（明确警告覆盖）。
- 设计 Token（AppSpacing/AppRadius）统一视觉；深色模式三档（外观 → Bottom Sheet）。

## 结构

```
lib/
├── app/          # app.dart（入口）、router.dart（路由）、theme.dart（主题）
├── core/         # calc.dart（容量/配速）、formatters.dart、providers、常量
├── database/     # Drift 表（schema v2：session.status）、三个 Repository、backup_repository
├── features/
│   ├── home/     # 首页：进行中横幅 + 快速开始 + 最近训练（再练一次）+ 本周概览
│   ├── workout/  # 进行中编辑器、动作选择、详情、总结、草稿状态（activeWorkoutProvider）
│   ├── running/  # 跑步录入、详情
│   ├── history/  # 按月分组历史
│   ├── stats/    # 统计 + fl_chart 图表（统一空状态）
│   └── settings/ # 外观 BottomSheet、数据管理（统计/备份/清空）
├── shared/       # BigActionButton、RecentWorkoutCard、EmptyState、确认弹窗、设计 Token
└── main.dart
```

数据流：UI → Riverpod → Repository → Drift。schema v1→v2 迁移：为 workout_sessions 增加 status 字段（旧数据视为已完成）。

## 测试

```bash
flutter test    # 42 个测试
```

覆盖：容量/配速/格式化（含 <1分钟）、动作库幂等、自定义动作去重、草稿落库→完成、进行中恢复、「再练一次」只复制结构、「上次」参考查询、级联删除、跑步 CRUD、备份导出导入往返、动作多选、两个入口防崩溃回归。

## 后续可扩展（刻意未做）

训练模板、PR 纪录、体重/围度、HealthKit / Apple Watch、GPS 轨迹、iCloud 自动同步、AI 分析。
