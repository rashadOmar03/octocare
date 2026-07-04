import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/appointment_service.dart';
import '../../services/receptionist_service.dart';
import '../../models/appointment.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/receptionist_scaffold.dart';
import '../../widgets/receptionist_reschedule_dialog.dart';
import '../../widgets/role_badge.dart';
import '../../utils/time_format.dart';
import '../../utils/ui_helpers.dart';

class ReceptionistQueueScreen extends StatefulWidget {
  const ReceptionistQueueScreen({super.key});

  @override
  State<ReceptionistQueueScreen> createState() => _ReceptionistQueueScreenState();
}

class _ReceptionistQueueScreenState extends State<ReceptionistQueueScreen> {
  final AppointmentService _service = AppointmentService();
  final ReceptionistService _receptionistService = ReceptionistService();
  List<Appointment> _queue = [];
  List<Map<String, dynamic>> _doctors = [];
  String? _selectedDoctorId;
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
      _queue = await _receptionistService.getQueue(doctorId: _selectedDoctorId, date: _todayStr);
      _doctors = await _receptionistService.getDoctors();
    } catch (e) {
      _loadError = extractApiError(e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _showMarkArrivedDialog() async {
    final searchController = TextEditingController();
    List<Appointment> confirmed = [];
    try {
      confirmed = await _service.getAppointments(status: 'confirmed', date: _todayStr);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
      return;
    }
    if (!mounted) return;
    if (confirmed.isEmpty) {
      showErrorSnackBar(context, AppLocalizations.tr('no_data'));
      return;
    }

    final selected = await showDialog<Appointment>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final query = searchController.text.toLowerCase();
          final filtered = confirmed.where((a) {
            if (query.isEmpty) return true;
            return '${a.patientName} ${a.doctorName} ${a.timeSlot}'.toLowerCase().contains(query);
          }).toList();
          return AlertDialog(
            title: Text(AppLocalizations.tr('mark_arrived')),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.tr('search_patient_hint'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: filtered
                          .map(
                            (a) => ListTile(
                              title: Text(a.patientName ?? ''),
                              subtitle: Text('${a.doctorName} — ${TimeFormat.format24To12(a.timeSlot)}'),
                              trailing: RoleBadge(
                                label: AppLocalizations.tr(a.isPaid ? 'paid' : 'unpaid'),
                                color: a.isPaid ? const Color(0xFF388E3C) : const Color(0xFFF57C00),
                              ),
                              onTap: () => Navigator.pop(ctx, a),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    searchController.dispose();
    if (!mounted || selected?.id == null) return;
    try {
      await _service.markArrived(selected!.id!);
      _loadData();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _leaveQueue(Appointment appointment) async {
    try {
      await _service.leaveQueue(appointment.id!);
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('returned_to_confirmed'));
      _loadData();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReceptionistScaffold(
      title: AppLocalizations.tr('waiting_queue'),
      bottomNavIndex: 2,
      floatingActionButton: FloatingActionButton(
        onPressed: _showMarkArrivedDialog,
        child: const Icon(Icons.person_add),
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
                  child: Text('${AppLocalizations.tr('today')}: $_todayStr', style: Theme.of(context).textTheme.titleSmall),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String?>(
                    value: _selectedDoctorId,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.tr('filter_by_doctor'),
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(AppLocalizations.tr('all'))),
                      ..._doctors.map(
                        (d) => DropdownMenuItem<String?>(
                          value: d['id']?.toString(),
                          child: Text((d['name'] ?? '').toString()),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedDoctorId = v);
                      _loadData();
                    },
                  ),
                ),
                Expanded(
                  child: _queue.isEmpty
                      ? EmptyState(icon: Icons.queue, message: AppLocalizations.tr('no_data'))
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _queue.length,
                            itemBuilder: (ctx, i) {
                              final a = _queue[i];
                              final isFirst = i == 0;
                              return Card(
                                color: isFirst ? const Color(0xFF7B1FA2).withValues(alpha: 0.08) : null,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    child: Text('${a.queueNumber ?? i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(a.patientName ?? ''),
                                  subtitle: Text('${a.doctorName ?? ''}\n${a.date ?? ''} — ${TimeFormat.format24To12(a.timeSlot)}'),
                                  isThreeLine: true,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isFirst)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: Text(AppLocalizations.tr('now_serving'), style: const TextStyle(color: Color(0xFF7B1FA2), fontWeight: FontWeight.bold, fontSize: 11)),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.event),
                                        tooltip: AppLocalizations.tr('reschedule'),
                                        onPressed: () async {
                                          final ok = await ReceptionistRescheduleDialog.show(context, a);
                                          if (ok == true) _loadData();
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFD32F2F)),
                                        tooltip: AppLocalizations.tr('remove_from_queue'),
                                        onPressed: () => _leaveQueue(a),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
