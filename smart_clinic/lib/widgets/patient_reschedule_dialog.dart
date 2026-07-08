import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import '../models/appointment.dart';
import '../services/appointment_service.dart';
import '../utils/time_format.dart';

class PatientRescheduleDialog extends StatefulWidget {
  final Appointment appointment;

  const PatientRescheduleDialog({super.key, required this.appointment});

  static Future<bool?> show(BuildContext context, Appointment appointment) {
    return showDialog<bool>(
      context: context,
      builder: (_) => PatientRescheduleDialog(appointment: appointment),
    );
  }

  @override
  State<PatientRescheduleDialog> createState() => _PatientRescheduleDialogState();
}

class _PatientRescheduleDialogState extends State<PatientRescheduleDialog> {
  final AppointmentService _service = AppointmentService();
  DateTime? _selectedDate;
  String? _selectedTime;
  List<Map<String, dynamic>> _slots = [];
  bool _loading = false;
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    if (widget.appointment.date != null) {
      final parts = widget.appointment.date!.split('-');
      if (parts.length == 3) {
        _selectedDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    }
    _selectedDate ??= DateTime.now().add(const Duration(days: 1));
    _selectedTime = widget.appointment.timeSlot;
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    if (_selectedDate == null || widget.appointment.doctorId == null) return;
    setState(() => _loadingSlots = true);
    try {
      final dateStr =
          '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final result = await _service.fetchAvailableSlots(
        widget.appointment.doctorId!,
        dateStr,
        excludeAppointmentId: widget.appointment.id,
      );
      _slots = (result['slots'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (_selectedTime != null && !_slots.any((s) => s['time'] == _selectedTime)) {
        _selectedTime = _slots.isNotEmpty ? _slots.first['time']?.toString() : null;
      }
    } catch (_) {
      _slots = [];
      _selectedTime = null;
    }
    setState(() => _loadingSlots = false);
  }

  Future<void> _pickDate() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadSlots();
    }
  }

  Future<void> _save() async {
    if (_selectedDate == null || _selectedTime == null || widget.appointment.id == null) return;
    setState(() => _loading = true);
    try {
      final dateStr =
          '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      await _service.rescheduleAppointment(widget.appointment.id!, {
        'date': dateStr,
        'time_slot': _selectedTime,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.tr('reschedule')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.appointment.doctorName != null)
                Text(widget.appointment.doctorName!, style: Theme.of(context).textTheme.titleMedium),
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
                Text(AppLocalizations.tr('no_slots_available'))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _slots.map((slot) {
                    final time = slot['time']?.toString() ?? '';
                    final available = slot['available'] as bool? ?? true;
                    final selected = _selectedTime == time;
                    return ChoiceChip(
                      label: Text(TimeFormat.format24To12(time)),
                      selected: selected,
                      onSelected: available ? (_) => setState(() => _selectedTime = time) : null,
                    );
                  }).toList(),
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
