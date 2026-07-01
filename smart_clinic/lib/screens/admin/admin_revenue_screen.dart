import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../l10n/localization.dart';
import '../../models/payment.dart';
import '../../services/admin_service.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/role_badge.dart';
import '../../utils/time_format.dart';
import '../../utils/ui_helpers.dart';

class AdminRevenueScreen extends StatefulWidget {
  const AdminRevenueScreen({super.key});

  @override
  State<AdminRevenueScreen> createState() => _AdminRevenueScreenState();
}

class _AdminRevenueScreenState extends State<AdminRevenueScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AdminService _service = AdminService();
  List<Payment> _all = [];
  bool _isLoading = true;
  bool _downloading = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final rows = await _service.getPayments();
      _all = rows.map((e) => Payment.fromJson(e)).toList();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _downloadReport() async {
    setState(() => _downloading = true);
    try {
      await _service.downloadReport('appointments');
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

  double get _totalPaid => _all.where((p) => p.status == 'paid').fold(0.0, (s, p) => s + (p.amount ?? 0));

  double get _totalRefunded => _all.where((p) => p.status == 'refunded').fold(0.0, (s, p) => s + (p.amount ?? 0));

  double get _netRevenue => _totalPaid - _totalRefunded;

  int get _paidCount => _all.where((p) => p.status == 'paid').length;

  int get _refundedCount => _all.where((p) => p.status == 'refunded').length;

  List<Payment> _filter(String? status) {
    final q = _searchController.text.toLowerCase().trim();
    return _all.where((p) {
      if (status != null && p.status != status) return false;
      if (q.isEmpty) return true;
      final hay = [p.patientName, p.doctorName, p.invoiceRef, p.method, p.appointmentDate].whereType<String>().join(' ').toLowerCase();
      return hay.contains(q);
    }).toList()
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'paid':
        return const Color(0xFF388E3C);
      case 'refunded':
        return const Color(0xFFD32F2F);
      default:
        return const Color(0xFFF57C00);
    }
  }

  void _showDetail(Payment payment) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.tr('payment_details'), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              _row(ctx, AppLocalizations.tr('patients'), payment.patientName),
              _row(ctx, AppLocalizations.tr('doctors'), payment.doctorName),
              _row(ctx, AppLocalizations.tr('select_date'), payment.appointmentDate ?? payment.date),
              _row(ctx, AppLocalizations.tr('select_time'), TimeFormat.format24To12(payment.timeSlot)),
              _row(ctx, AppLocalizations.tr('amount'), '${payment.amount?.toStringAsFixed(0) ?? 0} ${AppLocalizations.tr('egp')}'),
              _row(ctx, AppLocalizations.tr('status'), payment.status),
              _row(ctx, AppLocalizations.tr('payment_method'), payment.method),
              _row(ctx, 'Invoice', payment.invoiceRef),
              if (payment.receptionistName != null) _row(ctx, AppLocalizations.tr('receptionists'), payment.receptionistName),
              if (payment.refundReason != null) _row(ctx, AppLocalizations.tr('refund_reason'), payment.refundReason),
              if (payment.refundedAt != null) _row(ctx, AppLocalizations.tr('date'), payment.refundedAt?.substring(0, 16)),
              if (payment.proofUrl != null && payment.proofUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(AppLocalizations.tr('instapay_screenshot'), style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                _proofImage(payment.proofUrl!),
              ],
              if (payment.refundProofUrl != null && payment.refundProofUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(AppLocalizations.tr('refund_proof'), style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                _proofImage(payment.refundProofUrl!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _proofImage(String url) {
    final fullUrl = url.startsWith('http') ? url : '${ApiConfig.url}$url';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              child: InteractiveViewer(
                child: Image.network(fullUrl, fit: BoxFit.contain),
              ),
            ),
          );
        },
        child: Image.network(
          fullUrl,
          height: 180,
          width: double.infinity,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text(AppLocalizations.tr('error'), style: Theme.of(context).textTheme.bodySmall),
          ),
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

  Widget _buildTable(List<Payment> items) {
    if (items.isEmpty) return EmptyState(icon: Icons.attach_money, message: AppLocalizations.tr('no_data'));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            DataColumn(label: Text(AppLocalizations.tr('select_date'))),
            DataColumn(label: Text(AppLocalizations.tr('patients'))),
            DataColumn(label: Text(AppLocalizations.tr('doctors'))),
            DataColumn(label: Text(AppLocalizations.tr('amount'))),
            DataColumn(label: Text(AppLocalizations.tr('status'))),
          ],
          rows: items.map((p) {
            return DataRow(
              onSelectChanged: (_) => _showDetail(p),
              cells: [
                DataCell(Text(p.appointmentDate ?? p.date ?? '')),
                DataCell(Text(p.patientName ?? '')),
                DataCell(Text(p.doctorName ?? '')),
                DataCell(Text('${p.amount?.toStringAsFixed(0) ?? 0} ${AppLocalizations.tr('egp')}')),
                DataCell(RoleBadge(label: p.status ?? '', color: _statusColor(p.status))),
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
        title: Text(AppLocalizations.tr('revenue')),
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
          tabs: [
            Tab(text: AppLocalizations.tr('history')),
            Tab(text: AppLocalizations.tr('paid')),
            Tab(text: AppLocalizations.tr('refunded')),
          ],
        ),
      ),
      body: _isLoading
          ? const LoadingWidget()
          : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_balance_wallet, color: Color(0xFFD32F2F)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(AppLocalizations.tr('revenue'), style: Theme.of(context).textTheme.titleMedium),
                                  Text(
                                    '${_netRevenue.toStringAsFixed(0)} ${AppLocalizations.tr('egp')}',
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                          color: const Color(0xFFD32F2F),
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_totalPaid.toStringAsFixed(0)} ${AppLocalizations.tr('egp')} ${AppLocalizations.tr('paid')} ($_paidCount) · '
                          '${_totalRefunded.toStringAsFixed(0)} ${AppLocalizations.tr('egp')} ${AppLocalizations.tr('refunded')} ($_refundedCount)',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                const SizedBox(height: 8),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTable(_filter(null)),
                        _buildTable(_filter('paid')),
                        _buildTable(_filter('refunded')),
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
