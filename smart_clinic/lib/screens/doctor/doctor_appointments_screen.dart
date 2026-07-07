import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../services/appointment_service.dart';
import '../../models/appointment.dart';
import '../../widgets/appointment_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/bottom_nav.dart';
import '../../utils/doctor_consultation_nav.dart';

class DoctorAppointmentsScreen extends StatefulWidget {
  final String? initialStatusFilter;

  const DoctorAppointmentsScreen({super.key, this.initialStatusFilter});

  @override
  State<DoctorAppointmentsScreen> createState() => _DoctorAppointmentsScreenState();
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final AppointmentService _service = AppointmentService();
  List<Appointment> _today = [];
  List<Appointment> _upcoming = [];
  List<Appointment> _completed = [];
  List<Appointment> _filtered = [];
  bool _isLoading = true;
  String? _loadError;
  final _searchController = TextEditingController();
  String? _statusFilter;
  bool _initialized = false;

  bool get _isFilteredView => _statusFilter == 'arrived' || _statusFilter == 'confirmed';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _statusFilter = widget.initialStatusFilter;
    if (_statusFilter == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['status'] != null) {
        _statusFilter = args['status']?.toString();
      } else if (args is String) {
        _statusFilter = args;
      }
    }
    if (_isFilteredView) {
      _tabController = TabController(length: 1, vsync: this);
    } else {
      _tabController = TabController(length: 3, vsync: this);
    }
    _loadData();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _filterTitle {
    if (_statusFilter == 'arrived') return AppLocalizations.tr('waiting_queue');
    if (_statusFilter == 'confirmed') return AppLocalizations.tr('confirmed');
    return AppLocalizations.tr('appointments');
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final all = await _service.getAppointments();
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final activeStatuses = {'pending', 'confirmed', 'arrived'};
      _today = all
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
      _upcoming = all
          .where((a) =>
              (a.status == 'confirmed' || a.status == 'pending' || a.status == 'arrived') &&
              a.date != null &&
              a.date!.compareTo(todayStr) > 0)
          .toList();
      _completed = all.where((a) => a.status == 'completed').toList();

      if (_statusFilter == 'arrived') {
        _filtered = await _service.getDoctorQueue(date: todayStr);
        _filtered.sort((a, b) => (a.queueNumber ?? 999).compareTo(b.queueNumber ?? 999));
      } else if (_statusFilter == 'confirmed') {
        _filtered = all
            .where((a) => a.date == todayStr && a.status == 'confirmed')
            .toList()
          ..sort((a, b) => (a.timeSlot ?? '').compareTo(b.timeSlot ?? ''));
      } else {
        _filtered = [];
      }
    } catch (e) {
      _loadError = e.toString();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_filterTitle),
        bottom: _isFilteredView
            ? null
            : TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: AppLocalizations.tr('today')),
                  Tab(text: AppLocalizations.tr('upcoming')),
                  Tab(text: AppLocalizations.tr('completed')),
                ],
              ),
      ),
      body: _isLoading
          ? const LoadingWidget()
          : Column(
              children: [
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_loadError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (_isFilteredView)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusFilter == 'arrived'
                          ? AppLocalizations.tr('waiting_queue_hint')
                          : AppLocalizations.tr('confirmed_today_hint'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
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
                  child: _isFilteredView
                      ? _buildList(_filtered)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildList(_today),
                            _buildList(_upcoming),
                            _buildList(_completed),
                          ],
                        ),
                ),
              ],
            ),
      bottomNavigationBar: const BottomNav(currentIndex: 1, role: 'doctor'),
    );
  }

  Widget _buildList(List<Appointment> items) {
    final query = _searchController.text.toLowerCase();
    final filtered = query.isEmpty
        ? items
        : items.where((a) => (a.patientName ?? '').toLowerCase().contains(query)).toList();

    if (filtered.isEmpty) {
      return EmptyState(icon: Icons.calendar_today, message: AppLocalizations.tr('no_data'));
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: filtered.length,
        itemBuilder: (ctx, i) {
          final apt = filtered[i];
          return AppointmentCard(
            appointment: apt,
            showPatient: true,
            showDoctor: false,
            onTap: apt.canDoctorStartConsultation || apt.isConsultationEditOnly || apt.status == 'completed'
                ? () async {
                    final changed = await openDoctorConsultation(context, apt);
                    if (changed == true && mounted) _loadData();
                  }
                : null,
          );
        },
      ),
    );
  }
}
