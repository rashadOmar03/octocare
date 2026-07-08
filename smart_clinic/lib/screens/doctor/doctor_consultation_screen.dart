import 'dart:convert';

import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../services/api_service.dart';
import '../../models/appointment.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/structured_soap_view.dart';
import '../../widgets/ai_review_panel.dart';
import '../../widgets/voice_mic_button.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/time_format.dart';
import '../../utils/ui_helpers.dart';

class DoctorConsultationScreen extends StatefulWidget {
  final Appointment? initialAppointment;
  final Map<String, dynamic>? initialPatient;
  final String? initialRecordId;

  const DoctorConsultationScreen({
    super.key,
    this.initialAppointment,
    this.initialPatient,
    this.initialRecordId,
  });

  @override
  State<DoctorConsultationScreen> createState() => _DoctorConsultationScreenState();
}

class _DoctorConsultationScreenState extends State<DoctorConsultationScreen> with SingleTickerProviderStateMixin {
  final _transcriptController = TextEditingController();
  final _reviewPromptController = TextEditingController();
  final _chiefComplaintController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _severityController = TextEditingController();
  final _treatmentPlanController = TextEditingController();
  final _followUpController = TextEditingController();
  final _soapSController = TextEditingController();
  final _soapOController = TextEditingController();
  final _soapAController = TextEditingController();
  final _soapPController = TextEditingController();
  final _scrollController = ScrollController();
  final _soapSectionKey = GlobalKey();
  int _soapViewGeneration = 0;

  bool _isLoading = false;
  bool _soapEditable = false;
  bool _hasExtracted = false;
  bool _recordLoaded = false;
  String? _recordId;
  Appointment? _appointment;
  Map<String, dynamic>? _structuredData;
  List<dynamic> _prescription = [];
  List<dynamic> _currentMedications = [];
  List<dynamic> _symptomsList = [];
  DateTime? _prescriptionActiveUntil;
  List<Map<String, dynamic>> _reviewSuggestions = [];
  final Set<int> _ignoredReviewIndexes = {};
  bool _showReviewPanel = false;
  String _reviewMessage = '';
  String? _reviewAnswer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  bool get _isEditOnly =>
      _appointment?.status == 'completed' || (_recordLoaded && _recordId != null && _appointment == null);
  bool get _hasSavedRecord => _recordId != null || _recordLoaded || _appointment?.medicalRecordId != null;
  bool get _canMarkCompleted => _hasSavedRecord && !_isEditOnly && !_isStandalone;
  bool get _isStandalone => _appointment == null && _standalonePatient != null;
  Map<String, dynamic>? _standalonePatient;
  bool _needsListRefresh = false;

  Future<void> _bootstrap() async {
    // Primary source: constructor parameters (reliable on Flutter web)
    _appointment ??= widget.initialAppointment;
    _standalonePatient ??= widget.initialPatient;
    _recordId ??= widget.initialRecordId;

    // Fallback: route arguments (for routes map / other callers)
    if (_appointment == null && _standalonePatient == null && _recordId == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Appointment) {
        _appointment = args;
      } else if (args is Map) {
        if (args['appointment'] is Appointment) {
          _appointment = args['appointment'] as Appointment;
        }
        if (args['patient'] is Map) {
          _standalonePatient = Map<String, dynamic>.from(args['patient'] as Map);
        }
        if (args['record_id'] != null) {
          _recordId = args['record_id'].toString();
        }
      }
    }

    if (_appointment == null && _standalonePatient == null && _recordId == null) {
      if (mounted) {
        showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
        Navigator.pop(context, false);
      }
      return;
    }

    if (mounted) setState(() {});

    await _refreshAppointmentFromServer();
    if (mounted) setState(() {});

    await _ensureConsultationStarted();
    if (mounted) setState(() {});

    if (_recordId != null || _appointment?.id != null || _appointment?.medicalRecordId != null) {
      await _loadExistingRecord();
    }
  }

  Future<void> _ensureConsultationStarted() async {
    if (_appointment == null || _appointment!.id == null) return;
    final status = _appointment!.status;
    if (status == 'completed' || status == 'cancelled') return;
    if (_appointment!.hasConsultation || _appointment!.medicalRecordId != null) return;
    try {
      final response = await ApiService.instance.put(
        '/appointments/${_appointment!.id}/start-consultation', {},
      );
      if (response is Map) {
        _appointment = Appointment.fromJson(Map<String, dynamic>.from(response));
      }
    } catch (e) {
      debugPrint('[Consultation] Failed to start consultation: $e');
      if (mounted) {
        final msg = e.toString();
        if (msg.toLowerCase().contains('payment')) {
          showErrorSnackBar(context, AppLocalizations.tr('payment_required_consultation'));
        }
      }
    }
  }

  Future<void> _refreshAppointmentFromServer() async {
    if (_appointment?.id == null) return;
    try {
      final data = Map<String, dynamic>.from(
        await ApiService.instance.get('/appointments/${_appointment!.id}'),
      );
      _appointment = Appointment.fromJson(data);
    } catch (e) {
      debugPrint('[Consultation] Failed to refresh appointment: $e');
    }
  }

  Future<void> _loadExistingRecord() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> data;
      final recordId = _recordId ?? _appointment?.medicalRecordId;
      if (recordId != null) {
        data = Map<String, dynamic>.from(
          await ApiService.instance.get('/records/$recordId'),
        );
      } else if (_appointment?.id != null) {
        data = Map<String, dynamic>.from(
          await ApiService.instance.get('/records/by-appointment/${_appointment!.id}'),
        );
      } else {
        return;
      }
      _recordId = data['id']?.toString();
      _loadRecordIntoForm(data);
      setState(() {
        _recordLoaded = true;
        _hasExtracted = true;
        _soapEditable = true;
        _soapViewGeneration++;
      });
    } catch (e) {
      if (_appointment?.status == 'completed' && mounted) {
        showErrorSnackBar(context, AppLocalizations.tr('no_consultation_to_edit'));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onStructuredChanged({
    Map<String, dynamic>? structured,
    List<dynamic>? prescription,
    List<dynamic>? currentMedications,
    List<dynamic>? symptomsList,
    DateTime? prescriptionActiveUntil,
  }) {
    setState(() {
      if (structured != null) _structuredData = structured;
      if (prescription != null) _prescription = prescription;
      if (currentMedications != null) _currentMedications = currentMedications;
      if (symptomsList != null) _symptomsList = symptomsList;
      _prescriptionActiveUntil = prescriptionActiveUntil;
    });
    _syncSummaryFields();
  }

  void _syncSummaryFields() {
    final activeSymptoms = _symptomsList
        .where((s) => s is Map && s['active'] != false)
        .map((s) => (s as Map)['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .join('; ');
    if (activeSymptoms.isNotEmpty) _symptomsController.text = activeSymptoms;

    final diagnoses = (_structuredData?['diagnoses'] as List?) ?? [];
    final activeDiagnoses = diagnoses
        .map((d) => d is Map ? d['name']?.toString() : d.toString())
        .where((n) => n != null && n.trim().isNotEmpty)
        .join('; ');
    if (activeDiagnoses.isNotEmpty) _diagnosisController.text = activeDiagnoses;
  }

  List<dynamic> _activePrescriptionForSave() {
    return _prescription.where((m) {
      if (m is Map) return m['active'] != false && (m['name']?.toString().trim().isNotEmpty ?? false);
      return m.toString().trim().isNotEmpty;
    }).map((m) {
      if (m is Map) {
        return {
          'name': m['name'],
          'dosage': m['dosage'],
          'frequency': m['frequency'],
          'route': m['route'],
          'duration': m['duration'],
          'notes': m['notes'],
        };
      }
      return {'name': m.toString()};
    }).toList();
  }

  void _loadRecordIntoForm(Map<String, dynamic> data) {
    _chiefComplaintController.text = (data['chief_complaint'] ?? '').toString();
    _symptomsController.text = (data['symptoms'] ?? '').toString();
    _diagnosisController.text = (data['diagnosis'] ?? '').toString();
    _severityController.text = (data['severity'] ?? 'moderate').toString();
    _treatmentPlanController.text = (data['treatment_plan'] ?? '').toString();
    _transcriptController.text = (data['notes'] ?? '').toString();
    _soapSController.text = (data['soap_subjective'] ?? '').toString();
    _soapOController.text = (data['soap_objective'] ?? '').toString();
    _soapAController.text = (data['soap_assessment'] ?? '').toString();
    _soapPController.text = (data['soap_plan'] ?? '').toString();
    final structuredRaw = data['structured_data'];
    dynamic structured = structuredRaw;
    if (structured is String && structured.trim().isNotEmpty) {
      try {
        structured = jsonDecode(structured);
      } catch (_) {}
    }
    if (structured is Map) {
      _structuredData = Map<String, dynamic>.from(structured);
      final prescription = _structuredData?['prescription'];
      if (prescription is List) _prescription = List<dynamic>.from(prescription);
      final currentMeds = _structuredData?['medications_current'];
      if (currentMeds is List) _currentMedications = List<dynamic>.from(currentMeds);
      final symptoms = _structuredData?['symptoms'];
      if (symptoms is List) _symptomsList = List<dynamic>.from(symptoms);
      final rawUntil = _structuredData?['prescription_active_until'];
      if (rawUntil != null && rawUntil.toString().trim().isNotEmpty) {
        _prescriptionActiveUntil = DateTime.tryParse(rawUntil.toString());
      }
      final followItems = _structuredData?['follow_up_items'];
      if (followItems is List && followItems.isNotEmpty) {
        _followUpController.text = followItems.map((e) => e.toString()).join('\n');
      } else if (_structuredData?['follow_up'] != null) {
        _followUpController.text = _structuredData!['follow_up'].toString();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appointment != null || _standalonePatient != null) return;
    _appointment ??= widget.initialAppointment;
    _standalonePatient ??= widget.initialPatient;
    _recordId ??= widget.initialRecordId;
    if (_appointment != null || _standalonePatient != null) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Appointment) {
      _appointment = args;
    } else if (args is Map) {
      if (args['appointment'] is Appointment) {
        _appointment = args['appointment'] as Appointment;
      }
      if (args['patient'] is Map) {
        _standalonePatient = Map<String, dynamic>.from(args['patient'] as Map);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _reviewPromptController.dispose();
    _transcriptController.dispose();
    _chiefComplaintController.dispose();
    _symptomsController.dispose();
    _diagnosisController.dispose();
    _severityController.dispose();
    _treatmentPlanController.dispose();
    _followUpController.dispose();
    _soapSController.dispose();
    _soapOController.dispose();
    _soapAController.dispose();
    _soapPController.dispose();
    super.dispose();
  }

  Future<void> _extractFromTranscript() async {
    if (_transcriptController.text.trim().isEmpty) {
      showErrorSnackBar(context, AppLocalizations.tr('transcript_required'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.post('/ai/extract', {
        'text': _transcriptController.text.trim(),
        'patient_id': _appointment?.patientId,
      });
      _applyExtraction(Map<String, dynamic>.from(response));
      setState(() {
        _hasExtracted = true;
        _soapEditable = true;
      });
      if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('soap_extracted'));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyExtraction(Map<String, dynamic> response) {
    _chiefComplaintController.text = (response['chief_complaint'] ?? '').toString();
    _symptomsController.text = (response['symptoms'] ?? '').toString();
    _diagnosisController.text = (response['diagnosis'] ?? '').toString();
    _severityController.text = (response['severity'] ?? 'unknown').toString();
    _treatmentPlanController.text = (response['treatment_plan'] ?? '').toString();
    _followUpController.text = (response['follow_up'] ?? '').toString();
    final followItems = response['follow_up_items'];
    if (followItems is List && followItems.isNotEmpty) {
      _followUpController.text = followItems.map((e) => e.toString()).join('\n');
    }

    _soapSController.text = (response['subjective'] ?? '').toString();
    _soapOController.text = (response['objective'] ?? '').toString();
    _soapAController.text = (response['assessment'] ?? '').toString();
    _soapPController.text = (response['plan'] ?? '').toString();

    final structuredRaw = response['structured'] ?? response['extracted_data'];
    if (structuredRaw is Map) {
      _structuredData = Map<String, dynamic>.from(structuredRaw);
    }
    _prescription = List<dynamic>.from(response['prescription'] ?? response['medications'] ?? []);
    _currentMedications = List<dynamic>.from(response['medications_current'] ?? []);
    _symptomsList = List<dynamic>.from(response['symptoms_list'] ?? []);

    final structured = _structuredData;
    if (structured != null) {
      final dx = (structured['diagnoses'] as List?)?.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList() ?? [];
      if (dx.isNotEmpty) {
        _diagnosisController.text = dx.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
        _soapAController.text = _diagnosisController.text;
      }
      final plan = (structured['soap_note'] as Map?)?['plan'];
      if (plan is List && plan.isNotEmpty) {
        _soapPController.text = plan.map((e) => '• $e').join('\n');
        _treatmentPlanController.text = _soapPController.text;
      }
      final cur = structured['medications_current'];
      if (cur is List) _currentMedications = List<dynamic>.from(cur);
    }

    setState(() {
      _reviewSuggestions = [];
      _ignoredReviewIndexes.clear();
      _showReviewPanel = false;
      _reviewMessage = '';
      _reviewAnswer = null;
      _reviewPromptController.clear();
      _tabController.index = 0;
    });
  }

  Future<void> _runAiReview() async {
    if (_transcriptController.text.trim().isEmpty) {
      showErrorSnackBar(context, AppLocalizations.tr('transcript_required'));
      return;
    }
    if (_structuredData == null) {
      showErrorSnackBar(context, AppLocalizations.tr('extract_before_review'));
      return;
    }
    final prompt = _reviewPromptController.text.trim();
    if (prompt.isEmpty) {
      showErrorSnackBar(context, AppLocalizations.tr('review_prompt_required'));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.post('/ai/extract/review', {
        'text': _transcriptController.text.trim(),
        'extracted_data': _structuredData,
        'prompt': prompt,
      });
      final list = (response['suggestions'] as List?) ?? [];
      setState(() {
        _reviewAnswer = response['answer']?.toString();
        _reviewMessage = (response['message'] ?? '').toString();
        _reviewSuggestions = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _ignoredReviewIndexes.clear();
        _showReviewPanel = true;
        _tabController.index = 1;
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyReviewSuggestion(int index) {
    if (index < 0 || index >= _reviewSuggestions.length) return;
    final s = _reviewSuggestions[index];
    final category = s['category']?.toString() ?? '';
    final value = s['suggested_value']?.toString().trim() ?? '';
    if (value.isEmpty) return;

    _structuredData ??= {};
    setState(() {
      switch (category) {
        case 'symptoms':
          _symptomsList.add({'name': value, 'duration': null, 'severity': null, 'location': null, 'active': true});
          _structuredData!['symptoms'] = _symptomsList;
        case 'diagnoses':
          final dx = (_structuredData!['diagnoses'] as List?)?.map((e) => e.toString()).toList() ?? [];
          if (!dx.contains(value)) {
            dx.add(value);
            _structuredData!['diagnoses'] = dx;
            final soap = Map<String, dynamic>.from((_structuredData!['soap_note'] as Map?) ?? {});
            soap['assessment'] = dx;
            _structuredData!['soap_note'] = soap;
            _diagnosisController.text = dx.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
          }
        case 'medications_current':
          _currentMedications.add({
            'name': value,
            'action': 'Continue',
            'dosage': '',
            'frequency': '',
            'route': '',
            'duration': '',
            'notes': '',
            'active': true,
          });
          _structuredData!['medications_current'] = _currentMedications;
        case 'prescription':
          _prescription.add({
            'name': value,
            'action': 'Start',
            'dosage': '',
            'frequency': '',
            'route': '',
            'duration': '',
            'notes': '',
            'active': true,
          });
          _structuredData!['prescription'] = _prescription;
        case 'plan':
          final soap = Map<String, dynamic>.from((_structuredData!['soap_note'] as Map?) ?? {});
          final plan = (soap['plan'] as List?)?.map((e) => e.toString()).toList() ?? [];
          if (!plan.contains(value)) plan.add(value);
          soap['plan'] = plan;
          _structuredData!['soap_note'] = soap;
          _soapPController.text = plan.map((p) => '• $p').join('\n');
          _treatmentPlanController.text = _soapPController.text;
        case 'allergies':
          _appendHistoryList('allergies', value);
        case 'medical_history':
          _appendHistoryList('past_medical_history', value);
        case 'chronic_diseases':
          _appendHistoryList('chronic_diseases', value);
        case 'existing_conditions':
          _appendHistoryList('existing_conditions', value);
        case 'family_history':
          _appendHistoryList('family_history', value);
        case 'social_history':
          _appendHistoryList('social_history', value);
        case 'previous_surgeries':
          _appendHistoryList('previous_surgeries', value);
        case 'follow_up':
          final items = (_structuredData!['follow_up_items'] as List?)?.map((e) => e.toString()).toList() ?? [];
          if (!items.contains(value)) {
            items.add(value);
            _structuredData!['follow_up_items'] = items;
            _structuredData!['follow_up'] = items.join('; ');
            _followUpController.text = items.join('\n');
          }
        case 'clinical_findings':
          final findings = (_structuredData!['clinical_findings'] as List?)?.map((e) => e.toString()).toList() ?? [];
          if (!findings.contains(value)) {
            findings.add(value);
            _structuredData!['clinical_findings'] = findings;
          }
        case 'laboratory_results':
          _appendObjectiveList('laboratory_results', value);
        case 'imaging':
          _appendObjectiveList('imaging', value);
        case 'ecg':
          _appendObjectiveList('ecg', value);
        case 'echocardiogram':
          _appendObjectiveList('echo', value);
        case 'doctor_notes':
          final notes = (_structuredData!['doctor_notes'] as List?)?.map((e) => e.toString()).toList() ?? [];
          if (!notes.contains(value)) {
            notes.add(value);
            _structuredData!['doctor_notes'] = notes;
          }
        default:
          final notes = (_structuredData!['doctor_notes'] as List?)?.map((e) => e.toString()).toList() ?? [];
          notes.add(value);
          _structuredData!['doctor_notes'] = notes;
      }
      _ignoredReviewIndexes.add(index);
    });
    _syncSummaryFields();
    if (mounted) showSuccessSnackBar(context, AppLocalizations.tr('success'));
  }

  void _appendHistoryList(String key, String value) {
    final mh = Map<String, dynamic>.from((_structuredData!['medical_history'] as Map?) ?? {});
    final list = (mh[key] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (!list.contains(value)) list.add(value);
    mh[key] = list;
    _structuredData!['medical_history'] = mh;
  }

  void _appendObjectiveList(String key, String value) {
    final soap = Map<String, dynamic>.from((_structuredData!['soap_note'] as Map?) ?? {});
    final obj = Map<String, dynamic>.from((soap['objective'] as Map?) ?? {});
    final list = (obj[key] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (!list.contains(value)) list.add(value);
    obj[key] = list;
    soap['objective'] = obj;
    _structuredData!['soap_note'] = soap;
  }

  bool _isEmpty(String? value) => value == null || value.trim().isEmpty;

  bool _validatePrescriptionDueDate() {
    final activeMeds = _activePrescriptionForSave();
    if (activeMeds.isEmpty) return true;
    if (_prescriptionActiveUntil == null) {
      showErrorSnackBar(context, AppLocalizations.tr('prescription_due_date_required'));
      return false;
    }
    if (!_prescriptionActiveUntil!.isAfter(DateTime.now())) {
      showErrorSnackBar(context, AppLocalizations.tr('active_until_future'));
      return false;
    }
    return true;
  }

  Future<bool> _resolveMissingFields() async {
    final checks = <MapEntry<TextEditingController, String>>[
      MapEntry(_chiefComplaintController, AppLocalizations.tr('chief_complaint')),
      MapEntry(_symptomsController, AppLocalizations.tr('symptoms')),
      MapEntry(_diagnosisController, AppLocalizations.tr('diagnosis')),
      MapEntry(_severityController, AppLocalizations.tr('severity')),
      MapEntry(_treatmentPlanController, AppLocalizations.tr('treatment_plan')),
      MapEntry(_soapSController, AppLocalizations.tr('soap_subjective')),
      MapEntry(_soapOController, AppLocalizations.tr('soap_objective')),
      MapEntry(_soapAController, AppLocalizations.tr('soap_assessment')),
      MapEntry(_soapPController, AppLocalizations.tr('soap_plan')),
    ];

    for (final entry in checks) {
      if (!_isEmpty(entry.key.text)) continue;
      if (!mounted) return false;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.tr('missing_field_title')),
          content: Text(AppLocalizations.tr('missing_field_body').replaceAll('{field}', entry.value)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'skip'), child: Text(AppLocalizations.tr('skip_field'))),
            TextButton(onPressed: () => Navigator.pop(ctx, 'add'), child: Text(AppLocalizations.tr('add_field'))),
          ],
        ),
      );
      if (action == 'add') {
        final value = await _promptFieldValue(entry.value);
        if (value == null) return false;
        entry.key.text = value;
      }
    }
    return true;
  }

  Future<String?> _promptFieldValue(String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: controller, maxLines: 4, decoration: InputDecoration(border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(AppLocalizations.tr('save'))),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _confirmAndSave({bool completeOnly = false}) async {
    final patientId = _appointment?.patientId ??
        _standalonePatient?['profile_id']?.toString() ??
        _standalonePatient?['id']?.toString();
    if (patientId == null) {
      showErrorSnackBar(context, AppLocalizations.tr('patient_required'));
      return;
    }

    if (_isEditOnly && completeOnly) {
      showErrorSnackBar(context, AppLocalizations.tr('consultation_already_completed'));
      return;
    }

    if (!completeOnly) {
      final ok = await _resolveMissingFields();
      if (!ok) return;
      if (!_validatePrescriptionDueDate()) return;
    }

    setState(() => _isLoading = true);
    try {
      if (!completeOnly) {
        final notes = _transcriptController.text.trim();
        if (_structuredData != null && _followUpController.text.trim().isNotEmpty) {
          final lines = _followUpController.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          _structuredData!['follow_up_items'] = lines;
          _structuredData!['follow_up'] = lines.join('; ');
        }
        final treatment = [
          _treatmentPlanController.text.trim(),
          if (_followUpController.text.trim().isNotEmpty) 'Follow-up: ${_followUpController.text.trim()}',
        ].where((s) => s.isNotEmpty).join('\n');

        final payload = {
          if (_appointment?.id != null) 'appointment_id': _appointment!.id,
          'patient_id': patientId,
          'chief_complaint': _chiefComplaintController.text.trim().isNotEmpty
              ? _chiefComplaintController.text.trim()
              : 'Consultation',
          'symptoms': _symptomsController.text.trim().isNotEmpty ? _symptomsController.text.trim() : 'See SOAP subjective',
          'diagnosis': _diagnosisController.text.trim().isNotEmpty ? _diagnosisController.text.trim() : 'See SOAP assessment',
          'severity': _severityController.text.trim().isNotEmpty ? _severityController.text.trim() : 'unknown',
          'treatment_plan': treatment.isNotEmpty ? treatment : 'See SOAP plan',
          'notes': notes,
          'soap_subjective': _soapSController.text.trim(),
          'soap_objective': _soapOController.text.trim(),
          'soap_assessment': _soapAController.text.trim(),
          'soap_plan': _soapPController.text.trim(),
          if (_structuredData != null) 'structured_data': jsonEncode(_structuredData),
          'prescription': _activePrescriptionForSave(),
          if (_prescriptionActiveUntil != null)
            'prescription_active_until': _prescriptionActiveUntil!.toUtc().toIso8601String(),
        };

        Map<String, dynamic> saved;
        final existingId = _recordId ?? _appointment?.medicalRecordId;
        if (existingId != null) {
          saved = Map<String, dynamic>.from(await ApiService.instance.put('/records/$existingId', payload));
        } else {
          saved = Map<String, dynamic>.from(await ApiService.instance.post('/records/', payload));
        }
        _recordId = saved['id']?.toString() ?? existingId;
        if (_appointment != null && _recordId != null) {
          _appointment = Appointment(
            id: _appointment!.id,
            patientId: _appointment!.patientId,
            doctorId: _appointment!.doctorId,
            patientName: _appointment!.patientName,
            doctorName: _appointment!.doctorName,
            specialtyName: _appointment!.specialtyName,
            date: _appointment!.date,
            timeSlot: _appointment!.timeSlot,
            status: _appointment!.status,
            notes: _appointment!.notes,
            queueNumber: _appointment!.queueNumber,
            createdAt: _appointment!.createdAt,
            isPaid: _appointment!.isPaid,
            paymentStatus: _appointment!.paymentStatus,
            needsPayment: _appointment!.needsPayment,
            medicalRecordId: _recordId,
            hasConsultation: true,
          );
        }
        setState(() {
          _recordLoaded = true;
          _hasExtracted = true;
          _soapEditable = true;
          _needsListRefresh = true;
        });
      }

      if (!_isEditOnly && !_isStandalone && completeOnly && _appointment?.id != null) {
        await ApiService.instance.put('/appointments/${_appointment!.id}/complete', {});
      }

      if (mounted) {
        showSuccessSnackBar(
          context,
          completeOnly
              ? AppLocalizations.tr('appointment_completed')
              : (_hasSavedRecord && _isEditOnly
                  ? AppLocalizations.tr('consultation_updated')
                  : AppLocalizations.tr('record_saved_history')),
        );
        if (completeOnly || _isEditOnly) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _markCompletedOnly() async {
    if (!_canMarkCompleted) {
      showErrorSnackBar(context, AppLocalizations.tr('complete_requires_save_first'));
      return;
    }
    if (_recordId == null && _appointment?.medicalRecordId == null) {
      await _loadExistingRecord();
    }
    if (_recordId == null && _appointment?.medicalRecordId == null) {
      showErrorSnackBar(context, AppLocalizations.tr('save_record_before_complete'));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('mark_completed')),
        content: Text(AppLocalizations.tr('mark_completed_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.tr('yes'))),
        ],
      ),
    );
    if (confirm == true) await _confirmAndSave(completeOnly: true);
  }

  void _openPatientSensors() {
    if (_appointment?.patientId == null) return;
    Navigator.pushNamed(
      context,
      AppRoutes.doctorSensors,
      arguments: {
        'patient_id': _appointment!.patientId,
        'patient_name': _appointment!.patientName ?? 'Patient',
      },
    );
  }

  void _rejectNotes() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.tr('reject_notes_title')),
        content: Text(AppLocalizations.tr('reject_notes_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('cancel'))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearAll();
            },
            child: Text(AppLocalizations.tr('reject_clear')),
          ),
        ],
      ),
    );
  }

  void _clearAll() {
    _transcriptController.clear();
    _chiefComplaintController.clear();
    _symptomsController.clear();
    _diagnosisController.clear();
    _severityController.clear();
    _treatmentPlanController.clear();
    _followUpController.clear();
    _soapSController.clear();
    _soapOController.clear();
    _soapAController.clear();
    _soapPController.clear();
    setState(() {
      _hasExtracted = false;
      _soapEditable = false;
      _structuredData = null;
      _prescription = [];
      _currentMedications = [];
      _symptomsList = [];
      _reviewSuggestions = [];
      _ignoredReviewIndexes.clear();
      _showReviewPanel = false;
      _reviewMessage = '';
      _reviewAnswer = null;
      _reviewPromptController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabHeight = (MediaQuery.sizeOf(context).height * 0.42).clamp(280.0, 480.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _needsListRefresh || _recordId != null);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isEditOnly ? AppLocalizations.tr('edit_consultation') : AppLocalizations.tr('consultation')),
        actions: [
          if (_appointment?.patientId != null)
            IconButton(
              icon: const Icon(Icons.sensors),
              tooltip: AppLocalizations.tr('view_sensors'),
              onPressed: _openPatientSensors,
            ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_appointment != null)
              Card(
                child: ListTile(
                  leading: UserAvatar(
                    name: _appointment!.patientName,
                    photoUrl: _appointment!.patientPhotoUrl,
                    patientId: _appointment!.patientId,
                  ),
                  title: Text(_appointment!.patientName ?? ''),
                  subtitle: Text('${_appointment!.date} - ${TimeFormat.format24To12(_appointment!.timeSlot)}'),
                  trailing: _appointment!.queueNumber != null
                      ? Chip(label: Text('#${_appointment!.queueNumber}'))
                      : null,
                ),
              )
            else if (_standalonePatient != null)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(
                    '${_standalonePatient!['first_name'] ?? ''} ${_standalonePatient!['last_name'] ?? ''}'.trim(),
                  ),
                  subtitle: Text(AppLocalizations.tr('add_record')),
                ),
              ),
            if (_hasSavedRecord && !_isEditOnly)
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    AppLocalizations.tr('consultation_saved_edit_hint'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            if (_isEditOnly)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    AppLocalizations.tr('consultation_edit_hint'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            if (_isEditOnly) const SizedBox(height: 12),
            if (_appointment?.patientId != null || _standalonePatient != null) ...[
              const SizedBox(height: 12),
              if (!_isEditOnly && !_isStandalone && !_canMarkCompleted)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      AppLocalizations.tr('complete_requires_save_first'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              if (!_isEditOnly && !_isStandalone && !_canMarkCompleted) const SizedBox(height: 12),
              Row(
                children: [
                  if (_appointment?.patientId != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openPatientSensors,
                        icon: const Icon(Icons.sensors),
                        label: Text(AppLocalizations.tr('connect_sensors')),
                      ),
                    ),
                  if (_appointment?.patientId != null && !_isEditOnly && !_isStandalone) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading || !_canMarkCompleted ? null : _markCompletedOnly,
                        icon: const Icon(Icons.done_all),
                        label: Text(AppLocalizations.tr('mark_completed')),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(AppLocalizations.tr('consultation_transcript'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            CustomTextField(
              controller: _transcriptController,
              hint: AppLocalizations.tr('consultation_transcript_hint'),
              maxLines: 8,
              suffix: VoiceMicSuffix(controller: _transcriptController),
            ),
            if (!_isEditOnly && !_hasSavedRecord) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _extractFromTranscript,
                icon: const Icon(Icons.auto_fix_high),
                label: Text(AppLocalizations.tr('extract_soap')),
              ),
            ],
            if (_isLoading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (!_hasExtracted && !_recordLoaded && !_isEditOnly && !_soapEditable) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _soapEditable = true;
                  _structuredData ??= {};
                }),
                icon: const Icon(Icons.edit_note),
                label: Text(AppLocalizations.tr('manual_entry')),
              ),
            ],
            if (_hasExtracted || _soapEditable || _recordLoaded || _isEditOnly) ...[
              const SizedBox(height: 16),
              KeyedSubtree(
                key: _soapSectionKey,
                child: TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: AppLocalizations.tr('ai_extraction')),
                  Tab(text: AppLocalizations.tr('ai_review')),
                ],
              ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: tabHeight,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    SingleChildScrollView(
                      child: StructuredSoapView(
                        key: ValueKey('soap_view_$_soapViewGeneration'),
                        structured: _structuredData,
                        prescription: _prescription,
                        currentMedications: _currentMedications,
                        symptomsList: _symptomsList,
                        editable: true,
                        onChanged: _onStructuredChanged,
                        subjectiveController: _soapSController,
                        objectiveController: _soapOController,
                        assessmentController: _soapAController,
                        planController: _soapPController,
                        followUpController: _followUpController,
                      ),
                    ),
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.tr('review_prompt_label'), style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          CustomTextField(
                            controller: _reviewPromptController,
                            hint: AppLocalizations.tr('review_prompt_hint'),
                            maxLines: 3,
                            suffix: VoiceMicSuffix(controller: _reviewPromptController),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isLoading ? null : _runAiReview,
                              icon: const Icon(Icons.psychology_outlined),
                              label: Text(AppLocalizations.tr('ask_ai_review')),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_showReviewPanel)
                            AiReviewPanel(
                              answer: _reviewAnswer,
                              message: _reviewMessage,
                              suggestions: _reviewSuggestions,
                              ignoredIndexes: _ignoredReviewIndexes,
                              onAdd: _applyReviewSuggestion,
                              onIgnore: (i) => setState(() => _ignoredReviewIndexes.add(i)),
                              onClose: () => setState(() => _showReviewPanel = false),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasExtracted && !_isEditOnly)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _rejectNotes,
                      icon: const Icon(Icons.close),
                      label: Text(AppLocalizations.tr('reject_clear')),
                    ),
                  ),
                if (_hasExtracted && !_isEditOnly) const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _confirmAndSave,
                    icon: const Icon(Icons.check_circle),
                    label: Text(
                      _isEditOnly
                          ? AppLocalizations.tr('save_changes')
                          : (_hasSavedRecord
                              ? AppLocalizations.tr('save_changes')
                              : AppLocalizations.tr('confirm_save_history')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
