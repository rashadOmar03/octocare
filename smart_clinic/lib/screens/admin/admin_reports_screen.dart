import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/report_download_service.dart';
import '../../widgets/bottom_nav.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  String _reportType = 'clinic-audit';
  String _exportFormat = 'pdf';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isLoading = false;

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

  Future<void> _downloadReport() async {
    setState(() => _isLoading = true);
    try {
      final params = <String, String>{};
      final from = _formatDate(_fromDate);
      final to = _formatDate(_toDate);
      if (from != null) params['date_from'] = from;
      if (to != null) params['date_to'] = to;

      final filenames = {
        'clinic-audit': 'clinic_audit_report.pdf',
        'appointments': 'appointment_report.pdf',
        'doctors': 'doctor_report.pdf',
      };
      await ReportDownloadService.download(
        '/reports/$_reportType',
        filename: filenames[_reportType] ?? 'report.pdf',
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
                      DropdownMenuItem(value: 'clinic-audit', child: Text(AppLocalizations.tr('audit_report'))),
                      DropdownMenuItem(value: 'appointments', child: Text(AppLocalizations.tr('appointments'))),
                      DropdownMenuItem(value: 'doctors', child: Text(AppLocalizations.tr('doctors'))),
                    ],
                    onChanged: (v) => setState(() => _reportType = v!),
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
