class SensorReading {
  final bool attached;
  final double? heartRate;
  final double? temperature;
  final double? ecg;
  final double? emg;
  final double? gsr;

  const SensorReading({
    required this.attached,
    this.heartRate,
    this.temperature,
    this.ecg,
    this.emg,
    this.gsr,
  });
}

typedef SensorBluetoothReading = SensorReading;
