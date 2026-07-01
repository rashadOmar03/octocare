import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/stat_card.dart';
import '../../services/admin_service.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/notification_icon.dart';
import '../../widgets/user_avatar.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const _statusOrder = ['Pending', 'Confirmed', 'Arrived', 'Completed', 'Cancelled'];
  static const _statusColors = {
    'Pending': Color(0xFFF57C00),
    'Confirmed': Color(0xFF1565C0),
    'Arrived': Color(0xFF7B1FA2),
    'Completed': Color(0xFF388E3C),
    'Cancelled': Color(0xFFD32F2F),
  };

  final _notifKey = GlobalKey<NotificationIconState>();
  final _avatarKey = GlobalKey<UserAvatarState>();
  final AdminService _service = AdminService();
  Map<String, dynamic> _dashboard = {};
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      _dashboard = await _service.getDashboard();
    } catch (e) {
      _loadError = e.toString();
    }
    await _avatarKey.currentState?.refresh();
    setState(() => _isLoading = false);
  }

  void _openUsers(int tab) {
    Navigator.pushNamed(context, AppRoutes.adminUsers, arguments: {'tab': tab});
  }

  double _formatRevenueNet() {
    final raw = _dashboard['revenue'] ?? _dashboard['total_revenue'] ?? 0;
    return raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
  }

  String _formatRevenueBreakdown() {
    final paidCount = _dashboard['paid_payments_count'] ?? 0;
    final refundedCount = _dashboard['refunded_payments_count'] ?? 0;
    final paidTotal = _dashboard['paid_revenue'] ?? 0;
    final refundedTotal = _dashboard['refunded_revenue'] ?? 0;
    final paidAmt = paidTotal is num ? paidTotal.toDouble() : double.tryParse('$paidTotal') ?? 0;
    final refundedAmt = refundedTotal is num ? refundedTotal.toDouble() : double.tryParse('$refundedTotal') ?? 0;
    return '${paidAmt.toStringAsFixed(0)} ${AppLocalizations.tr('paid')} ($paidCount) · '
        '${refundedAmt.toStringAsFixed(0)} ${AppLocalizations.tr('refunded')} ($refundedCount)';
  }

  Map<String, int> _statusCounts() {
    final statusData = _dashboard['status_distribution'];
    if (statusData is! Map) return {};
    return {
      for (final key in _statusOrder)
        if (statusData[key] != null) key: (statusData[key] as num).toInt(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('dashboard')),
        actions: [
          NotificationIcon(
            key: _notifKey,
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.adminNotifications);
              _notifKey.currentState?.refresh();
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const LoadingWidget()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loadError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          UserAvatar(key: _avatarKey, name: user?.firstName),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${AppLocalizations.tr('welcome_back')},', style: Theme.of(context).textTheme.bodyMedium),
                                Text(user?.fullName ?? '', style: Theme.of(context).textTheme.titleLarge),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 1.3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: [
                      StatCard(
                        title: AppLocalizations.tr('total_patients'),
                        value: '${_dashboard['total_patients'] ?? 0}',
                        icon: Icons.people,
                        color: const Color(0xFF1565C0),
                        onTap: () => _openUsers(0),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('total_doctors'),
                        value: '${_dashboard['total_doctors'] ?? 0}',
                        icon: Icons.medical_services,
                        color: const Color(0xFF00897B),
                        onTap: () => _openUsers(1),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('total_receptionists'),
                        value: '${_dashboard['total_receptionists'] ?? 0}',
                        icon: Icons.person_outline,
                        color: const Color(0xFF7B1FA2),
                        onTap: () => _openUsers(2),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('total_appointments'),
                        value: '${_dashboard['total_appointments'] ?? 0}',
                        icon: Icons.calendar_today,
                        color: const Color(0xFFF57C00),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.adminAppointments),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('total_prescriptions'),
                        value: '${_dashboard['total_prescriptions'] ?? 0}',
                        icon: Icons.medication,
                        color: const Color(0xFF388E3C),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.adminPrescriptions),
                      ),
                      StatCard(
                        title: _formatRevenueBreakdown(),
                        value: '${_formatRevenueNet().toStringAsFixed(0)} ${AppLocalizations.tr('egp')}',
                        icon: Icons.attach_money,
                        color: const Color(0xFFD32F2F),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.adminRevenue),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('ai_assistant'),
                        value: '',
                        icon: Icons.smart_toy,
                        color: const Color(0xFF6A1B9A),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.adminAi),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('reports'),
                        value: '',
                        icon: Icons.assessment,
                        color: const Color(0xFF455A64),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.adminReports),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(AppLocalizations.tr('completed_last_7_days'), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SizedBox(height: 220, child: _buildBarChart()),
                  const SizedBox(height: 24),
                  Text(AppLocalizations.tr('status'), style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _buildStatusSummary(),
                  const SizedBox(height: 12),
                  SizedBox(height: 220, child: _buildPieChart()),
                ],
              ),
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 0, role: 'admin'),
    );
  }

  Widget _buildBarChart() {
    final chartData = _dashboard['chart_data'];
    List<BarChartGroupData> bars = [];
    List<String> labels = [];

    if (chartData is List && chartData.isNotEmpty) {
      for (int i = 0; i < chartData.length && i < 7; i++) {
        final item = chartData[i];
        final count = (item is Map ? (item['count'] ?? item['value'] ?? 0) : 0);
        labels.add(item is Map ? '${item['label'] ?? i}' : '$i');
        bars.add(BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (count as num).toDouble(),
              color: const Color(0xFF388E3C),
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        ));
      }
    }

    if (bars.isEmpty) {
      return Card(
        child: Center(child: Text(AppLocalizations.tr('no_data'), style: Theme.of(context).textTheme.bodyMedium)),
      );
    }

    final maxVal = bars.map((b) => b.barRods.first.toY).fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: BarChart(
          BarChartData(
            barGroups: bars,
            minY: 0,
            maxY: maxVal < 1 ? 1 : maxVal + 1,
            gridData: const FlGridData(show: true),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= labels.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(labels[index], style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSummary() {
    final counts = _statusCounts();
    if (counts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _statusOrder.map((status) {
        final count = counts[status] ?? 0;
        final color = _statusColors[status]!;
        return Chip(
          avatar: CircleAvatar(backgroundColor: color, radius: 8),
          label: Text('$status: $count'),
        );
      }).toList(),
    );
  }

  Widget _buildPieChart() {
    final counts = _statusCounts();
    final sections = <PieChartSectionData>[];

    for (final status in _statusOrder) {
      final v = (counts[status] ?? 0).toDouble();
      if (v <= 0) continue;
      final color = _statusColors[status]!;
      sections.add(PieChartSectionData(
        value: v,
        title: '$status\n${v.toInt()}',
        color: color,
        radius: 60,
        titleStyle: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
      ));
    }

    if (sections.isEmpty) {
      return Card(
        child: Center(child: Text(AppLocalizations.tr('no_data'), style: Theme.of(context).textTheme.bodyMedium)),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: PieChart(
          PieChartData(sections: sections, centerSpaceRadius: 30, sectionsSpace: 2),
        ),
      ),
    );
  }
}
