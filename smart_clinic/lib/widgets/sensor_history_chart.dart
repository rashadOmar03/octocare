import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/sensor_colors.dart';

/// Trend chart for stored sensor readings (one scalar per visit).
class SensorHistoryChart extends StatelessWidget {
  const SensorHistoryChart({
    super.key,
    required this.title,
    required this.description,
    required this.unit,
    required this.color,
    required this.values,
  });

  final String title;
  final String description;
  final String unit;
  final Color color;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();

    final spots = List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i]));
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final spread = (maxVal - minVal).abs();
    final padding = spread < 1 ? 1.0 : spread * 0.08;
    final minY = minVal - padding;
    final maxY = maxVal + padding;
    final interval = _gridInterval(minY, maxY);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: SensorPlotterColors.plotBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: SensorPlotterColors.plotGrid),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 4),
                child: LineChart(
                  LineChartData(
                    minY: minY,
                    maxY: maxY,
                    clipData: const FlClipData.all(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: interval,
                      verticalInterval: values.length > 8 ? (values.length / 4).ceilToDouble() : 1,
                      getDrawingHorizontalLine: (_) => FlLine(color: SensorPlotterColors.plotGrid, strokeWidth: 0.8),
                      getDrawingVerticalLine: (_) =>
                          FlLine(color: SensorPlotterColors.plotGrid.withValues(alpha: 0.55), strokeWidth: 0.6),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: SensorPlotterColors.plotGrid.withValues(alpha: 0.8)),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 48,
                          interval: interval,
                          getTitlesWidget: (value, meta) {
                            if (!_shouldShowTick(value, interval, meta)) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              _formatAxis(value),
                              style: const TextStyle(fontSize: 10, color: SensorPlotterColors.plotAxis),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: values.length > 8 ? (values.length / 4).ceilToDouble() : 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.round();
                            if (i < 0 || i >= values.length) return const SizedBox.shrink();
                            if (values.length > 8 && i % (values.length ~/ 4).clamp(1, values.length) != 0 && i != 0) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              '${i + 1}',
                              style: const TextStyle(fontSize: 10, color: SensorPlotterColors.plotAxis),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: false,
                        color: color,
                        barWidth: 1.6,
                        dotData: FlDotData(
                          show: values.length <= 24,
                          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                            radius: 2.5,
                            color: color,
                            strokeWidth: 1,
                            strokeColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touched) => touched
                            .map(
                              (s) => LineTooltipItem(
                                '${s.y.toStringAsFixed(1)}${unit.isNotEmpty ? ' $unit' : ''}',
                                TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  duration: Duration.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _gridInterval(double minY, double maxY) {
    final span = maxY - minY;
    if (span <= 0) return 1;
    if (span <= 5) return 1;
    if (span <= 20) return 5;
    if (span <= 100) return 20;
    if (span <= 500) return 100;
    if (span <= 1000) return 200;
    return span / 5;
  }

  static bool _shouldShowTick(double value, double interval, TitleMeta meta) {
    if (interval <= 0) return false;
    final steps = ((meta.max - meta.min) / interval).round();
    if (steps > 8) return false;
    final normalized = (value / interval).round() * interval;
    return (value - normalized).abs() < interval * 0.15;
  }

  static String _formatAxis(double value) {
    if (value.abs() >= 100) return value.round().toString();
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }
}
