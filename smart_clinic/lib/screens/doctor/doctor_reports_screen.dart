import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/report_download_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_nav.dart';
import '../../utils/ui_helpers.dart';

class DoctorReportsScreen extends StatefulWidget {
  const DoctorReportsScreen({super.key});

  @override
  State<DoctorReportsScreen> createState() => _DoctorReportsScreenState();
}

class _DoctorReportsScreenState extends State<DoctorReportsScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isLoading = false;

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

  Future<void> _selectDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => isFrom ? _fromDate = picked : _toDate = picked);
  }

  Future<void> _downloadActivityReport({required String format}) async {
    if (_fromDate != null && _toDate != null && _fromDate!.isAfter(_toDate!)) {
      showErrorSnackBar(context, AppLocalizations.tr('invalid_date_range'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ReportDownloadService.download(
        '/reports/doctor-activity',
        filename: 'doctor_activity_report',
        queryParams: _dateParams(),
        format: format,
      );
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('report_download_info'));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Widget _formatDownloadButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppLocalizations.tr('download_report'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _downloadActivityReport(format: 'pdf'),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(AppLocalizations.tr('format_pdf')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _downloadActivityReport(format: 'csv'),
                icon: const Icon(Icons.table_chart, size: 18),
                label: Text(AppLocalizations.tr('format_csv')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : () => _downloadActivityReport(format: 'xlsx'),
                icon: const Icon(Icons.grid_on, size: 18),
                label: Text(AppLocalizations.tr('format_xlsx')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('reports'))),
      drawer: const AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
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
                ],
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
                  Row(
                    children: [
                      Icon(Icons.fact_check, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(AppLocalizations.tr('activity_report'), style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(AppLocalizations.tr('doctor_activity_report_desc'), style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  _formatDownloadButtons(),
                  if (_isLoading) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                AppLocalizations.tr('doctor_patient_report_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 0, role: 'doctor'),
    );
  }
}
