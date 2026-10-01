import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../database/app_database.dart' show RunningRecord;
import '../../database/running_repository.dart';
import '../../shared/input_formatters.dart';
import '../../shared/widgets/app_snack_bar.dart';
import 'running_providers.dart';

/// 跑步手动录入 / 编辑。V1.1：弱化表单感，突出 距离 / 用时 / 配速。
class RunningEditorPage extends ConsumerStatefulWidget {
  const RunningEditorPage({super.key, this.editRecordId});

  final int? editRecordId;

  @override
  ConsumerState<RunningEditorPage> createState() => _RunningEditorPageState();
}

class _RunningEditorPageState extends ConsumerState<RunningEditorPage> {
  final _distanceCtrl = TextEditingController();
  final _hourCtrl = TextEditingController();
  final _minuteCtrl = TextEditingController();
  final _secondCtrl = TextEditingController();
  final _heartRateCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final editId = widget.editRecordId;
    if (editId != null) {
      Future(() async {
        final record =
            await ref.read(runningRepositoryProvider).getById(editId);
        if (!mounted) return;
        if (record != null) _prefill(record);
        setState(() => _ready = true);
      });
    } else {
      _ready = true;
    }
  }

  void _prefill(RunningRecord record) {
    _date = record.date;
    _distanceCtrl.text = _trimDouble(record.distanceKm);
    _hourCtrl.text = (record.durationSeconds ~/ 3600).toString();
    _minuteCtrl.text = ((record.durationSeconds % 3600) ~/ 60).toString();
    _secondCtrl.text = (record.durationSeconds % 60).toString();
    if (record.averageHeartRate != null) {
      _heartRateCtrl.text = record.averageHeartRate.toString();
    }
    _noteCtrl.text = record.note ?? '';
  }

  static String _trimDouble(double v) {
    var s = v.toStringAsFixed(2);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  @override
  void dispose() {
    _distanceCtrl.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    _secondCtrl.dispose();
    _heartRateCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int get _durationSeconds =>
      (int.tryParse(_hourCtrl.text) ?? 0) * 3600 +
      (int.tryParse(_minuteCtrl.text) ?? 0) * 60 +
      (int.tryParse(_secondCtrl.text) ?? 0);

  double get _distanceKm => double.tryParse(_distanceCtrl.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    final isEdit = widget.editRecordId != null;

    final distance = _distanceKm;
    final duration = _durationSeconds;
    final pace = (distance > 0 && duration > 0)
        ? formatPace(duration, distance)
        : "--'--\"/km";

    final bigFieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '编辑跑步' : '记录跑步')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 日期（弱化为一行）
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickDate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    _dateLabel(),
                    style: TextStyle(
                        fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Icon(Icons.expand_more_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 距离
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              IntrinsicWidth(
                child: TextField(
                  controller: _distanceCtrl,
                  autofocus: !isEdit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalInputFormatter()],
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w700, height: 1.1),
                  decoration: const InputDecoration(
                      hintText: '0', counterText: '', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Text('km',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('距离',
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 用时（大号 时:分:秒）
          Row(
            children: [
              _bigTimeField(_hourCtrl, '时', bigFieldBorder, scheme),
              _colon(scheme),
              _bigTimeField(_minuteCtrl, '分', bigFieldBorder, scheme),
              _colon(scheme),
              _bigTimeField(_secondCtrl, '秒', bigFieldBorder, scheme),
            ],
          ),
          const SizedBox(height: 20),
          // 配速（实时）
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.speed_rounded,
                    color: scheme.onSecondaryContainer, size: 22),
                const SizedBox(width: 10),
                Text('平均配速',
                    style: TextStyle(
                        fontSize: 14, color: scheme.onSecondaryContainer)),
                const Spacer(),
                Text(
                  pace,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 更多信息（弱化）
          Text('更多信息（可选）',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextField(
            controller: _heartRateCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 3,
            decoration: const InputDecoration(
              hintText: '平均心率 bpm',
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteCtrl,
            maxLength: 200,
            decoration: const InputDecoration(
              hintText: '备注：路线、天气、感受等',
              counterText: '',
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(
                isEdit ? '保存修改' : '保存',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel() {
    final now = DateTime.now();
    final isToday = now.year == _date.year &&
        now.month == _date.month &&
        now.day == _date.day;
    return isToday
        ? '今天 · ${formatMonthDay(_date)}'
        : formatFullDate(_date);
  }

  Widget _bigTimeField(
    TextEditingController ctrl,
    String label,
    OutlineInputBorder border,
    ColorScheme scheme,
  ) {
    return Expanded(
      child: Column(
        children: [
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 30, fontWeight: FontWeight.w700, height: 1.1),
            decoration: InputDecoration(
              hintText: '00',
              hintStyle: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
              counterText: '',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              enabledBorder: border,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.primary, width: 1.5),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _colon(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 20),
        child: Text(':',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant)),
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: '选择跑步日期',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final distance = _distanceKm;
    final duration = _durationSeconds;
    if (distance <= 0) {
      showAppSnackBar(context, '请输入跑步距离');
      return;
    }
    if (duration <= 0) {
      showAppSnackBar(context, '请输入跑步用时');
      return;
    }
    setState(() => _saving = true);
    final heartRate = int.tryParse(_heartRateCtrl.text);
    try {
      final repo = ref.read(runningRepositoryProvider);
      // 日期归一化到当天 0 点，便于按月分组
      final date = DateTime(_date.year, _date.month, _date.day);
      if (widget.editRecordId != null) {
        await repo.update(
          widget.editRecordId!,
          date: date,
          distanceKm: distance,
          durationSeconds: duration,
          averageHeartRate: heartRate,
          note: _noteCtrl.text,
        );
        ref.invalidate(runningRecordProvider(widget.editRecordId!));
      } else {
        await repo.save(
          date: date,
          distanceKm: distance,
          durationSeconds: duration,
          averageHeartRate: heartRate,
          note: _noteCtrl.text,
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppSnackBar(context, '保存失败，请重试', isError: true);
      }
    }
  }
}
