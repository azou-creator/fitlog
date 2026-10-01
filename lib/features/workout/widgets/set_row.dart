import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/input_formatters.dart';
import '../workout_draft.dart';

/// 把 draft 里的重量转成输入框文本：0 显示空，80 显示 80，22.5 显示 22.5。
String weightToText(double w) {
  if (w <= 0) return '';
  var s = w.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

/// 一组训练的紧凑输入行：组号 | 重量 | × | 次数。
/// 重量 → Next → 次数 → Done；删除由外层 Dismissible 左滑完成。
class SetRow extends StatefulWidget {
  const SetRow({
    super.key,
    required this.index,
    required this.set,
    required this.onWeightChanged,
    required this.onRepsChanged,
  });

  final int index;
  final DraftSet set;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int?> onRepsChanged;

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  late final TextEditingController _weightCtrl = TextEditingController(
    text: weightToText(widget.set.weight),
  );
  late final TextEditingController _repsCtrl = TextEditingController(
    text: widget.set.reps?.toString() ?? '',
  );
  final _repsFocus = FocusNode();

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final numberStyle = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );
    final unitStyle = TextStyle(
      fontSize: 12,
      color: scheme.onSurfaceVariant,
      height: 1.1,
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${widget.index + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [DecimalInputFormatter()],
              textInputAction: TextInputAction.next,
              textAlign: TextAlign.center,
              style: numberStyle,
              decoration: InputDecoration(
                hintText: '重量',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                suffix: Text('kg', style: unitStyle),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                enabledBorder: fieldBorder,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: scheme.primary, width: 1.2),
                ),
              ),
              onChanged: (t) {
                if (t.isEmpty) {
                  widget.onWeightChanged(0);
                  return;
                }
                final v = double.tryParse(t);
                if (v != null) widget.onWeightChanged(v);
              },
              onSubmitted: (_) => _repsFocus.requestFocus(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('×', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: TextField(
              controller: _repsCtrl,
              focusNode: _repsFocus,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              style: numberStyle,
              autofocus: widget.set.reps == null,
              decoration: InputDecoration(
                hintText: '次数',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                enabledBorder: fieldBorder,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: scheme.primary, width: 1.2),
                ),
              ),
              onChanged: (t) => widget.onRepsChanged(int.tryParse(t)),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }
}
