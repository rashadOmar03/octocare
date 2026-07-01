class SensorReading {
  final int? id;
  final String? patientId;
  final double? heartRate;
  final double? temperature;
  final double? ecg;
  final double? emg;
  final double? gsr;
  final Map<String, dynamic>? waveforms;
  final String? timestamp;
  final String? status;

  SensorReading({
    this.id,
    this.patientId,
    this.heartRate,
    this.temperature,
    this.ecg,
    this.emg,
    this.gsr,
    this.waveforms,
    this.timestamp,
    this.status,
  });

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? ''),
      patientId: json['patient_id']?.toString(),
      heartRate: _toDouble(json['heart_rate']),
      temperature: _toDouble(json['temperature']),
      ecg: _toDouble(json['ecg']),
      emg: _toDouble(json['emg']),
      gsr: _toDouble(json['gsr']),
      waveforms: json['waveforms'] is Map ? Map<String, dynamic>.from(json['waveforms']) : null,
      timestamp: json['timestamp']?.toString(),
      status: json['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'heart_rate': heartRate,
      'temperature': temperature,
      'ecg': ecg,
      'emg': emg,
      'gsr': gsr,
      'waveforms': waveforms,
      'timestamp': timestamp,
      'status': status,
    };
  }

  List<double> waveformSamples(String type) {
    final data = waveforms?[type];
    if (data is List) {
      return data.map((e) => e is num ? e.toDouble() : double.tryParse(e.toString()) ?? 0).toList();
    }
    return const [];
  }
}
