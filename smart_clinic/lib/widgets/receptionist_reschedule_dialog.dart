import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import '../models/appointment.dart';
import '../services/appointment_service.dart';
import '../services/receptionist_service.dart';
import '../utils/time_format.dart';

class ReceptionistRescheduleDialog extends StatefulWidget {
  final Appointment appointment;
  final bool confirmAfter;
  final String? title;

  const ReceptionistRescheduleDialog({
    super.key,
    required this.appointment,
    this.confirmAfter = true,
    this.title,
  });

  static Future<bool?> show(
    BuildContext context,
    Appointment appointment, {
    bool confirmAfter = true,
    String? title,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ReceptionistRescheduleDialog(
        appointment: appointment,
        confirmAfter: confirmAfter,
        title: title,
      ),
    );
  }

  @override
  State<ReceptionistRescheduleDialog> createState() => _ReceptionistRescheduleDialogState();
}

class _ReceptionistRescheduleDialogState extends State<ReceptionistRescheduleDialog> {
  final AppointmentService _service = AppointmentService();
  final ReceptionistService _receptionistService = ReceptionistService();
  DateTime? _selectedDate;
  String? _selectedTime;
  List<String> _slots = [];
  String? _slotsReason;
  String? _slotsDaysLabel;
  String? _vacationReason;
  bool _confirm = true;
  bool _loading = false;
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    _confirm = widget.confirmAfter;
    if (widget.appointment.date != null) {
      final parts = widget.appointment.date!.split('-');
      if (parts.length == 3) {
        _selectedDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    }
    _selectedDate ??= DateTime.now();
    _selectedTime = widget.appointment.timeSlot;
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    if (_selectedDate == null || widget.appointment.doctorId == null) return;
    setState(() => _loadingSlots = true);
    try {
      final dateStr =
          '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final result = await _receptionistService.fetchAvailableSlotsMeta(
        widget.appointment.doctorId!,
        dateStr,
        excludeAppointmentId: widget.appointment.id,
      );
      _slots = List<String>.from(result['slots'] as List? ?? []);
      _slotsReason = result['reason']?.toString();
      _slotsDaysLabel = result['working_days_label']?.toString();
      _vacationReason = result['vacation_reason']?.toString();
      if (_selectedTime != null && !_slots.contains(_selectedTime)) {
        _selectedTime = _slots.isNotEmpty ? _slots.first : null;
      }
    } catch (_) {
      _slots = [];
      _slotsReason = null;
      _slotsDaysLabel = null;
      _vacationReason = null;
      _selectedTime = null;
    }
    setState(() => _loadingSlots = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadSlots();
    }
  }

  String? _emptySlotsMessage() {
    if (_slots.isNotEmpty) return null;
    final reason = _slotsReason;
    final daysLabel = _slotsDaysLabel ?? '';
    if (reason == 'vacation') {
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
    return AppLocalizations.tr('no_slots_available').replaceAll('{days}', daysLabel);
  }

  Future<void> _save() async {
    if (_selectedDate == null || _selectedTime == null || widget.appointment.id == null) return;
    setState(() => _loading = true);
    try {
      final dateStr =
          '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      await _service.receptionistReschedule(widget.appointment.id!, {
        'date': dateStr,
        'time_slot': _selectedTime,
        'confirm': _confirm,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final emptyMessage = _emptySlotsMessage();

    return AlertDialog(
      title: Text(widget.title ?? AppLocalizations.tr('reschedule')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.appointment.patientName ?? '', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(_selectedDate == null
                    ? AppLocalizations.tr('select_date')
                    : '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'),
              ),
              const SizedBox(height: 12),
              Text(AppLocalizations.tr('select_time'), style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              if (_loadingSlots)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else if (_slots.isEmpty)
                Text(
                  emptyMessage ?? AppLocalizations.tr('no_data'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _slots.map((slot) {
                    final selected = _selectedTime == slot;
                    return ChoiceChip(
                      label: Text(TimeFormat.format24To12(slot)),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedTime = slot),
                    );
                  }).toList(),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirm,
                onChanged: (v) => setState(() => _confirm = v ?? true),
                title: Text(AppLocalizations.tr('confirm_after_reschedule')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.tr('cancel'))),
        ElevatedButton(
          onPressed: _loading || _selectedTime == null ? null : _save,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(AppLocalizations.tr('save')),
        ),
      ],
    );
  }
}
