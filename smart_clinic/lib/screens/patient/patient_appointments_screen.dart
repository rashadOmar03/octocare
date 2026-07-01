import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/review_service.dart';
import '../../config/routes.dart';
import '../../services/appointment_service.dart';
import '../../models/appointment.dart';
import '../../widgets/appointment_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/patient_reschedule_dialog.dart';

class PatientAppointmentsScreen extends StatefulWidget {
  const PatientAppointmentsScreen({super.key});

  @override
  State<PatientAppointmentsScreen> createState() => _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState extends State<PatientAppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AppointmentService _service = AppointmentService();
  final ReviewService _reviewService = ReviewService();
  List<Appointment> _upcoming = [];
  List<Appointment> _history = [];
  Set<String> _pendingReviewIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final all = await _service.getAppointments();
      final pending = await _reviewService.getPendingReviews();
      setState(() {
        _upcoming = all.where((a) => a.status == 'pending' || a.status == 'confirmed' || a.status == 'arrived').toList();
        _history = all.where((a) => a.status == 'completed' || a.status == 'cancelled').toList();
        _pendingReviewIds = pending
            .map((p) => p['appointment_id']?.toString())
            .whereType<String>()
            .toSet();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _showCancelBlocked(String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('cancel_appointment')),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('close'))),
        ],
      ),
    );
  }

  Future<void> _cancelAppointment(Appointment appointment) async {
    if (appointment.status != 'pending') {
      if (appointment.isPaid) {
        await _showCancelBlocked(AppLocalizations.tr('payment_blocks_cancel'));
      } else {
        await _showCancelBlocked(AppLocalizations.tr('contact_clinic_cancel'));
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('cancel_appointment')),
        content: Text(AppLocalizations.tr('cancel_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('no'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.tr('yes'))),
        ],
      ),
    );
    if (confirm == true && appointment.id != null) {
      try {
        await _service.cancelAppointment(appointment.id!);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
          );
        }
      }
    }
  }

  Future<void> _rescheduleAppointment(Appointment appointment) async {
    final ok = await PatientRescheduleDialog.show(context, appointment);
    if (ok == true) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    }
  }

  Future<void> _openReview(String appointmentId) async {
    Map<String, dynamic>? visit;
    try {
      final pending = await _reviewService.getPendingReviews();
      for (final p in pending) {
        if (p['appointment_id']?.toString() == appointmentId) {
          visit = p;
          break;
        }
      }
    } catch (_) {}
    if (visit == null || !mounted) return;
    final ok = await Navigator.pushNamed(context, AppRoutes.patientReview, arguments: visit);
    if (ok == true) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('appointments')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: AppLocalizations.tr('upcoming')),
            Tab(text: AppLocalizations.tr('history')),
          ],
        ),
      ),
      body: _isLoading
          ? const LoadingWidget()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_upcoming, showActions: true),
                _buildList(_history),
              ],
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 1, role: 'patient'),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.patientBookAppointment),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildList(List<Appointment> items, {bool showActions = false}) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_today,
        message: AppLocalizations.tr('no_upcoming_appointments'),
        actionLabel: AppLocalizations.tr('book_appointment'),
        onAction: () => Navigator.pushNamed(context, AppRoutes.patientBookAppointment),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final apt = items[i];
          return AppointmentCard(
            appointment: apt,
            onCancel: showActions ? () => _cancelAppointment(apt) : null,
            onReschedule: showActions && apt.status == 'pending' ? () => _rescheduleAppointment(apt) : null,
            onReview: apt.status == 'completed' && apt.id != null && _pendingReviewIds.contains(apt.id)
                ? () => _openReview(apt.id!)
                : null,
          );
        },
      ),
    );
  }
}
