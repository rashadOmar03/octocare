import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../config/sensor_colors.dart';
import '../../l10n/localization.dart';
import '../../services/api_service.dart';
import '../../services/sensor_reading.dart';
import '../../services/sensor_service.dart';
import '../../services/wifi_sensor_service.dart';
import '../../widgets/sensor_waveform_chart.dart';

class DoctorSensorScreen extends StatefulWidget {
  const DoctorSensorScreen({super.key});

  @override
  State<DoctorSensorScreen> createState() => _DoctorSensorScreenState();
}

class _DoctorSensorScreenState extends State<DoctorSensorScreen> {
  static const int _waveformCapacity = 500;
  static const Duration _uiRefreshInterval = Duration(milliseconds: 33);
  static const Duration _dataSilenceTimeout = Duration(seconds: 3);

  final SensorService _sensorService = SensorService();
  final WifiSensorService _wifi = WifiSensorService.instance;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '${WifiSensorService.defaultPort}');

  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _selectedPatient;
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isMeasuring = false;
  bool _isSaving = false;
  bool _sensorAttached = false;
  String? _connectedLabel;

  double? _heartRate;
  double? _temperature;
  double? _gsr;
  double? _ecg;
  double? _emg;
  final List<double> _ecgSamples = [];
  final List<double> _emgSamples = [];
  final List<double> _gsrSamples = [];
  final List<double> _bpmSamples = [];
  final List<double> _tempSamples = [];
  StreamSubscription<SensorReading>? _readingSub;
  StreamSubscription<String>? _rawSub;
  StreamSubscription<bool>? _connectionSub;
  Timer? _noDataTimer;
  Timer? _dataSilenceTimer;
  DateTime? _lastDataReceivedAt;
  String? _lastRawLine;
  int _bytesReceived = 0;
  bool _isConnecting = false;
  String? _lastHost;
  Timer? _uiRefreshTimer;
  bool _needsUiRefresh = false;
  int _readingSession = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyRouteArgs();
      _loadSavedHost();
    });
    _loadPatients();
  }

  Future<void> _loadSavedHost() async {
    final host = await _wifi.loadSavedHost();
    final port = await _wifi.loadSavedPort();
    if (!mounted) return;
    if (host != null && host.isNotEmpty) {
      _hostController.text = host;
    }
    _portController.text = '$port';
  }

  void _applyRouteArgs() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final patientId = args['patient_id']?.toString() ?? args['patientId']?.toString();
      final patientName = args['patient_name']?.toString() ?? args['patientName']?.toString() ?? 'Patient';
      if (patientId != null && patientId.isNotEmpty) {
        setState(() {
          _selectedPatient = {'id': patientId, 'name': patientName};
          if (!_patients.any((p) => p['id'] == patientId)) {
            _patients.insert(0, {'id': patientId, 'name': patientName});
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _noDataTimer?.cancel();
    _dataSilenceTimer?.cancel();
    _uiRefreshTimer?.cancel();
    _readingSub?.cancel();
    _rawSub?.cancel();
    _connectionSub?.cancel();
    _wifi.disconnect();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.get('/appointments/?status=arrived');
      final List<dynamic> data = response is List ? response : [];
      final seen = <String>{};
      _patients = [];
      for (final apt in data) {
        if (apt['is_paid'] != true) continue;
        final pid = apt['patient_id']?.toString() ?? '';
        if (pid.isNotEmpty && seen.add(pid)) {
          _patients.add({
            'id': pid,
            'name': apt['patient_name'] ?? 'Patient',
            'appointment_id': apt['id'],
          });
        }
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  void _clearReadings() {
    _heartRate = null;
    _temperature = null;
    _gsr = null;
    _ecg = null;
    _emg = null;
    _ecgSamples.clear();
    _emgSamples.clear();
    _gsrSamples.clear();
    _bpmSamples.clear();
    _tempSamples.clear();
  }

  void _scheduleUiRefresh() {
    if (_needsUiRefresh) return;
    _needsUiRefresh = true;
    _uiRefreshTimer ??= Timer(_uiRefreshInterval, () {
      _uiRefreshTimer = null;
      if (!mounted) return;
      if (_needsUiRefresh) {
        setState(() => _needsUiRefresh = false);
      }
    });
  }

  void _flushUiRefresh() {
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = null;
    _needsUiRefresh = false;
    if (mounted) setState(() {});
  }

  void _appendSample(List<double> buffer, double value) {
    buffer.add(value);
    if (buffer.length > _waveformCapacity) {
      buffer.removeAt(0);
    }
  }

  void _noteDataReceived() {
    _lastDataReceivedAt = DateTime.now();
  }

  void _startDataSilenceWatchdog() {
    _dataSilenceTimer?.cancel();
    _lastDataReceivedAt = DateTime.now();
    _dataSilenceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isConnected || !_isMeasuring) return;
      final last = _lastDataReceivedAt;
      if (last == null) return;
      if (DateTime.now().difference(last) > _dataSilenceTimeout) {
        unawaited(_handleSensorDataStopped());
      }
    });
  }

  void _stopDataSilenceWatchdog() {
    _dataSilenceTimer?.cancel();
    _dataSilenceTimer = null;
    _lastDataReceivedAt = null;
  }

  Future<void> _handleSensorDataStopped() async {
    if (!mounted || !_isConnected) return;
    _stopDataSilenceWatchdog();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.tr('sensor_data_stopped')),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 6),
      ),
    );
    await _disconnectSensors();
  }

  Future<void> _disconnectSensors() async {
    final session = ++_readingSession;
    _noDataTimer?.cancel();
    _noDataTimer = null;
    _stopDataSilenceWatchdog();
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = null;
    _needsUiRefresh = false;

    setState(() {
      _isConnected = false;
      _isMeasuring = false;
      _sensorAttached = false;
      _connectedLabel = null;
      _lastRawLine = null;
      _bytesReceived = 0;
      _clearReadings();
    });

    await _readingSub?.cancel();
    _readingSub = null;
    await _rawSub?.cancel();
    _rawSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _wifi.disconnect();

    if (!mounted || session != _readingSession) return;
    _flushUiRefresh();
  }

  void _handleConnectionLost() {
    if (!mounted || !_isConnected || _isConnecting) return;
    ++_readingSession;
    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = null;
    _needsUiRefresh = false;
    _stopDataSilenceWatchdog();
    setState(() {
      _isConnected = false;
      _isMeasuring = false;
      _sensorAttached = false;
      _connectedLabel = null;
      _clearReadings();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.tr('wifi_disconnected')),
        backgroundColor: Theme.of(context).colorScheme.error,
        action: _lastHost != null
            ? SnackBarAction(
                label: AppLocalizations.tr('reconnect'),
                onPressed: () {
                  unawaited(_connect());
                },
              )
            : null,
      ),
    );
  }

  Future<void> _connect() async {
    if (_selectedPatient == null) return;

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? WifiSensorService.defaultPort;

    if (!kIsWeb && !ApiConfig.useCloud && host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.tr('esp32_ip_required')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    _lastHost = host;
    final session = ++_readingSession;

    try {
      await _readingSub?.cancel();
      _readingSub = null;
      await _rawSub?.cancel();
      _rawSub = null;
      await _connectionSub?.cancel();
      _connectionSub = null;
      await _wifi.disconnect();

      if (!mounted) return;
      setState(() {
        _isConnecting = true;
        _isConnected = false;
        _isMeasuring = false;
        _sensorAttached = false;
      });

      await _wifi.connect(host: host, port: port);

      if (!mounted || session != _readingSession) return;
      _connectionSub = _wifi.connectionState.listen((connected) {
        if (!connected) _handleConnectionLost();
      });
      _readingSub = _wifi.readings.listen(
        (reading) {
          if (session != _readingSession) return;
          _onSensorReading(reading);
        },
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
          }
          _handleConnectionLost();
        },
      );
      _rawSub = _wifi.rawLines.listen((line) {
        if (!mounted || session != _readingSession) return;
        _noteDataReceived();
        _lastRawLine = line;
        _bytesReceived = _wifi.bytesReceived;
        _scheduleUiRefresh();
      });

      _noDataTimer?.cancel();
      _noDataTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || !_isConnected || _sensorAttached) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.tr('wifi_no_data_hint')),
            duration: const Duration(seconds: 6),
          ),
        );
      });

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = true;
          _connectedLabel = _wifi.connectionLabel;
          _isMeasuring = true;
          _sensorAttached = false;
          _lastRawLine = null;
          _bytesReceived = 0;
          _clearReadings();
        });
        _startDataSilenceWatchdog();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('connected')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
        });
        final message = e is ApiException && e.message.isNotEmpty
            ? e.message
            : AppLocalizations.tr('sensor_connect_failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  void _onSensorReading(SensorReading reading) {
    if (!_isConnected || !_isMeasuring) return;

    _noteDataReceived();
    _sensorAttached = reading.attached;

    if (!reading.attached) {
      _heartRate = null;
      _temperature = null;
      _gsr = null;
      _ecg = null;
      _emg = null;
      _scheduleUiRefresh();
      return;
    }

    if (reading.heartRate != null) {
      _heartRate = reading.heartRate;
      if (_isMeasuring && reading.heartRate! > 0) {
        _appendSample(_bpmSamples, reading.heartRate!);
      }
    }
    if (reading.temperature != null) {
      _temperature = reading.temperature;
      if (_isMeasuring && reading.temperature! > 0) {
        _appendSample(_tempSamples, reading.temperature!);
      }
    }
    if (reading.ecg != null) {
      _ecg = reading.ecg;
      if (_isMeasuring) {
        _appendSample(_ecgSamples, reading.ecg!);
      }
    }
    if (reading.emg != null) {
      _emg = reading.emg;
      if (_isMeasuring) {
        _appendSample(_emgSamples, reading.emg!);
      }
    }
    if (reading.gsr != null) {
      _gsr = reading.gsr;
      if (_isMeasuring) {
        _appendSample(_gsrSamples, reading.gsr!);
      }
    }
    _scheduleUiRefresh();
  }

  void _startMeasuring() {
    if (!_isConnected) return;
    setState(() {
      _isMeasuring = true;
      _sensorAttached = _lastRawLine != null || _bytesReceived > 0;
      _heartRate = null;
      _temperature = null;
      _gsr = null;
      _ecg = null;
      _emg = null;
      _ecgSamples.clear();
      _emgSamples.clear();
      _gsrSamples.clear();
      _bpmSamples.clear();
      _tempSamples.clear();
    });
    _startDataSilenceWatchdog();
    _flushUiRefresh();
  }

  void _stopMeasuring() {
    if (!_isConnected) return;
    setState(() => _isMeasuring = false);
    _stopDataSilenceWatchdog();
    _flushUiRefresh();
  }

  Future<void> _saveReadings() async {
    if (_selectedPatient == null || (_heartRate == null && _temperature == null && _gsr == null)) return;
    setState(() => _isSaving = true);
    try {
      List<double> tail(List<double> samples, [int max = 200]) {
        if (samples.length <= max) return List<double>.from(samples);
        return samples.sublist(samples.length - max);
      }

      await _sensorService.uploadReading({
        'patient_id': _selectedPatient!['id'],
        'heart_rate': (_heartRate ?? 0).round(),
        'temperature': _temperature ?? 0,
        'ecg': _ecgSamples.isNotEmpty ? _ecgSamples.last : 0,
        'emg': _emgSamples.isNotEmpty ? _emgSamples.last : 0,
        'gsr': _gsr ?? 0,
        'waveforms': {
          'bpm': tail(_bpmSamples),
          'temp': tail(_tempSamples),
          'ecg': tail(_ecgSamples),
          'emg': tail(_emgSamples),
          'gsr': tail(_gsrSamples),
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('readings_saved')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('measure_vitals'))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        kIsWeb
                            ? AppLocalizations.tr('wifi_web_hint')
                            : AppLocalizations.tr('wifi_mobile_hint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.tr('select_patient'), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedPatient?['id'],
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.person),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: _patients
                                .map((p) => DropdownMenuItem<String>(
                                      value: p['id'],
                                      child: Text(p['name'] ?? ''),
                                    ))
                                .toList(),
                            onChanged: (v) async {
                              await _disconnectSensors();
                              setState(() {
                                _selectedPatient = _patients.firstWhere((p) => p['id'] == v);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _isConnected ? Icons.wifi : Icons.wifi_off,
                                color: _isConnected ? const Color(0xFF388E3C) : const Color(0xFF757575),
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Arduino + ESP32 WiFi', style: Theme.of(context).textTheme.titleMedium),
                                    Text(
                                      _isConnected
                                          ? '${AppLocalizations.tr('connected')}${_connectedLabel != null ? ' · $_connectedLabel' : ''}'
                                          : AppLocalizations.tr('disconnected'),
                                      style: TextStyle(
                                        color: _isConnected ? const Color(0xFF388E3C) : const Color(0xFF757575),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isConnected)
                                OutlinedButton(
                                  onPressed: _disconnectSensors,
                                  child: Text(AppLocalizations.tr('disconnect')),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: _selectedPatient == null || _isConnecting ? null : () => _connect(),
                                  icon: _isConnecting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.wifi_find, size: 18),
                                  label: Text(AppLocalizations.tr('connect_sensors')),
                                ),
                            ],
                          ),
                          if (!_isConnected) ...[
                            const SizedBox(height: 16),
                            if (ApiConfig.useCloud)
                              Text(
                                AppLocalizations.tr('wifi_cloud_hint'),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF1565C0)),
                              ),
                            if (ApiConfig.useCloud) const SizedBox(height: 12),
                            if (!kIsWeb && !ApiConfig.useCloud)
                              TextField(
                                controller: _hostController,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.tr('esp32_ip_label'),
                                  hintText: '192.168.43.123',
                                  prefixIcon: const Icon(Icons.router),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            if (!kIsWeb && !ApiConfig.useCloud) const SizedBox(height: 12),
                            if (!kIsWeb && !ApiConfig.useCloud)
                              TextField(
                                controller: _portController,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.tr('esp32_port_label'),
                                  prefixIcon: const Icon(Icons.settings_ethernet),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                          ],
                          if (_isConnected) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  _sensorAttached ? Icons.sensors : Icons.sensors_off,
                                  color: _sensorAttached ? const Color(0xFF388E3C) : Colors.orange,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    !_isMeasuring
                                        ? AppLocalizations.tr('measuring_paused')
                                        : _sensorAttached
                                            ? AppLocalizations.tr('sensor_on_patient')
                                            : AppLocalizations.tr('sensor_off_patient'),
                                    style: TextStyle(
                                      color: _sensorAttached ? const Color(0xFF388E3C) : Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_lastRawLine != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${AppLocalizations.tr('last_sensor_line')}: $_lastRawLine',
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.tr('wifi_no_data_hint'),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                              ),
                            ],
                            if (_bytesReceived > 0)
                              Text(
                                '${AppLocalizations.tr('sensor_bytes_received')}: $_bytesReceived',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.tr('latest_readings'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildVitalCard(
                          AppLocalizations.tr('heart_rate'),
                          _heartRate,
                          AppLocalizations.tr('bpm'),
                          Icons.favorite,
                          SensorPlotterColors.bpm,
                        ),
                        const SizedBox(width: 8),
                        _buildVitalCard(
                          AppLocalizations.tr('temperature'),
                          _temperature,
                          '°C',
                          Icons.thermostat,
                          SensorPlotterColors.temp,
                        ),
                        const SizedBox(width: 8),
                        _buildVitalCard(
                          AppLocalizations.tr('gsr'),
                          _gsr,
                          '',
                          Icons.bolt,
                          SensorPlotterColors.gsr,
                        ),
                        const SizedBox(width: 8),
                        _buildVitalCard(
                          AppLocalizations.tr('ecg'),
                          _ecg,
                          '',
                          Icons.monitor_heart_outlined,
                          SensorPlotterColors.ecg,
                        ),
                        const SizedBox(width: 8),
                        _buildVitalCard(
                          AppLocalizations.tr('emg'),
                          _emg,
                          '',
                          Icons.fitness_center,
                          SensorPlotterColors.emg,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.tr('signal_charts'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SensorWaveformChart(
                    title: AppLocalizations.tr('ecg'),
                    shortLabel: 'ECG',
                    samples: _ecgSamples,
                    currentValue: _ecg ?? (_ecgSamples.isNotEmpty ? _ecgSamples.last : null),
                    color: SensorPlotterColors.ecg,
                    height: 140,
                    maxSamples: _waveformCapacity,
                  ),
                  const SizedBox(height: 8),
                  SensorWaveformChart(
                    title: AppLocalizations.tr('emg'),
                    shortLabel: 'EMG',
                    samples: _emgSamples,
                    currentValue: _emg ?? (_emgSamples.isNotEmpty ? _emgSamples.last : null),
                    color: SensorPlotterColors.emg,
                    height: 140,
                    maxSamples: _waveformCapacity,
                  ),
                  const SizedBox(height: 8),
                  SensorWaveformChart(
                    title: AppLocalizations.tr('gsr_waveform'),
                    shortLabel: 'GSR',
                    samples: _gsrSamples,
                    currentValue: _gsr,
                    color: SensorPlotterColors.gsr,
                    height: 140,
                    maxSamples: _waveformCapacity,
                  ),
                  const SizedBox(height: 8),
                  SensorWaveformChart(
                    title: AppLocalizations.tr('heart_rate'),
                    shortLabel: 'BPM',
                    samples: _bpmSamples,
                    currentValue: _heartRate,
                    unit: AppLocalizations.tr('bpm'),
                    color: SensorPlotterColors.bpm,
                    height: 120,
                    maxSamples: _waveformCapacity,
                  ),
                  const SizedBox(height: 8),
                  SensorWaveformChart(
                    title: AppLocalizations.tr('temperature'),
                    shortLabel: 'Temp',
                    samples: _tempSamples,
                    currentValue: _temperature,
                    unit: '°C',
                    color: SensorPlotterColors.temp,
                    height: 120,
                    maxSamples: _waveformCapacity,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: !_isConnected
                              ? null
                              : _isMeasuring
                                  ? _stopMeasuring
                                  : _startMeasuring,
                          icon: Icon(_isMeasuring ? Icons.stop : Icons.play_arrow),
                          label: Text(_isMeasuring ? AppLocalizations.tr('stop_measuring') : AppLocalizations.tr('start_measuring')),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_heartRate != null || _temperature != null) && !_isSaving
                              ? _saveReadings
                              : null,
                          icon: _isSaving
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save),
                          label: Text(AppLocalizations.tr('save_readings')),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: const Color(0xFF388E3C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildVitalCard(String title, double? value, String unit, IconData icon, Color color) {
    return SizedBox(
      width: 110,
      child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                value != null ? value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1) : '--',
                key: ValueKey(value),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
            ),
            if (unit.isNotEmpty)
              Text(unit, style: Theme.of(context).textTheme.bodySmall),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
    );
  }
}
