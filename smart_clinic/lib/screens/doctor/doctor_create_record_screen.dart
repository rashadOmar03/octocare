import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/medical_service.dart';
import '../../widgets/custom_text_field.dart';

class DoctorCreateRecordScreen extends StatefulWidget {
  const DoctorCreateRecordScreen({super.key});

  @override
  State<DoctorCreateRecordScreen> createState() => _DoctorCreateRecordScreenState();
}

class _DoctorCreateRecordScreenState extends State<DoctorCreateRecordScreen> {
  final _formKey = GlobalKey<FormState>();
  final MedicalService _service = MedicalService();
  final _chiefComplaintController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _treatmentController = TextEditingController();
  final _notesController = TextEditingController();
  final _soapSController = TextEditingController();
  final _soapOController = TextEditingController();
  final _soapAController = TextEditingController();
  final _soapPController = TextEditingController();
  String _severity = 'mild';
  bool _isLoading = false;
  Map<String, dynamic>? _patient;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _patient ??= ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
  }

  @override
  void dispose() {
    _chiefComplaintController.dispose();
    _symptomsController.dispose();
    _diagnosisController.dispose();
    _treatmentController.dispose();
    _notesController.dispose();
    _soapSController.dispose();
    _soapOController.dispose();
    _soapAController.dispose();
    _soapPController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _service.createRecord({
        'patient_id': _patient?['id'] ?? _patient?['patient_id'],
        'chief_complaint': _chiefComplaintController.text,
        'symptoms': _symptomsController.text,
        'diagnosis': _diagnosisController.text,
        'severity': _severity,
        'treatment_plan': _treatmentController.text,
        'notes': _notesController.text,
        'soap_subjective': _soapSController.text,
        'soap_objective': _soapOController.text,
        'soap_assessment': _soapAController.text,
        'soap_plan': _soapPController.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Theme.of(context).colorScheme.error));
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('medical_records'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomTextField(controller: _chiefComplaintController, label: AppLocalizations.tr('chief_complaint'), validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null, maxLines: 2),
              CustomTextField(controller: _symptomsController, label: AppLocalizations.tr('symptoms'), maxLines: 3),
              CustomTextField(controller: _diagnosisController, label: AppLocalizations.tr('diagnosis'), validator: (v) => v == null || v.isEmpty ? AppLocalizations.tr('field_required') : null),
              DropdownButtonFormField<String>(
                initialValue: _severity,
                decoration: InputDecoration(labelText: AppLocalizations.tr('severity')),
                items: ['mild', 'moderate', 'severe'].map((s) => DropdownMenuItem(value: s, child: Text(AppLocalizations.tr(s)))).toList(),
                onChanged: (v) => setState(() => _severity = v!),
              ),
              const SizedBox(height: 16),
              CustomTextField(controller: _treatmentController, label: AppLocalizations.tr('treatment_plan'), maxLines: 3),
              CustomTextField(controller: _notesController, label: AppLocalizations.tr('notes'), maxLines: 3),
              ExpansionTile(
                title: Text(AppLocalizations.tr('soap_notes')),
                children: [
                  CustomTextField(controller: _soapSController, label: AppLocalizations.tr('soap_subjective'), maxLines: 2),
                  CustomTextField(controller: _soapOController, label: AppLocalizations.tr('soap_objective'), maxLines: 2),
                  CustomTextField(controller: _soapAController, label: AppLocalizations.tr('soap_assessment'), maxLines: 2),
                  CustomTextField(controller: _soapPController, label: AppLocalizations.tr('soap_plan'), maxLines: 2),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(AppLocalizations.tr('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
