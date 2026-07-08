import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/sensor_colors.dart';
import '../../l10n/localization.dart';
import '../../services/sensor_service.dart';
import '../../models/sensor_reading.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/sensor_waveform_chart.dart';
import '../../widgets/sensor_vitals_icons_row.dart';

class PatientSensorsScreen extends StatefulWidget {
  const PatientSensorsScreen({super.key});

  @override
  State<PatientSensorsScreen> createState() => _PatientSensorsScreenState();
}

class _PatientSensorsScreenState extends State<PatientSensorsScreen> {
  final SensorService _service = SensorService();
  SensorReading? _latest;
  List<SensorReading> _history = [];
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadData(silent: true);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      _latest = await _service.getLatest();
      _alerts = await _service.getAlerts();
      _history = await _service.getHistory();
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    if (mounted) {
      if (silent) {
        setState(() {});
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _hasValue(String type, double? value) {
    if (value == null) return false;
    if (type == 'hr') return value > 0;
    if (type == 'ecg' || type == 'emg' || type == 'gsr') return value > 0;
    return true;
  }

  bool _isNormal(String type, double? value) {
    if (!_hasValue(type, value)) return false;
    switch (type) {
      case 'hr':
        return value! >= 60 && value <= 100;
      case 'temp':
        return value! >= 36.0 && value <= 37.5;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(appBar: AppBar(title: Text(AppLocalizations.tr('sensor_readings'))), body: const LoadingWidget());
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('sensor_readings'))),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildAlertsSection(),
            const SizedBox(height: 16),
            Text(AppLocalizations.tr('latest_readings'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildMetricCard(AppLocalizations.tr('heart_rate'), _latest?.heartRate, AppLocalizations.tr('bpm'), Icons.favorite, SensorPlotterColors.bpm, 'hr'),
                  const SizedBox(width: 8),
                  _buildMetricCard(AppLocalizations.tr('temperature'), _latest?.temperature, '°C', Icons.thermostat, SensorPlotterColors.temp, 'temp'),
                  const SizedBox(width: 8),
                  _buildMetricCard(AppLocalizations.tr('gsr'), _latest?.gsr, '', Icons.bolt, SensorPlotterColors.gsr, 'gsr'),
                  const SizedBox(width: 8),
                  _buildMetricCard(AppLocalizations.tr('ecg'), _latest?.ecg, '', Icons.monitor_heart_outlined, SensorPlotterColors.ecg, 'ecg'),
                  const SizedBox(width: 8),
                  _buildMetricCard(AppLocalizations.tr('emg'), _latest?.emg, '', Icons.fitness_center, SensorPlotterColors.emg, 'emg'),
                ],
              ),
            ),
            if (_latest != null) ...[
              const SizedBox(height: 20),
              Text(AppLocalizations.tr('signal_charts'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SensorWaveformChart(
                title: AppLocalizations.tr('ecg'),
                shortLabel: 'ECG',
                samples: _latest!.waveformSamples('ecg'),
                currentValue: _latest!.ecg,
                color: SensorPlotterColors.ecg,
                height: 120,
              ),
              const SizedBox(height: 8),
              SensorWaveformChart(
                title: AppLocalizations.tr('emg'),
                shortLabel: 'EMG',
                samples: _latest!.waveformSamples('emg'),
                currentValue: _latest!.emg,
                color: SensorPlotterColors.emg,
                height: 120,
              ),
              const SizedBox(height: 8),
              SensorWaveformChart(
                title: AppLocalizations.tr('gsr_waveform'),
                shortLabel: 'GSR',
                samples: _latest!.waveformSamples('gsr'),
                currentValue: _latest!.gsr,
                color: SensorPlotterColors.gsr,
                height: 120,
              ),
            ],
            const SizedBox(height: 24),
            Text(AppLocalizations.tr('history'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildHistoryList(),
            const SizedBox(height: 16),
            _buildHistoryTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.tr('sensor_alerts'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_alerts.isEmpty)
          Card(
            child: ListTile(
              leading: Icon(Icons.check_circle, color: const Color(0xFF388E3C)),
              title: Text(AppLocalizations.tr('no_alerts')),
            ),
          )
        else
          ..._alerts.map((alert) {
            final messages = alert['alerts'];
            final text = messages is List ? messages.map((e) => e.toString()).join('\n') : messages?.toString() ?? '';
            final timestamp = alert['timestamp']?.toString() ?? '';
            final hr = alert['heart_rate'];
            final temp = alert['temperature'];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
                title: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (timestamp.isNotEmpty) timestamp,
                  if (hr != null) '${AppLocalizations.tr('heart_rate')}: $hr',
                  if (temp != null) '${AppLocalizations.tr('temperature')}: $temp°C',
                ].join(' · ')),
                isThreeLine: true,
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMetricCard(String title, double? value, String unit, IconData icon, Color color, String type) {
    final hasValue = _hasValue(type, value);
    final isNormal = hasValue && _isNormal(type, value);
    final statusColor = !hasValue ? const Color(0xFF757575) : (isNormal ? const Color(0xFF388E3C) : const Color(0xFFD32F2F));
    final display = !hasValue ? '--' : (type == 'temp' ? value!.toStringAsFixed(1) : value!.toStringAsFixed(type == 'hr' ? 0 : 1));

    return SizedBox(
      width: 110,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(display, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              if (unit.isNotEmpty) Text(unit, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              if (hasValue && (type == 'hr' || type == 'temp'))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    AppLocalizations.tr(isNormal ? 'normal' : 'abnormal'),
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 4),
              Text(title, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(AppLocalizations.tr('no_data'))));
    }

    return Column(
      children: _history.map(_buildHistoryReadingCard).toList(),
    );
  }

  Widget _buildHistoryReadingCard(SensorReading r) {
    final ecg = r.waveformSamples('ecg');
    final emg = r.waveformSamples('emg');
    final gsr = r.waveformSamples('gsr');
    final hasWaveforms = ecg.length >= 2 || emg.length >= 2 || gsr.length >= 2;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Expanded(child: Text(r.timestamp ?? '', style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
            const SizedBox(height: 12),
            SensorVitalsIconsRow(
              heartRate: r.heartRate,
              temperature: r.temperature,
              gsr: r.gsr,
              ecg: r.ecg,
              emg: r.emg,
            ),
            if (hasWaveforms) ...[
              const SizedBox(height: 12),
              if (ecg.length >= 2)
                SensorWaveformChart(
                  title: AppLocalizations.tr('ecg'),
                  shortLabel: 'ECG',
                  samples: ecg,
                  currentValue: r.ecg,
                  color: SensorPlotterColors.ecg,
                  height: 120,
                ),
              if (emg.length >= 2) ...[
                const SizedBox(height: 8),
                SensorWaveformChart(
                  title: AppLocalizations.tr('emg'),
                  shortLabel: 'EMG',
                  samples: emg,
                  currentValue: r.emg,
                  color: SensorPlotterColors.emg,
                  height: 120,
                ),
              ],
              if (gsr.length >= 2) ...[
                const SizedBox(height: 8),
                SensorWaveformChart(
                  title: AppLocalizations.tr('gsr_waveform'),
                  shortLabel: 'GSR',
                  samples: gsr,
                  currentValue: r.gsr,
                  color: SensorPlotterColors.gsr,
                  height: 120,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTable() {
    if (_history.isEmpty) return const SizedBox.shrink();

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(AppLocalizations.tr('date'))),
            DataColumn(label: Text(AppLocalizations.tr('heart_rate'))),
            DataColumn(label: Text(AppLocalizations.tr('temperature'))),
            DataColumn(label: Text(AppLocalizations.tr('gsr'))),
            DataColumn(label: Text(AppLocalizations.tr('ecg'))),
            DataColumn(label: Text(AppLocalizations.tr('emg'))),
          ],
          rows: _history.take(15).map((r) {
            final ts = r.timestamp ?? '-';
            return DataRow(cells: [
              DataCell(Text(ts.length > 16 ? ts.substring(0, 16) : ts)),
              DataCell(Text(r.heartRate != null && r.heartRate! > 0 ? SensorVitalsIconsRow.formatValue(r.heartRate) : '--')),
              DataCell(Text(r.temperature != null && r.temperature! > 0 ? '${SensorVitalsIconsRow.formatValue(r.temperature)}°C' : '--')),
              DataCell(Text(r.gsr != null && r.gsr! > 0 ? SensorVitalsIconsRow.formatValue(r.gsr) : '--')),
              DataCell(Text(r.ecg != null && r.ecg! > 0 ? SensorVitalsIconsRow.formatValue(r.ecg) : '--')),
              DataCell(Text(r.emg != null && r.emg! > 0 ? SensorVitalsIconsRow.formatValue(r.emg) : '--')),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
