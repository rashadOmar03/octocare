import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../widgets/receptionist_scaffold.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/user_avatar.dart';
import '../../services/receptionist_service.dart';
import '../../models/appointment.dart';
import '../../utils/time_format.dart';
import '../../utils/ui_helpers.dart';
import '../../utils/responsive.dart';

class ReceptionistHomeScreen extends StatefulWidget {
  const ReceptionistHomeScreen({super.key});

  @override
  State<ReceptionistHomeScreen> createState() => _ReceptionistHomeScreenState();
}

class _ReceptionistHomeScreenState extends State<ReceptionistHomeScreen> {
  final _avatarKey = GlobalKey<UserAvatarState>();
  final _receptionistService = ReceptionistService();
  ReceptionistDashboardData? _dashboard;
  List<Appointment> _queuePreview = [];
  String? _loadError;
  bool _isLoading = true;

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

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
      _dashboard = await _receptionistService.getDashboard();
      _queuePreview = await _receptionistService.getQueue(date: _todayStr);
      await _avatarKey.currentState?.refresh();
    } catch (e) {
      _loadError = extractApiError(e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final dash = _dashboard;

    return ReceptionistScaffold(
      title: AppLocalizations.tr('dashboard'),
      bottomNavIndex: 0,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? ListView(children: const [SizedBox(height: 240), Center(child: CircularProgressIndicator())])
            : ListView(
                padding: Responsive.pagePadding(context),
                children: [
                  if (_loadError != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('${AppLocalizations.tr('load_failed')}\n$_loadError'),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          UserAvatar(key: _avatarKey, name: auth.currentUser?.firstName),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(AppLocalizations.tr('welcome_back'), style: Theme.of(context).textTheme.bodyMedium),
                                Text(auth.currentUser?.fullName ?? '', style: Theme.of(context).textTheme.titleLarge),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  receptionistQuickActions(context),
                  if (dash != null && dash.actionRequired > 0) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: const Color(0xFFF57C00).withValues(alpha: 0.12),
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF57C00)),
                        title: Text(
                          AppLocalizations.tr('paid_action_required_title'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(AppLocalizations.tr('paid_action_required_body')),
                        isThreeLine: true,
                        trailing: Chip(
                          label: Text('${dash.actionRequired}'),
                          backgroundColor: const Color(0xFFF57C00),
                          labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.receptionistAppointments),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (dash != null)
                    Card(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                      child: ListTile(
                        leading: const Icon(Icons.payments, color: Color(0xFF1565C0)),
                        title: Text(AppLocalizations.tr('today_revenue')),
                        trailing: Text(
                          '${dash.todayRevenue.toStringAsFixed(0)} ${AppLocalizations.tr('egp')}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.receptionistPayments),
                      ),
                    ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: Responsive.statGridAspectRatio(context),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: [
                      StatCard(
                        title: AppLocalizations.tr('appointments_today'),
                        value: '${dash?.todayAppointments ?? 0}',
                        icon: Icons.calendar_today,
                        color: const Color(0xFF1565C0),
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.receptionistAppointments,
                          arguments: {'initial_tab': 1, 'date_scope': 'today'},
                        ),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('arrived'),
                        value: '${dash?.arrived ?? 0}',
                        icon: Icons.person_pin,
                        color: const Color(0xFF7B1FA2),
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.receptionistAppointments,
                          arguments: {'initial_tab': 2, 'date_scope': 'today'},
                        ),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('confirmed'),
                        value: '${dash?.confirmed ?? 0}',
                        icon: Icons.check_circle,
                        color: const Color(0xFF388E3C),
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.receptionistAppointments,
                          arguments: {'initial_tab': 1},
                        ),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('pending'),
                        value: '${dash?.pending ?? 0}',
                        icon: Icons.pending,
                        color: const Color(0xFFF57C00),
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.receptionistAppointments,
                          arguments: {'initial_tab': 0},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppLocalizations.tr('now_serving'), style: Theme.of(context).textTheme.titleLarge),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.receptionistQueue),
                        child: Text(AppLocalizations.tr('view_all')),
                      ),
                    ],
                  ),
                  if (_queuePreview.isEmpty)
                    Text(AppLocalizations.tr('no_data'))
                  else
                    ..._queuePreview.take(5).map(
                          (a) => Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Text('${a.queueNumber ?? ''}')),
                              title: Text(a.patientName ?? ''),
                              subtitle: Text('${a.doctorName ?? ''} • ${TimeFormat.format24To12(a.timeSlot)}'),
                            ),
                          ),
                        ),
                ],
              ),
      ),
    );
  }
}
