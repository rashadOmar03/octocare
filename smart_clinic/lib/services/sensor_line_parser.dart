import 'dart:convert';

import 'sensor_reading.dart';

class SensorLineParser {
  static SensorReading? parseLine(String line) {
    var trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    final upper = trimmed.toUpperCase();
    if (upper.startsWith('RECEIVED:')) {
      trimmed = trimmed.substring('RECEIVED:'.length).trim();
      if (trimmed.isEmpty) return null;
    }

    final upperTrimmed = trimmed.toUpperCase();
    if (upperTrimmed.startsWith('SYSTEM') || upperTrimmed.startsWith('SMART CLINIC')) {
      return null;
    }

    if (trimmed.startsWith('{')) {
      try {
        final map = json.decode(trimmed) as Map<String, dynamic>;
        final hr = _toDouble(map['heart_rate'] ?? map['hr'] ?? map['bpm']);
        final temp = _parseTemperature(map['temperature'] ?? map['temp']);
        final ecg = _toDouble(map['ecg']);
        final emg = _toDouble(map['emg']);
        final gsr = _toDouble(map['gsr']);
        final explicitAttached = map.containsKey('attached');
        final attached = explicitAttached
            ? map['attached'] == true || map['attached'] == 1
            : _inferAttached(hr, temp, ecg, emg, gsr);
        return SensorReading(
          attached: attached,
          heartRate: hr,
          temperature: temp,
          ecg: ecg,
          emg: emg,
          gsr: gsr,
        );
      } catch (_) {
        return null;
      }
    }

    bool hasExplicitAttached = false;
    bool attached = false;
    double? hr;
    double? temp;
    double? ecg;
    double? emg;
    double? gsr;

    const keyPattern =
        r'(ATTACHED|HR|HEART_RATE|BPM|TEMP|TEMPERATURE|Temp|ECG|EMG|GSR):([^,\s]+)';
    for (final match in RegExp(keyPattern, caseSensitive: false).allMatches(trimmed)) {
      final key = match.group(1)!.trim().toUpperCase();
      final value = match.group(2)!.trim();
      if (key == 'ATTACHED') {
        hasExplicitAttached = true;
        attached = value == '1' || value.toLowerCase() == 'true';
      } else if (key == 'HR' || key == 'HEART_RATE' || key == 'BPM') {
        hr = _toDouble(value);
      } else if (key == 'TEMP' || key == 'TEMPERATURE') {
        temp = _parseTemperature(value);
      } else if (key == 'ECG') {
        ecg = _toDouble(value);
      } else if (key == 'EMG') {
        emg = _toDouble(value);
      } else if (key == 'GSR') {
        gsr = _toDouble(value);
      }
    }

    if (!hasExplicitAttached) {
      attached = _inferAttached(hr, temp, ecg, emg, gsr);
    }

    if (hr == null && temp == null && ecg == null && emg == null && gsr == null) {
      return null;
    }

    return SensorReading(
      attached: attached,
      heartRate: hr,
      temperature: temp,
      ecg: ecg,
      emg: emg,
      gsr: gsr,
    );
  }

  static bool _inferAttached(
    double? hr,
    double? temp,
    double? ecg,
    double? emg,
    double? gsr,
  ) {
    if (hr != null && hr > 0) return true;
    if (temp != null && temp > 20 && temp < 45) return true;
    return ecg != null || emg != null || gsr != null;
  }

  static double? _parseTemperature(dynamic value) {
    if (value == null) return null;
    var text = value.toString().trim().toUpperCase();
    if (text == 'NA' || text == 'NAN') return null;
    if (text.endsWith('C')) {
      text = text.substring(0, text.length - 1).trim();
    }
    return double.tryParse(text);
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString().trim());
  }
}
