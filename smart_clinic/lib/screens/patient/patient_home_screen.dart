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
import '../../services/sensor_service.dart';
import '../../models/appointment.dart';
import '../../utils/time_format.dart';
import '../../utils/ui_helpers.dart';
import '../../utils/responsive.dart';
import '../../models/sensor_reading.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  final _notifKey = GlobalKey<NotificationIconState>();
  final _avatarKey = GlobalKey<UserAvatarState>();
  final AppointmentService _appointmentService = AppointmentService();
  final SensorService _sensorService = SensorService();
  List<Appointment> _upcomingAppointments = [];
  int _totalAppointmentCount = 0;
  SensorReading? _latestReading;
  Map<String, dynamic>? _queueStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final pending = await _appointmentService.getAppointments(status: 'pending');
      final appointments = await _appointmentService.getAppointments(status: 'confirmed');
      final arrived = await _appointmentService.getAppointments(status: 'arrived');
      final queue = await _appointmentService.getMyQueueStatus();
      SensorReading? reading;
      try {
        reading = await _sensorService.getLatest();
      } catch (_) {}
      if (mounted) {
        final allUpcoming = [...arrived, ...appointments, ...pending];
        setState(() {
          _totalAppointmentCount = allUpcoming.length;
          _upcomingAppointments = allUpcoming.take(5).toList();
          _latestReading = reading;
          _queueStatus = queue;
        });
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    await _avatarKey.currentState?.refresh();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('home')),
        actions: [
          NotificationIcon(
            key: _notifKey,
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.patientNotifications);
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
                padding: Responsive.pagePadding(context).copyWith(
                  bottom: Responsive.bottomContentPadding(context, hasFab: true),
                ),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          UserAvatar(
                            key: _avatarKey,
                            name: user?.firstName,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${AppLocalizations.tr('welcome_back')},',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                Text(
                                  user?.fullName ?? '',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_queueStatus != null && _queueStatus!['in_queue'] == true) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: const Color(0xFF7B1FA2).withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B1FA2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '#${_queueStatus!['queue_number']}',
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLocalizations.tr('your_queue_number'),
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  Text(
                                    AppLocalizations.tr('in_queue_with_doctor').replaceAll(
                                      '{doctor}',
                                      _queueStatus!['doctor_name']?.toString() ?? '',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    AppLocalizations.tr('queue_position_only'),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                        title: AppLocalizations.tr('appointments'),
                        value: '$_totalAppointmentCount',
                        icon: Icons.calendar_today,
                        color: const Color(0xFF1565C0),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.patientAppointments),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('heart_rate'),
                        value: _latestReading?.heartRate != null ? '${_latestReading!.heartRate!.toInt()}' : '--',
                        icon: Icons.favorite,
                        color: const Color(0xFFD32F2F),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.patientSensors),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('medical_records'),
                        value: '',
                        icon: Icons.medical_information,
                        color: const Color(0xFF00897B),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.patientRecords),
                      ),
                      StatCard(
                        title: AppLocalizations.tr('ai_assistant'),
                        value: '',
                        icon: Icons.smart_toy,
                        color: const Color(0xFF7B1FA2),
                        onTap: () => Navigator.pushNamed(context, AppRoutes.patientAi),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocalizations.tr('upcoming'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.patientAppointments),
                        child: Text(AppLocalizations.tr('view_all')),
                      ),
                    ],
                  ),
                  if (_upcomingAppointments.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.calendar_today, size: 48, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(AppLocalizations.tr('no_upcoming_appointments')),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => Navigator.pushNamed(context, AppRoutes.patientBookAppointment),
                              child: Text(AppLocalizations.tr('book_appointment')),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._upcomingAppointments.map((a) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(a.doctorName ?? ''),
                            subtitle: Text('${a.date} - ${TimeFormat.format24To12(a.timeSlot)}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF388E3C).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                AppLocalizations.tr(a.status ?? 'confirmed'),
                                style: const TextStyle(color: Color(0xFF388E3C), fontSize: 12),
                              ),
                            ),
                          ),
                        )),
                ],
              ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 0, role: 'patient'),
      floatingActionButton: Responsive.isCompact(context)
          ? FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.patientBookAppointment),
              tooltip: AppLocalizations.tr('book_appointment'),
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.patientBookAppointment),
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.tr('book_appointment')),
            ),
    );
  }
}
