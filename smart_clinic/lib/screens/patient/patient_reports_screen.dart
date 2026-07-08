import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/report_download_service.dart';
import '../../services/api_service.dart';
import '../../config/sensor_colors.dart';
import '../../models/sensor_reading.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/sensor_waveform_chart.dart';
import '../../widgets/sensor_vitals_icons_row.dart';
import '../../utils/time_format.dart';

class PatientReportsScreen extends StatefulWidget {
  const PatientReportsScreen({super.key});

  @override
  State<PatientReportsScreen> createState() => _PatientReportsScreenState();
}

class _PatientReportsScreenState extends State<PatientReportsScreen> {
  Map<String, dynamic>? _summary;
  bool _isLoading = true;
  String _exportFormat = 'pdf';

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.get('/patients/my-care-summary');
      _summary = Map<String, dynamic>.from(response);
    } catch (e) {
      _summary = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _downloadPdf() async {
    try {
      await ReportDownloadService.download(
        '/reports/my-report',
        filename: 'my_medical_report.pdf',
        format: _exportFormat,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('report_download_info')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  List<Map<String, dynamic>> _list(String key) {
    final raw = _summary?[key];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('reports')),
        actions: [
          PopupMenuButton<String>(
            tooltip: AppLocalizations.tr('export_format'),
            onSelected: (v) {
              setState(() => _exportFormat = v);
              _downloadPdf();
            },
            itemBuilder: (ctx) => ReportDownloadService.formats
                .map(
                  (f) => PopupMenuItem(
                    value: f,
                    child: Text(f == 'pdf'
                        ? AppLocalizations.tr('format_pdf')
                        : f == 'csv'
                            ? AppLocalizations.tr('format_csv')
                            : AppLocalizations.tr('format_xlsx')),
                  ),
                )
                .toList(),
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : RefreshIndicator(
              onRefresh: _loadSummary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildOverviewCard(),
                  const SizedBox(height: 16),
                  _buildMedicalInfoCard(),
                  const SizedBox(height: 16),
                  _buildSectionTitle(AppLocalizations.tr('consultations')),
                  _buildConsultationsTable(),
                  const SizedBox(height: 16),
                  _buildSectionTitle(AppLocalizations.tr('sensor_readings')),
                  _buildSensorHistory(),
                  const SizedBox(height: 8),
                  _buildSensorTable(),
                  const SizedBox(height: 16),
                  _buildSectionTitle(AppLocalizations.tr('diagnoses')),
                  _buildRecordsSection(),
                  const SizedBox(height: 16),
                  _buildSectionTitle(AppLocalizations.tr('prescriptions')),
                  _buildPrescriptionsSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  Widget _buildOverviewCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_summary?['patient_name']?.toString() ?? AppLocalizations.tr('reports'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.local_hospital, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('${AppLocalizations.tr('clinic_visits')}: ${_summary?['visit_count'] ?? 0}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicalInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.tr('medical_info'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _infoRow(AppLocalizations.tr('self_reported_conditions'), _summary?['self_reported_conditions']),
            _infoRow(AppLocalizations.tr('allergies'), _summary?['allergies']),
            _infoRow(AppLocalizations.tr('chronic_diseases'), _summary?['chronic_diseases']),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text((value?.toString().trim().isNotEmpty ?? false) ? value.toString() : '-')),
        ],
      ),
    );
  }

  Widget _buildConsultationsTable() {
    final rows = _list('consultations');
    if (rows.isEmpty) return _emptyCard();

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(AppLocalizations.tr('date'))),
            DataColumn(label: Text(AppLocalizations.tr('select_time'))),
            DataColumn(label: Text(AppLocalizations.tr('select_doctor'))),
            DataColumn(label: Text(AppLocalizations.tr('receptionists'))),
            DataColumn(label: Text(AppLocalizations.tr('diagnosis'))),
            DataColumn(label: Text(AppLocalizations.tr('notes'))),
            DataColumn(label: Text(AppLocalizations.tr('heart_rate'))),
            DataColumn(label: Text(AppLocalizations.tr('temperature'))),
            DataColumn(label: Text(AppLocalizations.tr('gsr'))),
            DataColumn(label: Text(AppLocalizations.tr('ecg'))),
            DataColumn(label: Text(AppLocalizations.tr('emg'))),
            DataColumn(label: Text(AppLocalizations.tr('amount'))),
            DataColumn(label: Text(AppLocalizations.tr('payment_method'))),
            DataColumn(label: Text(AppLocalizations.tr('status'))),
          ],
          rows: rows.map((r) {
            final hr = r['sensor_heart_rate'];
            final temp = r['sensor_temperature'];
            final gsr = r['sensor_gsr'];
            final ecg = r['sensor_ecg'];
            final emg = r['sensor_emg'];
            final notes = [r['notes'], r['record_notes']].where((n) => n != null && n.toString().trim().isNotEmpty).join('\n');
            return DataRow(cells: [
              DataCell(Text(r['date']?.toString() ?? '-')),
              DataCell(Text(TimeFormat.format24To12(r['time_slot']?.toString()))),
              DataCell(Text(r['doctor_name']?.toString() ?? '-')),
              DataCell(Text(r['receptionist_name']?.toString() ?? '-')),
              DataCell(Text(r['diagnosis']?.toString() ?? '-')),
              DataCell(Text(notes.isNotEmpty ? notes : '-')),
              DataCell(Text(_sensorCell(hr))),
              DataCell(Text(temp != null && temp != 0 ? '${_sensorCell(temp)}°C' : '--')),
              DataCell(Text(_sensorCell(gsr))),
              DataCell(Text(_sensorCell(ecg))),
              DataCell(Text(_sensorCell(emg))),
              DataCell(Text(r['payment_amount'] != null ? '${r['payment_amount']}' : '-')),
              DataCell(Text(r['payment_method']?.toString() ?? '-')),
              DataCell(Text(AppLocalizations.trValue(r['status']?.toString() ?? '-'))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  String _sensorCell(dynamic value) {
    if (value == null || value == 0) return '--';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString());
    return SensorVitalsIconsRow.formatValue(n);
  }

  Widget _buildSensorHistory() {
    final sensors = _list('sensor_readings');
    if (sensors.isEmpty) return _emptyCard();

    return Column(
      children: sensors.map((raw) {
        final reading = SensorReading.fromJson(raw);
        final ecg = reading.waveformSamples('ecg');
        final emg = reading.waveformSamples('emg');
        final gsr = reading.waveformSamples('gsr');
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
                    Expanded(child: Text(reading.timestamp ?? '', style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
                const SizedBox(height: 12),
                SensorVitalsIconsRow(
                  heartRate: reading.heartRate,
                  temperature: reading.temperature,
                  gsr: reading.gsr,
                  ecg: reading.ecg,
                  emg: reading.emg,
                ),
                if (hasWaveforms) ...[
                  const SizedBox(height: 12),
                  if (ecg.length >= 2)
                    SensorWaveformChart(
                      title: AppLocalizations.tr('ecg'),
                      shortLabel: 'ECG',
                      samples: ecg,
                      currentValue: reading.ecg,
                      color: SensorPlotterColors.ecg,
                      height: 120,
                    ),
                  if (emg.length >= 2) ...[
                    const SizedBox(height: 8),
                    SensorWaveformChart(
                      title: AppLocalizations.tr('emg'),
                      shortLabel: 'EMG',
                      samples: emg,
                      currentValue: reading.emg,
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
                      currentValue: reading.gsr,
                      color: SensorPlotterColors.gsr,
                      height: 120,
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSensorTable() {
    final sensors = _list('sensor_readings');
    if (sensors.isEmpty) return const SizedBox.shrink();

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
          rows: sensors.take(20).map((s) {
            final ts = s['timestamp']?.toString() ?? '-';
            return DataRow(cells: [
              DataCell(Text(ts)),
              DataCell(Text(_sensorCell(s['heart_rate']))),
              DataCell(Text(s['temperature'] != null && s['temperature'] != 0 ? '${_sensorCell(s['temperature'])}°C' : '--')),
              DataCell(Text(_sensorCell(s['gsr']))),
              DataCell(Text(_sensorCell(s['ecg']))),
              DataCell(Text(_sensorCell(s['emg']))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRecordsSection() {
    final records = _list('medical_records');
    if (records.isEmpty) return _emptyCard();

    return Column(
      children: records.map((r) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(r['diagnosis']?.toString() ?? '-'),
            subtitle: Text(
              '${r['doctor_name'] ?? ''}\n${r['date'] ?? ''}\n${AppLocalizations.tr('notes')}: ${r['notes'] ?? '-'}',
            ),
            isThreeLine: true,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPrescriptionsSection() {
    final records = _list('medical_records');
    final meds = <Map<String, dynamic>>[];
    for (final r in records) {
      final items = r['medications'];
      if (items is List) {
        for (final m in items) {
          meds.add(Map<String, dynamic>.from(m));
        }
      }
    }
    if (meds.isEmpty) return _emptyCard();

    return Card(
      child: Column(
        children: meds.map((m) {
          return ListTile(
            leading: const Icon(Icons.medication),
            title: Text(m['name']?.toString() ?? '-'),
            subtitle: Text('${m['dosage'] ?? ''} · ${m['frequency'] ?? ''} · ${m['duration'] ?? ''}'),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(AppLocalizations.tr('no_data'))),
      ),
    );
  }
}
