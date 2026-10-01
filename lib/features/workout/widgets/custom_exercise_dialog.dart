import 'package:flutter/material.dart';

import '../../../core/constants/muscle_groups.dart';

/// 自定义动作弹窗。确认时返回 (名称, 部位)，取消返回 null。
class CustomExerciseDialog extends StatefulWidget {
  const CustomExerciseDialog({super.key});

  @override
  State<CustomExerciseDialog> createState() => _CustomExerciseDialogState();
}

class _CustomExerciseDialogState extends State<CustomExerciseDialog> {
  final _nameCtrl = TextEditingController();
  String _group = muscleGroups.first;
  bool _canSave = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save(BuildContext context) {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name, _group));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义动作'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: '动作名称',
              counterText: '',
            ),
            onChanged: (t) => setState(() => _canSave = t.trim().isNotEmpty),
            onSubmitted: (_) => _canSave ? _save(context) : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _group,
            decoration: const InputDecoration(labelText: '训练部位'),
            items: [
              for (final g in muscleGroups)
                DropdownMenuItem(value: g, child: Text(g)),
            ],
            onChanged: (v) => setState(() => _group = v ?? _group),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canSave ? () => _save(context) : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
