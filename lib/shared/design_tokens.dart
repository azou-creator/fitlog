import 'package:flutter/material.dart';

/// 轻量设计 Token（V1.1）。只收录确实统一使用的值，避免散落魔法数字。
///
/// 页面左右 Padding 统一 20；内容区块 16。
/// Card 圆角 16 / 主按钮 16 / 输入框 12。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// 页面水平留白
  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: xl);
}

abstract final class AppRadius {
  static const double card = 16;
  static const double button = 16;
  static const double input = 12;
  static const double chip = 20;
}
