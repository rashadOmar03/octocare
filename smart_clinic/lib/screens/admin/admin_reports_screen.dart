import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/report_download_service.dart';
import '../../services/api_service.dart';
import '../../widgets/bottom_nav.dart';
import '../../utils/ui_helpers.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  String _reportType = 'clinic-audit';
  String _staffRole = 'doctor';
  String _exportFormat = 'pdf';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isLoading = false;
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

  Map<String, String> _dateParams() {
    final params = <String, String>{};
    final from = _formatDate(_fromDate);
    final to = _formatDate(_toDate);
    if (from != null) params['date_from'] = from;
    if (to != null) params['date_to'] = to;
    return params;
  }

  Future<void> _downloadReport() async {
    if (_fromDate != null && _toDate != null && _fromDate!.isAfter(_toDate!)) {
      showErrorSnackBar(context, AppLocalizations.tr('invalid_date_range'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final params = _dateParams();
      String path;
      String filename;
      switch (_reportType) {
        case 'staff':
          path = '/reports/staff';
          params['role'] = _staffRole;
          filename = 'staff_$_staffRole';
          break;
        case 'patients':
          path = '/reports/patients';
          filename = 'patients_summary';
          break;
        case 'patient-detail':
          final patientId = _selectedPatient?['profile_id']?.toString();
          if (patientId == null || patientId.isEmpty) {
            showErrorSnackBar(context, AppLocalizations.tr('select_patient'));
            setState(() => _isLoading = false);
            return;
          }
          path = '/reports/patient/$patientId';
          filename = 'patient_care_report';
          break;
        case 'appointments':
          path = '/reports/appointments';
          filename = 'appointment_report';
          break;
        case 'doctors':
          path = '/reports/doctors';
          filename = 'doctor_report';
          break;
        default:
          path = '/reports/clinic-audit';
          filename = 'clinic_audit_report';
      }
      await ReportDownloadService.download(
        path,
        filename: '$filename.$_exportFormat',
        queryParams: params.isEmpty ? null : params,
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
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('reports'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.tr('report_type'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _reportType,
                    decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    items: [
                      DropdownMenuItem(value: 'clinic-audit', child: Text(AppLocalizations.tr('reception_report'))),
                      DropdownMenuItem(value: 'appointments', child: Text(AppLocalizations.tr('appointments'))),
                      DropdownMenuItem(value: 'doctors', child: Text(AppLocalizations.tr('doctors'))),
                      DropdownMenuItem(value: 'patients', child: Text(AppLocalizations.tr('patients_summary_report'))),
                      DropdownMenuItem(value: 'patient-detail', child: Text(AppLocalizations.tr('patient_care_report'))),
                      DropdownMenuItem(value: 'staff', child: Text(AppLocalizations.tr('staff_report'))),
                    ],
                    onChanged: (v) => setState(() => _reportType = v!),
                  ),
                  if (_reportType == 'staff') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _staffRole,
                      decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      items: const [
                        DropdownMenuItem(value: 'doctor', child: Text('Doctors')),
                        DropdownMenuItem(value: 'patient', child: Text('Patients')),
                        DropdownMenuItem(value: 'receptionist', child: Text('Receptionists')),
                        DropdownMenuItem(value: 'admin', child: Text('Admins')),
                      ],
                      onChanged: (v) => setState(() => _staffRole = v ?? 'doctor'),
                    ),
                  ],
                  if (_reportType == 'patient-detail') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _patientSearchController,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.tr('search_patient_hint'),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: _searchingPatients
                            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                            : null,
                      ),
                      onChanged: _searchPatients,
                    ),
                    if (_patientResults.isNotEmpty)
                      ..._patientResults.take(5).map((p) => ListTile(
                            title: Text(p['name']?.toString() ?? 'Patient'),
                            subtitle: Text(p['email']?.toString() ?? ''),
                            selected: _selectedPatient?['profile_id'] == p['profile_id'],
                            onTap: () => setState(() => _selectedPatient = p),
                          )),
                    if (_selectedPatient != null)
                      Chip(
                        label: Text(_selectedPatient!['name']?.toString() ?? 'Patient'),
                        onDeleted: () => setState(() => _selectedPatient = null),
                      ),
                  ],
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
                  const SizedBox(height: 16),
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
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _downloadReport,
                      icon: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download),
                      label: Text(AppLocalizations.tr('download_report')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 2, role: 'admin'),
    );
  }
}
