import 'package:flutter/material.dart';

import '../config/sensor_colors.dart';

/// Icon badges for sensor vitals with full stored precision (no rounding away digits).
class SensorVitalsIconsRow extends StatelessWidget {
  const SensorVitalsIconsRow({
    super.key,
    this.heartRate,
    this.temperature,
    this.gsr,
    this.ecg,
    this.emg,
  });

  final double? heartRate;
  final double? temperature;
  final double? gsr;
  final double? ecg;
  final double? emg;

  static String formatValue(double? value) {
    if (value == null || value == 0) return '--';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _VitalBadge(
          icon: Icons.favorite,
          color: SensorPlotterColors.bpm,
          value: formatValue(heartRate),
          unit: 'BPM',
        ),
        _VitalBadge(
          icon: Icons.thermostat,
          color: SensorPlotterColors.temp,
          value: formatValue(temperature),
          unit: '°C',
        ),
        _VitalBadge(
          icon: Icons.bolt,
          color: SensorPlotterColors.gsr,
          value: formatValue(gsr),
          unit: 'GSR',
        ),
        _VitalBadge(
          icon: Icons.monitor_heart_outlined,
          color: SensorPlotterColors.ecg,
          value: formatValue(ecg),
          unit: 'ECG',
        ),
        _VitalBadge(
          icon: Icons.fitness_center,
          color: SensorPlotterColors.emg,
          value: formatValue(emg),
          unit: 'EMG',
        ),
      ],
    );
  }
}

class _VitalBadge extends StatelessWidget {
  const _VitalBadge({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(
            value == '--' ? '--' : '$value $unit',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
