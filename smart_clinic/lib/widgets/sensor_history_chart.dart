import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One metric per chart so BPM, °C, and GSR are not squashed on one Y-axis.
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

    final spots = <FlSpot>[];
    for (var i = 0; i < values.length; i++) {
      spots.add(FlSpot(i.toDouble(), values[i]));
    }

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final spread = (maxVal - minVal).abs();
    final padding = spread < 1 ? 1.0 : spread * 0.15;
    final minY = (minVal - padding).floorToDouble();
    final maxY = (maxVal + padding).ceilToDouble();
    final interval = ((maxY - minY) / 4).clamp(1.0, double.infinity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(description, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(show: true, horizontalInterval: interval),
                  borderData: FlBorderData(show: true),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: interval,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= values.length) return const SizedBox.shrink();
                          return Text('${i + 1}', style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                          radius: 3,
                          color: color,
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                                '${s.y.toStringAsFixed(1)} $unit',
                                TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              values.map((v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)).join(', ') + (unit.isNotEmpty ? ' $unit' : ''),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
