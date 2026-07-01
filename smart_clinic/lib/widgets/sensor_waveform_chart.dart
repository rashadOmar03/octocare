import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SensorWaveformChart extends StatelessWidget {
  const SensorWaveformChart({
    super.key,
    required this.title,
    required this.samples,
    required this.color,
    this.currentValue,
    this.unit = '',
    this.shortLabel,
    this.height = 100,
  });

  final String title;
  final List<double> samples;
  final Color color;
  final double? currentValue;
  final String unit;
  final String? shortLabel;
  final double height;

  String get _label => shortLabel ?? title;

  String _formatValue(double? value) {
    if (value == null) return '--';
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
    final outline = Theme.of(context).colorScheme.outline.withValues(alpha: 0.25);

    return Card(
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
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
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
            SizedBox(
              height: height,
              child: samples.isEmpty
                  ? Center(
                      child: Text(
                        '--',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (samples.length - 1).toDouble().clamp(0, double.infinity),
                        minY: _minY,
                        maxY: _maxY,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: _gridInterval,
                          getDrawingHorizontalLine: (_) => FlLine(color: outline, strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              interval: _gridInterval,
                              getTitlesWidget: (value, meta) => Text(
                                _formatAxis(value),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                                      fontSize: 10,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            bottom: BorderSide(color: outline),
                            left: BorderSide(color: outline),
                          ),
                        ),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: List.generate(
                              samples.length,
                              (i) => FlSpot(i.toDouble(), samples[i]),
                            ),
                            isCurved: false,
                            color: color,
                            barWidth: 1.8,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                      duration: Duration.zero,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAxis(double value) {
    if (value.abs() >= 100) return value.round().toString();
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  double get _minY {
    var minY = samples.reduce((a, b) => a < b ? a : b);
    var maxY = samples.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) return minY - 1;
    final pad = (maxY - minY) * 0.12;
    return minY - pad;
  }

  double get _maxY {
    var minY = samples.reduce((a, b) => a < b ? a : b);
    var maxY = samples.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) return maxY + 1;
    final pad = (maxY - minY) * 0.12;
    return maxY + pad;
  }

  double get _gridInterval {
    final span = _maxY - _minY;
    if (span <= 0) return 1;
    if (span <= 5) return 1;
    if (span <= 20) return 5;
    if (span <= 100) return 20;
    if (span <= 500) return 100;
    return span / 4;
  }
}
