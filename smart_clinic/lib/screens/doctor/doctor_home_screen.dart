import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/notification_icon.dart';
import '../../widgets/user_avatar.dart';
import '../../services/appointment_service.dart';
import '../../models/appointment.dart';
import '../../utils/doctor_consultation_nav.dart';
import '../../utils/time_format.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  final _notifKey = GlobalKey<NotificationIconState>();
  final _avatarKey = GlobalKey<UserAvatarState>();
  final AppointmentService _appointmentService = AppointmentService();
  List<Appointment> _todayAppointments = [];
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
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final all = await _appointmentService.getTodayAppointments();
      final arrivedQueue = await _appointmentService.getDoctorQueue(date: todayStr);
      const activeStatuses = {'pending', 'confirmed', 'arrived'};
      final fromToday = all.where((a) => activeStatuses.contains(a.status));
      final merged = <String, Appointment>{
        for (final a in fromToday)
          if (a.id != null) a.id!: a,
        for (final a in arrivedQueue)
          if (a.id != null) a.id!: a,
      };
      _todayAppointments = merged.values.toList()
        ..sort((a, b) {
          final aArrived = a.status == 'arrived';
          final bArrived = b.status == 'arrived';
          if (aArrived != bArrived) return aArrived ? -1 : 1;
          if (aArrived && bArrived) {
            return (a.queueNumber ?? 999).compareTo(b.queueNumber ?? 999);
          }
          return (a.timeSlot ?? '').compareTo(b.timeSlot ?? '');
        });
    } catch (_) {
      try {
        final all = await _appointmentService.getAppointments();
        final now = DateTime.now();
        final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        const activeStatuses = {'pending', 'confirmed', 'arrived'};
        _todayAppointments = all
            .where((a) => a.date == todayStr && activeStatuses.contains(a.status))
            .toList()
          ..sort((a, b) {
            final aArrived = a.status == 'arrived';
            final bArrived = b.status == 'arrived';
            if (aArrived != bArrived) return aArrived ? -1 : 1;
            if (aArrived && bArrived) {
              return (a.queueNumber ?? 999).compareTo(b.queueNumber ?? 999);
            }
            return (a.timeSlot ?? '').compareTo(b.timeSlot ?? '');
          });
      } catch (e) {
        _loadError = e.toString();
      }
    }
    await _avatarKey.currentState?.refresh();
    setState(() => _isLoading = false);
  }

  String _consultationStatusSubtitle(Appointment a) {
    if (!a.isPaid && (a.status == 'arrived' || a.status == 'confirmed' || a.status == 'pending')) {
      return AppLocalizations.tr('payment_required_consultation');
    }
    return AppLocalizations.tr(a.status ?? '');
  }

  Widget _consultationTrailing(Appointment a) {
    if (a.canDoctorStartConsultation) {
      return ElevatedButton(
        onPressed: () async {
          final changed = await openDoctorConsultation(context, a);
          if (changed == true && mounted) _loadData();
        },
        child: Text(AppLocalizations.tr('start_consultation')),
      );
    }
    if (a.isConsultationEditOnly) {
      return OutlinedButton(
        onPressed: () async {
          final changed = await openDoctorConsultation(context, a);
          if (changed == true && mounted) _loadData();
        },
        child: Text(AppLocalizations.tr('edit_consultation')),
      );
    }
    return SizedBox(
      width: 130,
      child: Text(
        _consultationStatusSubtitle(a),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
        textAlign: TextAlign.end,
        maxLines: 3,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;
    final waiting = _todayAppointments.where((a) => a.status == 'arrived').length;
    final confirmed = _todayAppointments.where((a) => a.status == 'confirmed').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('dashboard')),
        actions: [
          NotificationIcon(
            key: _notifKey,
            iconColor: Colors.white,
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.doctorNotifications);
              _notifKey.currentState?.refresh();
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
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
                                Text('Dr. ${user?.fullName ?? ''}', style: Theme.of(context).textTheme.titleLarge),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: StatCard(
                            title: AppLocalizations.tr('appointments_today'),
                            value: '${_todayAppointments.length}',
                            icon: Icons.calendar_today,
                            color: const Color(0xFF1565C0),
                            onTap: () => Navigator.pushNamed(context, AppRoutes.doctorAppointments),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            title: AppLocalizations.tr('waiting_queue'),
                            value: '$waiting',
                            icon: Icons.queue,
                            color: const Color(0xFFF57C00),
                            onTap: () => Navigator.pushNamed(context, AppRoutes.doctorWaitingQueue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: StatCard(
                            title: AppLocalizations.tr('confirmed'),
                            value: '$confirmed',
                            icon: Icons.check_circle,
                            color: const Color(0xFF388E3C),
                            onTap: () => Navigator.pushNamed(context, AppRoutes.doctorConfirmedToday),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            title: AppLocalizations.tr('measure_vitals'),
                            value: '',
                            icon: Icons.monitor_heart,
                            color: const Color(0xFF7B1FA2),
                            onTap: () => Navigator.pushNamed(context, AppRoutes.doctorSensors),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppLocalizations.tr('appointments_today'), style: Theme.of(context).textTheme.titleLarge),
                      TextButton(onPressed: () => Navigator.pushNamed(context, AppRoutes.doctorAppointments), child: Text(AppLocalizations.tr('view_all'))),
                    ],
                  ),
                  if (_todayAppointments.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.calendar_today, size: 48, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(AppLocalizations.tr('no_upcoming_appointments')),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._todayAppointments.take(5).map((a) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: a.status == 'arrived'
                                  ? const Color(0xFF7B1FA2).withValues(alpha: 0.15)
                                  : null,
                              child: Text(
                                a.status == 'arrived' && a.queueNumber != null
                                    ? '${a.queueNumber}'
                                    : (a.patientName?.isNotEmpty == true ? a.patientName![0] : '?'),
                              ),
                            ),
                            title: Text(a.patientName ?? ''),
                            subtitle: Text(
                              a.status == 'arrived'
                                  ? '${AppLocalizations.tr('waiting_queue')} • ${TimeFormat.format24To12(a.timeSlot)}'
                                  : TimeFormat.format24To12(a.timeSlot),
                            ),
                            trailing: _consultationTrailing(a),
                            onTap: (a.canDoctorStartConsultation || a.isConsultationEditOnly)
                                ? () async {
                                    final changed = await openDoctorConsultation(context, a);
                                    if (changed == true && mounted) _loadData();
                                  }
                                : null,
                          ),
                        )),
                ],
              ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 0, role: 'doctor'),
    );
  }
}
