import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/receptionist_service.dart';
import '../../utils/ui_helpers.dart';
import '../../widgets/receptionist_scaffold.dart';
import '../../widgets/loading_widget.dart';

class ReceptionistBookAppointmentScreen extends StatefulWidget {
  const ReceptionistBookAppointmentScreen({super.key});

  @override
  State<ReceptionistBookAppointmentScreen> createState() => _ReceptionistBookAppointmentScreenState();
}

class _ReceptionistBookAppointmentScreenState extends State<ReceptionistBookAppointmentScreen> {
  final _service = ReceptionistService();
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();

  List<PatientSearchResult> _patients = [];
  List<Map<String, dynamic>> _doctors = [];
  List<String> _slots = [];
  String? _slotsReason;
  String? _slotsDaysLabel;
  bool _doctorOnVacation = false;
  String? _vacationReason;
  PatientSearchResult? _selectedPatient;
  String? _selectedDoctorId;
  String? _selectedSlot;
  DateTime _selectedDate = DateTime.now();
  bool _loadingDoctors = true;
  bool _loadingSlots = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadDoctors();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRouteArgs());
  }

  void _applyRouteArgs() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) return;
    final profileId = args['profile_id']?.toString();
    final patientName = args['patient_name']?.toString();
    if (profileId == null || profileId.isEmpty) return;
    setState(() {
      _selectedPatient = PatientSearchResult(
        profileId: profileId,
        name: patientName ?? 'Patient',
        email: '',
        phone: '',
      );
      _searchController.text = patientName ?? '';
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDoctors() async {
    setState(() => _loadingDoctors = true);
    try {
      _doctors = await _service.getDoctors();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _loadingDoctors = false);
  }

  Future<void> _searchPatients(String query) async {
    if (query.trim().length < 2) {
      setState(() => _patients = []);
      return;
    }
    try {
      final results = await _service.searchPatients(query);
      if (mounted) setState(() => _patients = results);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedSlot = null;
        _slots = [];
      });
      _loadSlots();
    }
  }

  String get _dateStr {
    return '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadSlots() async {
    if (_selectedDoctorId == null) return;
    setState(() => _loadingSlots = true);
    try {
      final result = await _service.fetchAvailableSlotsMeta(_selectedDoctorId!, _dateStr);
      _slots = List<String>.from(result['slots'] as List? ?? []);
      _slotsReason = result['reason']?.toString();
      _slotsDaysLabel = result['working_days_label']?.toString();
      _doctorOnVacation = result['doctor_on_vacation'] == true;
      _vacationReason = result['vacation_reason']?.toString();
      _selectedSlot = null;
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _loadingSlots = false);
  }

  String? _slotEmptyMessage() {
    if (_slots.isNotEmpty) return null;
    final reason = _slotsReason;
    final daysLabel = _slotsDaysLabel ?? '';
    if (_doctorOnVacation) {
      return _vacationReason?.isNotEmpty == true
          ? '${AppLocalizations.tr('doctor_on_vacation')}: $_vacationReason'
          : AppLocalizations.tr('doctor_on_vacation');
    }
    if (reason == 'clinic_closed') return AppLocalizations.tr('clinic_closed_day');
    if (reason == 'doctor_day_off') return AppLocalizations.tr('doctor_day_off');
    if (reason == 'all_slots_booked') return AppLocalizations.tr('all_slots_booked');
    if (reason == 'no_schedule_hours') return AppLocalizations.tr('doctor_hours_not_set');
    if (daysLabel.isNotEmpty) {
      return AppLocalizations.tr('no_slots_available').replaceAll('{days}', daysLabel);
    }
    return AppLocalizations.tr('no_data');
  }

  Future<void> _book() async {
    if (_selectedPatient == null || _selectedDoctorId == null || _selectedSlot == null) {
      showErrorSnackBar(context, AppLocalizations.tr('field_required'));
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.bookAppointment(
        patientId: _selectedPatient!.profileId,
        doctorId: _selectedDoctorId!,
        date: _dateStr,
        timeSlot: _selectedSlot!,
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('appointment_booked'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return ReceptionistScaffold(
      title: AppLocalizations.tr('book_appointment'),
      body: _loadingDoctors
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(AppLocalizations.tr('reception_same_day_note'), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.tr('search_patient'),
                      hintText: AppLocalizations.tr('search_patient_hint'),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: _searchPatients,
                  ),
                  if (_patients.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ..._patients.map(
                      (p) => RadioListTile<PatientSearchResult>(
                        title: Text(p.name),
                        subtitle: Text('${p.email ?? ''} ${p.phone ?? ''}'.trim()),
                        value: p,
                        groupValue: _selectedPatient,
                        onChanged: (v) => setState(() => _selectedPatient = v),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedDoctorId,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.tr('doctor'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _doctors
                        .map(
                          (d) => DropdownMenuItem(
                            value: d['id']?.toString(),
                            child: Text((d['name'] ?? 'Doctor').toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedDoctorId = v;
                        _selectedSlot = null;
                        _slots = [];
                      });
                      _loadSlots();
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text('${AppLocalizations.tr('date')}: $_dateStr'),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingSlots)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  else if (_selectedDoctorId != null && _slots.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _slotEmptyMessage() ?? AppLocalizations.tr('no_data'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (_selectedDoctorId != null)
                    DropdownButtonFormField<String>(
                      value: _selectedSlot,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.tr('time_slot'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _slots
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedSlot = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.tr('notes'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saving ? null : _book,
                    child: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(AppLocalizations.tr('book_appointment')),
                  ),
                ],
              ),
            ),
    );
  }
}
