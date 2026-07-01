import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../models/prescription.dart';
import '../../services/medical_service.dart';
import '../../services/admin_service.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/role_badge.dart';
import '../../utils/ui_helpers.dart';

class AdminPrescriptionsScreen extends StatefulWidget {
  const AdminPrescriptionsScreen({super.key});

  @override
  State<AdminPrescriptionsScreen> createState() => _AdminPrescriptionsScreenState();
}

class _AdminPrescriptionsScreenState extends State<AdminPrescriptionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MedicalService _service = MedicalService();
  final AdminService _adminService = AdminService();
  List<Prescription> _all = [];
  bool _isLoading = true;
  bool _downloading = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      _all = await _service.getPrescriptions(includeInactive: true);
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _downloadReport() async {
    setState(() => _downloading = true);
    try {
      await _adminService.downloadReport('clinic-audit');
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

  String _medSummary(Prescription rx) {
    final names = rx.items?.map((i) => i.medicationName).whereType<String>().take(3).join(', ') ?? '';
    return names.isNotEmpty ? names : rx.id ?? '';
  }

  List<Prescription> _filter(String? status) {
    final q = _searchController.text.toLowerCase().trim();
    return _all.where((rx) {
      if (status != null && rx.status != status) return false;
      if (q.isEmpty) return true;
      final hay = [rx.patientName, rx.doctorName, rx.status, _medSummary(rx), rx.id].whereType<String>().join(' ').toLowerCase();
      return hay.contains(q);
    }).toList()
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'active':
        return const Color(0xFF388E3C);
      case 'completed':
        return const Color(0xFF1565C0);
      case 'cancelled':
        return const Color(0xFFD32F2F);
      default:
        return const Color(0xFF757575);
    }
  }

  void _openDetail(Prescription rx) {
    Navigator.pushNamed(context, AppRoutes.adminPrescriptionDetail, arguments: rx);
  }

  Widget _buildTable(List<Prescription> items) {
    if (items.isEmpty) return EmptyState(icon: Icons.medication, message: AppLocalizations.tr('no_data'));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            DataColumn(label: Text(AppLocalizations.tr('select_date'))),
            DataColumn(label: Text(AppLocalizations.tr('patients'))),
            DataColumn(label: Text(AppLocalizations.tr('doctors'))),
            DataColumn(label: Text(AppLocalizations.tr('medications'))),
            DataColumn(label: Text(AppLocalizations.tr('status'))),
          ],
          rows: items.map((rx) {
            return DataRow(
              onSelectChanged: (_) => _openDetail(rx),
              cells: [
                DataCell(Text((rx.createdAt ?? '').substring(0, 10))),
                DataCell(Text(rx.patientName ?? '')),
                DataCell(Text(rx.doctorName ?? '')),
                DataCell(Text(_medSummary(rx))),
                DataCell(RoleBadge(label: rx.status ?? '', color: _statusColor(rx.status))),
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
        title: Text('${AppLocalizations.tr('prescriptions')} (${_all.length})'),
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
            Tab(text: AppLocalizations.tr('history')),
            Tab(text: AppLocalizations.tr('active')),
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
                        _buildTable(_filter(null)),
                        _buildTable(_filter('active')),
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
