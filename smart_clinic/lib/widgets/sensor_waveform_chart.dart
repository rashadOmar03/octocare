import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/sensor_colors.dart';

class SensorWaveformChart extends StatelessWidget {
  const SensorWaveformChart({
    super.key,
    required this.title,
    required this.samples,
    required this.color,
    this.currentValue,
    this.unit = '',
    this.shortLabel,
    this.height = 150,
    this.plotterStyle = true,
    this.maxSamples = 500,
    this.fixedMinY,
    this.fixedMaxY,
  });

  final String title;
  final List<double> samples;
  final Color color;
  final double? currentValue;
  final String unit;
  final String? shortLabel;
  final double height;
  final bool plotterStyle;
  final int maxSamples;
  final double? fixedMinY;
  final double? fixedMaxY;

  String get _label => shortLabel ?? title;

  String _formatValue(double? value) {
    if (value == null) return '--';
    if (value.abs() >= 100) return value.round().toString();
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  String get _displayValue {
    final text = _formatValue(currentValue);
    if (text == '--' || unit.isEmpty) return text;
    return '$text $unit';
  }

  @override
  Widget build(BuildContext context) {
    final plotBg = plotterStyle ? SensorPlotterColors.plotBackground : Theme.of(context).colorScheme.surfaceContainerHighest;
    final gridColor = plotterStyle ? SensorPlotterColors.plotGrid : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25);
    final axisColor = plotterStyle ? SensorPlotterColors.plotAxis : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  _label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                ),
                const Spacer(),
                Text(
                  _displayValue,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
            if (title != _label)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 2),
                child: Text(title, style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Container(
              height: height,
              decoration: BoxDecoration(
                color: plotBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: gridColor),
              ),
              child: samples.length < 2
                  ? Center(
                      child: Text(
                        '--',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: axisColor.withValues(alpha: 0.7),
                            ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 8, 4),
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (maxSamples - 1).toDouble(),
                          minY: _minY,
                          maxY: _maxY,
                          clipData: const FlClipData.all(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: true,
                            verticalInterval: maxSamples / 4,
                            horizontalInterval: _gridInterval,
                            getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 0.8),
                            getDrawingVerticalLine: (_) => FlLine(color: gridColor.withValues(alpha: 0.55), strokeWidth: 0.6),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: plotterStyle,
                                reservedSize: plotterStyle ? 22 : 0,
                                interval: maxSamples / 4,
                                getTitlesWidget: (value, meta) {
                                  if (!plotterStyle) return const SizedBox.shrink();
                                  final rounded = value.round();
                                  if (rounded % (maxSamples ~/ 4) != 0 && rounded != 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Text(
                                    '$rounded',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: axisColor,
                                          fontSize: 10,
                                        ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 44,
                                interval: _gridInterval,
                                getTitlesWidget: (value, meta) => Text(
                                  _formatAxis(value),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: axisColor,
                                        fontSize: 10,
                                      ),
                                ),
                              ),
                            ),
                          ),
                          borderData: FlBorderData(
                            show: plotterStyle,
                            border: Border.all(color: gridColor.withValues(alpha: 0.8)),
                          ),
                          lineTouchData: const LineTouchData(enabled: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: _spots,
                              isCurved: false,
                              isStepLineChart: false,
                              color: color,
                              barWidth: 1.6,
                              dotData: const FlDotData(show: false),
                            ),
                          ],
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

  List<FlSpot> get _spots {
    if (samples.isEmpty) return [];
    final startIndex = samples.length > maxSamples ? samples.length - maxSamples : 0;
    final visible = samples.sublist(startIndex);
    final offset = (maxSamples - visible.length).clamp(0, maxSamples);
    return List.generate(
      visible.length,
      (i) => FlSpot((offset + i).toDouble(), visible[i]),
    );
  }

  String _formatAxis(double value) {
    if (value.abs() >= 100) return value.round().toString();
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  double get _minY {
    if (fixedMinY != null && fixedMaxY != null) return fixedMinY!;
    var minY = samples.reduce((a, b) => a < b ? a : b);
    var maxY = samples.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) return minY - 1;
    final pad = (maxY - minY) * 0.05;
    return (minY - pad).clamp(fixedMinY ?? double.negativeInfinity, double.infinity);
  }

  double get _maxY {
    if (fixedMinY != null && fixedMaxY != null) return fixedMaxY!;
    var minY = samples.reduce((a, b) => a < b ? a : b);
    var maxY = samples.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) return maxY + 1;
    final pad = (maxY - minY) * 0.05;
    return maxY + pad;
  }

  double get _gridInterval {
    final span = _maxY - _minY;
    if (span <= 0) return 1;
    if (span <= 5) return 1;
    if (span <= 20) return 5;
    if (span <= 100) return 20;
    if (span <= 500) return 100;
    if (span <= 1000) return 200;
    return span / 5;
  }
}
