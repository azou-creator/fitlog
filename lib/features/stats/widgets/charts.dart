import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

typedef DayPoint = ({DateTime day, double value});

/// 最近 30 天训练次数柱状图。
class DailyBarChart extends StatelessWidget {
  const DailyBarChart({super.key, required this.points});

  final List<DayPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = points.fold<double>(0, (m, p) => p.value > m ? p.value : m);

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY < 1 ? 1 : maxY + 1,
          barTouchData: BarTouchData(enabled: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY < 4 ? 1 : (maxY / 4).ceilToDouble(),
            getDrawingHorizontalLine: (v) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  final d = points[i].day;
                  if (d.day % 5 != 0 && d.day != 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].value,
                    width: 6,
                    borderRadius: BorderRadius.circular(3),
                    color: points[i].value > 0
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 通用折线图（跑步距离趋势 / 动作重量趋势）。
class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({
    super.key,
    required this.points,
    this.showLeftLabels = true,
  });

  final List<DayPoint> points;
  final bool showLeftLabels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];
    final maxY = points.fold<double>(0, (m, p) => p.value > m ? p.value : m);
    final minY = points.fold<double>(
      double.infinity,
      (m, p) => p.value < m ? p.value : m,
    );
    final range = (maxY - minY).clamp(0, double.infinity);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          lineTouchData: const LineTouchData(
            touchTooltipData: LineTouchTooltipData(),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: range < 3 ? 1 : _niceInterval(range / 4),
            getDrawingHorizontalLine: (v) => FlLine(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: showLeftLabels,
                reservedSize: 36,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      formatWeight(value),
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  // 最多显示 6 个日期标签
                  final step = (points.length / 6).ceil().clamp(1, 30);
                  if (i % step != 0 && i != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  final d = points[i].day;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${d.month}/${d.day}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              barWidth: 2,
              color: scheme.primary,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.08),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _niceInterval(double raw) {
    if (raw <= 0) return 1;
    if (raw < 1) return 0.5;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1.0, 2.0, 5.0, 10.0]) {
      if (mag * m >= raw) return mag * m;
    }
    return mag * 10;
  }
}
