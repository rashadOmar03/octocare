import 'package:flutter/material.dart';

/// Colors aligned with Arduino Serial Plotter legend:
/// ECG blue, EMG red, GSR green, BPM orange, Temp magenta.
class SensorPlotterColors {
  SensorPlotterColors._();

  static const ecg = Color(0xFF2196F3);
  static const emg = Color(0xFFF44336);
  static const gsr = Color(0xFF4CAF50);
  static const bpm = Color(0xFFFF9800);
  static const temp = Color(0xFFE91E63);

  static const plotBackground = Color(0xFF1E1E1E);
  static const plotGrid = Color(0xFF3E3E42);
  static const plotAxis = Color(0xFFCCCCCC);
}
