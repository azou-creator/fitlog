import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/weight_conversion.dart';
import '../../shared/input_formatters.dart';

/// 重量换算（纯计算工具）：lb ↔ kg。
/// 默认 lb → kg（健身房哑铃标 lb，训练记录用 kg）。
/// 实时换算、可交换方向（交换时把当前结果作为新输入）、常用磅数快捷输入。
class WeightConverterPage extends StatefulWidget {
  const WeightConverterPage({super.key});

  @override
  State<WeightConverterPage> createState() => _WeightConverterPageState();
}

class _WeightConverterPageState extends State<WeightConverterPage> {
  final _inputCtrl = TextEditingController();

  /// true = lb → kg（默认），false = kg → lb
  bool _lbToKg = true;

  /// 常用磅数（健身房哑铃/杠铃常见规格）
  static const _commonPounds = [
    20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100,
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  double get _inputValue => double.tryParse(_inputCtrl.text) ?? 0;

  /// 换算结果（保留原始精度，展示时再格式化）。
  double get _result => _lbToKg
      ? poundsToKg(_inputValue)
      : kgToPounds(_inputValue);

  /// 交换方向：把当前展示的转换结果作为新的输入，体验更自然。
  void _swap() {
    setState(() {
      final shownResult =
          _inputValue > 0 ? formatWeight(_result) : _inputCtrl.text;
      _lbToKg = !_lbToKg;
      _inputCtrl.text = shownResult;
      _inputCtrl.selection = TextSelection.collapsed(
        offset: _inputCtrl.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fromLabel = _lbToKg ? '磅 lb' : '公斤 kg';
    final toLabel = _lbToKg ? '公斤 kg' : '磅 lb';
    final hasInput = _inputValue > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('重量换算')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ===== 换算核心 =====
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fromLabel,
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _inputCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [DecimalInputFormatter()],
                    maxLength: 8,
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        height: 1.1),
                    decoration: const InputDecoration(
                      hintText: '0',
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  // 交换方向
                  IconButton.filledTonal(
                    onPressed: _swap,
                    icon: const Icon(Icons.swap_vert_rounded),
                    tooltip: '交换方向',
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      toLabel,
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatWeight(_result),
                      style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          height: 1.1),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 换算系数提示
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _lbToKg ? '1 lb = 0.453592 kg' : '1 kg = 2.204623 lb',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  // 训练记录参考（仅换算结果为 kg 时有意义）
                  if (_lbToKg && hasInput) ...[
                    const Divider(height: 28),
                    Row(
                      children: [
                        Text(
                          '训练记录参考',
                          style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant),
                        ),
                        const Spacer(),
                        Text(
                          '≈ ${formatWeight(roundToTrainingKg(poundsToKg(_inputValue)))} kg',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ===== 常用磅数（只在 lb → kg 模式显示）=====
          if (_lbToKg) ...[
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '常用磅数',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '点击直接填入',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final lb in _commonPounds)
                  ActionChip(
                    label: Text('$lb'),
                    labelStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                    side: BorderSide.none,
                    backgroundColor: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    onPressed: () {
                      setState(() {
                        _inputCtrl.text = '$lb';
                        _inputCtrl.selection = TextSelection.collapsed(
                          offset: _inputCtrl.text.length,
                        );
                      });
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
