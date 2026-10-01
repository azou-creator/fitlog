import 'package:flutter/services.dart';

/// 重量 / 距离输入格式化：最多 4 位整数 + 2 位小数。
class DecimalInputFormatter extends TextInputFormatter {
  static final _exp = RegExp(r'^\d{0,4}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _exp.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
