import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/report_download_service.dart';
import '../../services/api_service.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/sensor_history_chart.dart';
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
                  _buildSensorChart(),
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
              DataCell(Text(hr != null && hr != 0 ? '$hr' : '--')),
              DataCell(Text(temp != null && temp != 0 ? '$temp°C' : '--')),
              DataCell(Text(gsr != null && gsr != 0 ? '$gsr' : '--')),
              DataCell(Text(ecg != null && ecg != 0 ? '$ecg' : '--')),
              DataCell(Text(emg != null && emg != 0 ? '$emg' : '--')),
              DataCell(Text(r['payment_amount'] != null ? '${r['payment_amount']}' : '-')),
              DataCell(Text(r['payment_method']?.toString() ?? '-')),
              DataCell(Text(AppLocalizations.trValue(r['status']?.toString() ?? '-'))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSensorChart() {
    final sensors = _list('sensor_readings');
    if (sensors.isEmpty) return _emptyCard();

    final ordered = sensors.reversed.toList();
    final hr = ordered.map((s) => (s['heart_rate'] as num?)?.toDouble()).whereType<double>().where((v) => v > 0).toList();
    final temp = ordered.map((s) => (s['temperature'] as num?)?.toDouble()).whereType<double>().where((v) => v > 0).toList();
    final gsr = ordered.map((s) => (s['gsr'] as num?)?.toDouble()).whereType<double>().where((v) => v > 0).toList();

    if (hr.isEmpty && temp.isEmpty && gsr.isEmpty) return _emptyCard();

    return Column(
      children: [
        if (hr.isNotEmpty)
          SensorHistoryChart(
            title: AppLocalizations.tr('heart_rate'),
            description: AppLocalizations.tr('hr_chart_desc'),
            unit: AppLocalizations.tr('bpm'),
            color: const Color(0xFFD32F2F),
            values: hr,
          ),
        if (temp.isNotEmpty)
          SensorHistoryChart(
            title: AppLocalizations.tr('temperature'),
            description: AppLocalizations.tr('temp_chart_desc'),
            unit: '°C',
            color: const Color(0xFFF57C00),
            values: temp,
          ),
        if (gsr.isNotEmpty)
          SensorHistoryChart(
            title: AppLocalizations.tr('gsr'),
            description: AppLocalizations.tr('gsr_chart_desc'),
            unit: '',
            color: const Color(0xFF6A1B9A),
            values: gsr,
          ),
      ],
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
              DataCell(Text(ts.length > 16 ? ts.substring(0, 16) : ts)),
              DataCell(Text('${s['heart_rate'] ?? '-'}')),
              DataCell(Text(s['temperature'] != null && s['temperature'] != 0 ? '${s['temperature']}°C' : '--')),
              DataCell(Text(s['gsr'] != null && s['gsr'] != 0 ? '${s['gsr']}' : '--')),
              DataCell(Text(s['ecg'] != null && s['ecg'] != 0 ? '${s['ecg']}' : '--')),
              DataCell(Text(s['emg'] != null && s['emg'] != 0 ? '${s['emg']}' : '--')),
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
