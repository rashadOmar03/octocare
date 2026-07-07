import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../services/appointment_service.dart';
import '../../models/appointment.dart';
import '../../widgets/appointment_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/receptionist_scaffold.dart';
import '../../widgets/receptionist_reschedule_dialog.dart';
import '../../utils/ui_helpers.dart';
import '../../utils/appointment_record_nav.dart';

enum _DateScope { upcoming, today, all }

class ReceptionistAppointmentsScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? initialDateScope;

  const ReceptionistAppointmentsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialDateScope,
  });

  @override
  State<ReceptionistAppointmentsScreen> createState() => _ReceptionistAppointmentsScreenState();
}

class _ReceptionistAppointmentsScreenState extends State<ReceptionistAppointmentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AppointmentService _service = AppointmentService();
  List<Appointment> _allAppointments = [];
  bool _isLoading = true;
  _DateScope _dateScope = _DateScope.upcoming;
  String? _loadError;
  final _searchController = TextEditingController();

  _DateScope _parseDateScope(String? raw) {
    switch (raw) {
      case 'today':
        return _DateScope.today;
      case 'all':
        return _DateScope.all;
      default:
        return _DateScope.upcoming;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: widget.initialTabIndex.clamp(0, 4));
    _tabController.addListener(_onTabChanged);
    _dateScope = _parseDateScope(widget.initialDateScope);
    _loadData();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final idx = _tabController.index;
    if (idx >= 3 && _dateScope == _DateScope.upcoming) {
      setState(() => _dateScope = _DateScope.all);
      _loadData();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      switch (_dateScope) {
        case _DateScope.today:
          _allAppointments = await _service.getAppointments(date: _todayStr);
        case _DateScope.all:
          _allAppointments = await _service.getAppointments(dateFrom: '2000-01-01');
        case _DateScope.upcoming:
          if (_tabController.index >= 3) {
            _allAppointments = await _service.getAppointments(dateFrom: '2000-01-01');
          } else {
            _allAppointments = await _service.getAppointments();
          }
      }
    } catch (e) {
      _loadError = extractApiError(e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  bool _matchesSearch(Appointment a, String query) {
    if (query.isEmpty) return true;
    final hay = [
      a.patientName,
      a.doctorName,
      a.date,
      a.timeSlot,
      a.id,
      a.status,
    ].whereType<String>().join(' ').toLowerCase();
    return hay.contains(query);
  }

  List<Appointment> _filterByStatus(String status) {
    final query = _searchController.text.toLowerCase().trim();
    final items = _allAppointments.where((a) => a.status == status && _matchesSearch(a, query)).toList();
    items.sort((a, b) {
      final dateCompare = (a.date ?? '').compareTo(b.date ?? '');
      if (dateCompare != 0) return dateCompare;
      return (a.timeSlot ?? '').compareTo(b.timeSlot ?? '');
    });
    return items;
  }

  String _emptyMessageFor(String status) {
    switch (status) {
      case 'pending':
        return AppLocalizations.tr('no_pending_appointments');
      case 'confirmed':
        return AppLocalizations.tr('no_confirmed_appointments');
      case 'arrived':
        return AppLocalizations.tr('no_arrived_appointments');
      case 'completed':
        return AppLocalizations.tr('no_completed_appointments');
      case 'cancelled':
        return AppLocalizations.tr('no_cancelled_appointments');
      default:
        return AppLocalizations.tr('no_data');
    }
  }

  Future<void> _reschedule(Appointment appointment, {bool reactivate = false}) async {
    final ok = await ReceptionistRescheduleDialog.show(
      context,
      appointment,
      confirmAfter: true,
      title: reactivate ? AppLocalizations.tr('reactivate_appointment') : null,
    );
    if (ok == true) _loadData();
  }

  Future<void> _confirm(Appointment apt) async {
    try {
      await _service.confirmAppointment(apt.id!);
      _loadData();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, '${AppLocalizations.tr('confirm_failed')}: ${extractApiError(e)}');
    }
  }

  Future<void> _cancel(Appointment apt) async {
    if (apt.isPaid) {
      showErrorSnackBar(context, AppLocalizations.tr('refund_then_cancel'));
      return;
    }
    try {
      await _service.cancelAppointment(apt.id!);
      _loadData();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, '${AppLocalizations.tr('cancel_failed')}: ${extractApiError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReceptionistScaffold(
      title: AppLocalizations.tr('appointments'),
      bottomNavIndex: 1,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final booked = await Navigator.pushNamed(context, AppRoutes.receptionistBookAppointment);
          if (booked == true) _loadData();
        },
        child: const Icon(Icons.add),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: Text(AppLocalizations.tr('upcoming')),
                          selected: _dateScope == _DateScope.upcoming,
                          onSelected: (_) {
                            setState(() => _dateScope = _DateScope.upcoming);
                            _loadData();
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text(AppLocalizations.tr('today_only')),
                          selected: _dateScope == _DateScope.today,
                          onSelected: (_) {
                            setState(() => _dateScope = _DateScope.today);
                            _loadData();
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text(AppLocalizations.tr('all_dates')),
                          selected: _dateScope == _DateScope.all,
                          onSelected: (_) {
                            setState(() => _dateScope = _DateScope.all);
                            _loadData();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.tr('search_patient_hint'),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(_filterByStatus('pending'), emptyMessage: _emptyMessageFor('pending'), showConfirm: true, showCancel: true, showReschedule: true),
                      _buildList(_filterByStatus('confirmed'), emptyMessage: _emptyMessageFor('confirmed'), showMarkArrived: true, markArrivedTodayOnly: true, showCancel: true, showReschedule: true),
                      _buildList(_filterByStatus('arrived'), emptyMessage: _emptyMessageFor('arrived'), showReschedule: true, showLeaveQueue: true),
                      _buildList(_filterByStatus('completed'), emptyMessage: _emptyMessageFor('completed')),
                      _buildList(_filterByStatus('cancelled'), emptyMessage: _emptyMessageFor('cancelled'), showReschedule: true, reactivateCancelled: true),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildList(
    List<Appointment> items, {
    String? emptyMessage,
    bool showConfirm = false,
    bool showCancel = false,
    bool showMarkArrived = false,
    bool showReschedule = false,
    bool showLeaveQueue = false,
    bool markArrivedTodayOnly = false,
    bool reactivateCancelled = false,
  }) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_today,
        message: emptyMessage ?? AppLocalizations.tr('no_data'),
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
            showPatient: true,
            onTap: apt.status == 'completed'
                ? () => openAppointmentMedicalRecord(
                      context,
                      apt,
                      recordDetailRoute: AppRoutes.receptionistRecordDetail,
                    )
                : null,
            onRecordPayment: !apt.isPaid && apt.status != 'cancelled' && apt.status != 'completed'
                ? () => Navigator.pushNamed(
                      context,
                      AppRoutes.receptionistPayments,
                      arguments: {'appointment_id': apt.id, 'open_dialog': true},
                    ).then((_) => _loadData())
                : null,
            onConfirm: showConfirm ? () => _confirm(apt) : null,
            onCancel: showCancel ? () => _cancel(apt) : null,
            onMarkArrived: showMarkArrived && (!markArrivedTodayOnly || apt.isToday)
                ? () async {
                    try {
                      await _service.markArrived(apt.id!);
                      if (mounted) {
                        showSuccessSnackBar(context, AppLocalizations.tr('patient_moved_to_queue'));
                        _tabController.animateTo(2);
                      }
                      _loadData();
                    } catch (e) {
                      if (mounted) showErrorSnackBar(context, e);
                    }
                  }
                : null,
            onReschedule: showReschedule ? () => _reschedule(apt, reactivate: reactivateCancelled) : null,
            onLeaveQueue: showLeaveQueue
                ? () async {
                    try {
                      await _service.leaveQueue(apt.id!);
                      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('returned_to_confirmed'));
                      _loadData();
                    } catch (e) {
                      if (mounted) showErrorSnackBar(context, e);
                    }
                  }
                : null,
          );
        },
      ),
    );
  }
}
