import 'package:flutter/material.dart';

/// 统一 SnackBar 提示。保存失败等场景使用 [isError]。
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? scheme.error : null,
    ),
  );
}
