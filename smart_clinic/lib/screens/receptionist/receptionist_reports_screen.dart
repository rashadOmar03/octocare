import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/report_download_service.dart';
import '../../services/api_service.dart';
import '../../widgets/receptionist_scaffold.dart';
import '../../utils/ui_helpers.dart';

class ReceptionistReportsScreen extends StatefulWidget {
  const ReceptionistReportsScreen({super.key});

  @override
  State<ReceptionistReportsScreen> createState() => _ReceptionistReportsScreenState();
}

class _ReceptionistReportsScreenState extends State<ReceptionistReportsScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isLoading = false;
  String _exportFormat = 'pdf';
  final _patientSearchController = TextEditingController();
  List<Map<String, dynamic>> _patientResults = [];
  Map<String, dynamic>? _selectedPatient;
  bool _searchingPatients = false;

  @override
  void dispose() {
    _patientSearchController.dispose();
    super.dispose();
  }

  Future<void> _searchPatients(String query) async {
    if (query.trim().length < 2) {
      setState(() => _patientResults = []);
      return;
    }
    setState(() => _searchingPatients = true);
    try {
      final response = await ApiService.instance.get('/receptionist/patients/search?q=${Uri.encodeComponent(query.trim())}');
      final list = response is List ? response : [];
      setState(() {
        _patientResults = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {
      setState(() => _patientResults = []);
    }
    setState(() => _searchingPatients = false);
  }

  Future<void> _selectDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => isFrom ? _fromDate = picked : _toDate = picked);
  }

  String? _formatDate(DateTime? date) {
    if (date == null) return null;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, String> _dateParams() {
    final params = <String, String>{};
    final from = _formatDate(_fromDate);
    final to = _formatDate(_toDate);
    if (from != null) params['date_from'] = from;
    if (to != null) params['date_to'] = to;
    return params;
  }

  String _formatLabel(String format) {
    switch (format) {
      case 'csv':
        return AppLocalizations.tr('format_csv');
      case 'xlsx':
        return AppLocalizations.tr('format_xlsx');
      default:
        return AppLocalizations.tr('format_pdf');
    }
  }

  Future<void> _downloadPatientReport() async {
    final patientId = _selectedPatient?['profile_id']?.toString();
    if (patientId == null || patientId.isEmpty) {
      showErrorSnackBar(context, AppLocalizations.tr('select_patient'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ReportDownloadService.download(
        '/reports/patient/$patientId',
        filename: 'patient_care_report',
        format: _exportFormat,
      );
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('report_download_info'));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _download(String path, String filename) async {
    if (_fromDate != null && _toDate != null && _fromDate!.isAfter(_toDate!)) {
      showErrorSnackBar(context, AppLocalizations.tr('invalid_date_range'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ReportDownloadService.download(
        path,
        filename: filename,
        queryParams: _dateParams(),
        format: _exportFormat,
      );
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('report_download_info'));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ReceptionistScaffold(
      title: AppLocalizations.tr('reports'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dateRangeCard(),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(AppLocalizations.tr('report_row_limit_notice'), style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
          const SizedBox(height: 12),
          _reportCard(
            title: AppLocalizations.tr('appointments'),
            description: AppLocalizations.tr('appointments_report_desc'),
            icon: Icons.calendar_today,
            onDownload: () => _download('/reports/appointments', 'appointment_report.pdf'),
          ),
          const SizedBox(height: 12),
          _patientReportCard(),
        ],
      ),
    );
  }

  Widget _patientReportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_search, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(AppLocalizations.tr('patient_care_report'), style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(AppLocalizations.tr('patient_care_report_desc'), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _patientSearchController,
              decoration: InputDecoration(
                hintText: AppLocalizations.tr('search_patient_hint'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchingPatients ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              ),
              onChanged: _searchPatients,
            ),
            if (_patientResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._patientResults.take(5).map((p) => ListTile(
                    title: Text(p['name']?.toString() ?? 'Patient'),
                    subtitle: Text(p['email']?.toString() ?? ''),
                    selected: _selectedPatient?['profile_id'] == p['profile_id'],
                    onTap: () => setState(() => _selectedPatient = p),
                  )),
            ],
            if (_selectedPatient != null) ...[
              const SizedBox(height: 8),
              Chip(
                label: Text(_selectedPatient!['name']?.toString() ?? 'Patient'),
                onDeleted: () => setState(() => _selectedPatient = null),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading || _selectedPatient == null ? null : _downloadPatientReport,
                icon: const Icon(Icons.download),
                label: Text(AppLocalizations.tr('download_report')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateRangeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.tr('date_range'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_fromDate != null ? _formatDate(_fromDate)! : AppLocalizations.tr('from_date')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(false),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_toDate != null ? _formatDate(_toDate)! : AppLocalizations.tr('to_date')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(AppLocalizations.tr('export_format'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _exportFormat,
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: ReportDownloadService.formats
                  .map((f) => DropdownMenuItem(value: f, child: Text(_formatLabel(f))))
                  .toList(),
              onChanged: (v) => setState(() => _exportFormat = v ?? 'pdf'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportCard({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onDownload,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : onDownload,
                icon: _isLoading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download),
                label: Text(AppLocalizations.tr('download_report')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
