import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/api_service.dart';
import '../../services/medical_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/voice_mic_button.dart';
import '../../utils/ui_helpers.dart';

class DoctorCreatePrescriptionScreen extends StatefulWidget {
  const DoctorCreatePrescriptionScreen({super.key});

  @override
  State<DoctorCreatePrescriptionScreen> createState() => _DoctorCreatePrescriptionScreenState();
}

class _DoctorCreatePrescriptionScreenState extends State<DoctorCreatePrescriptionScreen> {
  final MedicalService _service = MedicalService();
  final _transcriptController = TextEditingController();
  final List<Map<String, TextEditingController>> _medications = [];
  bool _isLoading = false;
  Map<String, dynamic>? _patient;
  DateTime? _prescriptionActiveUntil;

  String _formatDueDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _prescriptionActiveUntil ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _prescriptionActiveUntil != null
          ? TimeOfDay.fromDateTime(_prescriptionActiveUntil!)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (pickedTime == null) return;
    setState(() {
      _prescriptionActiveUntil = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _patient ??= ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (_medications.isEmpty) _addMedication();
  }

  void _addMedication({Map<String, dynamic>? seed}) {
    _medications.add({
      'name': TextEditingController(text: seed?['name']?.toString() ?? ''),
      'dosage': TextEditingController(text: seed?['dosage']?.toString() ?? ''),
      'frequency': TextEditingController(text: seed?['frequency']?.toString() ?? ''),
      'duration': TextEditingController(text: seed?['duration']?.toString() ?? ''),
      'notes': TextEditingController(text: seed?['notes']?.toString() ?? ''),
    });
    setState(() {});
  }

  void _removeMedication(int index) {
    for (var c in _medications[index].values) {
      c.dispose();
    }
    _medications.removeAt(index);
    setState(() {});
  }

  @override
  void dispose() {
    _transcriptController.dispose();
    for (var med in _medications) {
      for (var c in med.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _extractPrescription() async {
    if (_transcriptController.text.trim().isEmpty) {
      showErrorSnackBar(context, AppLocalizations.tr('transcript_required'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final patientId = _patient?['profile_id'] ?? _patient?['id'];
      final response = await ApiService.instance.post('/ai/extract', {
        'text': _transcriptController.text.trim(),
        if (patientId != null) 'patient_id': patientId,
      });
      final rx = (response['prescription'] as List?) ?? [];
      final current = (response['medications_current'] as List?) ?? [];
      for (final m in [...rx, ...current]) {
        if (m is Map) {
          _addMedication(seed: {
            'name': m['name'],
            'dosage': m['dosage'],
            'frequency': m['frequency'],
            'duration': m['duration'],
            'notes': m['notes'],
          });
        }
      }
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('prescription_extracted'));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (_medications.isEmpty || _medications.first['name']!.text.isEmpty) {
      showErrorSnackBar(context, AppLocalizations.tr('field_required'));
      return;
    }
    if (_prescriptionActiveUntil == null) {
      showErrorSnackBar(context, AppLocalizations.tr('prescription_due_date_required'));
      return;
    }
    if (!_prescriptionActiveUntil!.isAfter(DateTime.now())) {
      showErrorSnackBar(context, AppLocalizations.tr('active_until_future'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _service.createPrescription({
        'patient': _patient?['profile_id'] ?? _patient?['id'],
        'active_until': _prescriptionActiveUntil!.toUtc().toIso8601String(),
        'items': _medications.map((m) => {
              'medication_name': m['name']!.text,
              'dosage': m['dosage']!.text,
              'frequency': m['frequency']!.text,
              'duration': m['duration']!.text,
              'notes': m['notes']!.text,
            }).toList(),
      });
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('success'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = _patient != null ? '${_patient!['first_name'] ?? ''} ${_patient!['last_name'] ?? ''}'.trim() : '';

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('add_prescription'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(name),
                  subtitle: Text(AppLocalizations.tr('patient')),
                ),
              ),
            const SizedBox(height: 16),
            Text(AppLocalizations.tr('prescription_transcript'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            CustomTextField(
              controller: _transcriptController,
              hint: AppLocalizations.tr('prescription_transcript_hint'),
              maxLines: 5,
              suffix: VoiceMicSuffix(controller: _transcriptController),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _extractPrescription,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(AppLocalizations.tr('extract_prescription')),
            ),
            const SizedBox(height: 16),
            Text(AppLocalizations.tr('manual_entry'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...List.generate(_medications.length, (i) => _buildMedicationCard(i)),
            OutlinedButton.icon(
              onPressed: _addMedication,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.tr('add_medication')),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event),
                title: Text(AppLocalizations.tr('prescription_due_date')),
                subtitle: Text(
                  _prescriptionActiveUntil != null
                      ? _formatDueDate(_prescriptionActiveUntil!)
                      : AppLocalizations.tr('prescription_due_date_hint'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDueDate,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.tr('save')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationCard(int index) {
    final med = _medications[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${AppLocalizations.tr('medication_name')} ${index + 1}', style: Theme.of(context).textTheme.titleSmall),
                if (_medications.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Color(0xFFD32F2F)),
                    onPressed: () => _removeMedication(index),
                  ),
              ],
            ),
            CustomTextField(controller: med['name']!, label: AppLocalizations.tr('medication_name'), prefixIcon: Icons.medication),
            Row(
              children: [
                Expanded(child: CustomTextField(controller: med['dosage']!, label: '${AppLocalizations.tr('dosage')} (${AppLocalizations.tr('optional_field')})')),
                const SizedBox(width: 8),
                Expanded(child: CustomTextField(controller: med['frequency']!, label: '${AppLocalizations.tr('frequency')} (${AppLocalizations.tr('optional_field')})')),
              ],
            ),
            Row(
              children: [
                Expanded(child: CustomTextField(controller: med['duration']!, label: '${AppLocalizations.tr('duration')} (${AppLocalizations.tr('optional_field')})')),
                const SizedBox(width: 8),
                Expanded(child: CustomTextField(controller: med['notes']!, label: AppLocalizations.tr('notes'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
