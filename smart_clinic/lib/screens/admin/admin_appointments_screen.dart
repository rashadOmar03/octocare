import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../models/appointment.dart';
import '../../widgets/receptionist_reschedule_dialog.dart';
import '../../services/appointment_service.dart';
import '../../services/admin_service.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/role_badge.dart';
import '../../utils/time_format.dart';
import '../../utils/ui_helpers.dart';

class AdminAppointmentsScreen extends StatefulWidget {
  const AdminAppointmentsScreen({super.key});

  @override
  State<AdminAppointmentsScreen> createState() => _AdminAppointmentsScreenState();
}

class _AdminAppointmentsScreenState extends State<AdminAppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AppointmentService _service = AppointmentService();
  final AdminService _adminService = AdminService();
  List<Appointment> _all = [];
  bool _isLoading = true;
  bool _downloading = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _all = await _service.getAppointments();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _downloadReport() async {
    setState(() => _downloading = true);
    try {
      await _adminService.downloadReport('appointments');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('report_download_info')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e.toString());
    }
    if (mounted) setState(() => _downloading = false);
  }

  List<Appointment> _filter(String status) {
    final q = _searchController.text.toLowerCase().trim();
    return _all.where((a) {
      if (a.status != status) return false;
      if (q.isEmpty) return true;
      final hay = [a.patientName, a.doctorName, a.date, a.timeSlot, a.specialtyName].whereType<String>().join(' ').toLowerCase();
      return hay.contains(q);
    }).toList()
      ..sort((a, b) {
        final d = (b.date ?? '').compareTo(a.date ?? '');
        return d != 0 ? d : (b.timeSlot ?? '').compareTo(a.timeSlot ?? '');
      });
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF1565C0);
      case 'pending':
        return const Color(0xFFF57C00);
      case 'cancelled':
        return const Color(0xFFD32F2F);
      case 'completed':
        return const Color(0xFF388E3C);
      case 'arrived':
        return const Color(0xFF7B1FA2);
      default:
        return const Color(0xFF757575);
    }
  }

  Future<void> _reschedule(Appointment apt) async {
    final ok = await ReceptionistRescheduleDialog.show(context, apt);
    if (ok == true) _loadData();
  }

  void _showDetail(Appointment apt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.tr('appointment_details'), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            _row(ctx, AppLocalizations.tr('patients'), apt.patientName),
            _row(ctx, AppLocalizations.tr('doctors'), apt.doctorName),
            _row(ctx, AppLocalizations.tr('select_specialty'), apt.specialtyName),
            _row(ctx, AppLocalizations.tr('select_date'), apt.date),
            _row(ctx, AppLocalizations.tr('select_time'), TimeFormat.format24To12(apt.timeSlot)),
            _row(ctx, AppLocalizations.tr('status'), apt.status),
            _row(ctx, AppLocalizations.tr('queue'), apt.queueNumber?.toString()),
            _row(ctx, AppLocalizations.tr('payments'), apt.isPaid ? AppLocalizations.tr('paid') : AppLocalizations.tr('unpaid')),
            if (apt.notes != null && apt.notes!.isNotEmpty) _row(ctx, AppLocalizations.tr('description'), apt.notes),
            if (apt.status != 'completed' && apt.status != 'cancelled') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _reschedule(apt);
                  },
                  icon: const Icon(Icons.event_repeat),
                  label: Text(AppLocalizations.tr('reschedule')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildTable(List<Appointment> items) {
    if (items.isEmpty) return EmptyState(icon: Icons.calendar_today, message: AppLocalizations.tr('no_data'));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            DataColumn(label: Text(AppLocalizations.tr('select_date'))),
            DataColumn(label: Text(AppLocalizations.tr('select_time'))),
            DataColumn(label: Text(AppLocalizations.tr('patients'))),
            DataColumn(label: Text(AppLocalizations.tr('doctors'))),
            DataColumn(label: Text(AppLocalizations.tr('status'))),
            DataColumn(label: Text(AppLocalizations.tr('payments'))),
          ],
          rows: items.map((apt) {
            return DataRow(
              onSelectChanged: (_) => _showDetail(apt),
              cells: [
                DataCell(Text(apt.date ?? '')),
                DataCell(Text(TimeFormat.format24To12(apt.timeSlot))),
                DataCell(Text(apt.patientName ?? '')),
                DataCell(Text(apt.doctorName ?? '')),
                DataCell(RoleBadge(label: apt.status ?? '', color: _statusColor(apt.status))),
                DataCell(Text(apt.isPaid ? AppLocalizations.tr('paid') : AppLocalizations.tr('unpaid'))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${AppLocalizations.tr('appointments')} (${_all.length})'),
        actions: [
          IconButton(
            onPressed: _downloading ? null : _downloadReport,
            icon: _downloading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            tooltip: AppLocalizations.tr('download_report'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: AppLocalizations.tr('pending')),
            Tab(text: AppLocalizations.tr('confirmed')),
            Tab(text: AppLocalizations.tr('arrived')),
            Tab(text: AppLocalizations.tr('completed')),
            Tab(text: AppLocalizations.tr('cancelled')),
          ],
        ),
      ),
      body: _isLoading
          ? const LoadingWidget()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.tr('search'),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTable(_filter('pending')),
                        _buildTable(_filter('confirmed')),
                        _buildTable(_filter('arrived')),
                        _buildTable(_filter('completed')),
                        _buildTable(_filter('cancelled')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 0, role: 'admin'),
    );
  }
}
