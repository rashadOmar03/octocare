import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import '../models/appointment.dart';
import '../services/api_service.dart';
import '../services/appointment_service.dart';
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
  DateTime? _selectedDate;
  String? _selectedTime;
  List<String> _slots = [];
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
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    if (_selectedDate == null || widget.appointment.doctorId == null) return;
    setState(() => _loadingSlots = true);
    try {
      final dateStr =
          '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final response = await ApiService.instance.get(
        '/receptionist/available-slots?doctor_id=${widget.appointment.doctorId}&date=$dateStr',
      );
      final slots = response is Map ? (response['slots'] as List? ?? []) : [];
      _slots = slots.map((e) => e.toString()).toList();
      if (_selectedTime != null && !_slots.contains(_selectedTime)) {
        _selectedTime = null;
      }
    } catch (_) {
      _slots = [];
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
                Text(AppLocalizations.tr('no_slots_available'))
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
