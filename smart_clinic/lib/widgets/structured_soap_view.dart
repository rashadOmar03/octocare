import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import 'voice_mic_button.dart';

typedef StructuredDataChanged = void Function({
  Map<String, dynamic>? structured,
  List<dynamic>? prescription,
  List<dynamic>? currentMedications,
  List<dynamic>? symptomsList,
  DateTime? prescriptionActiveUntil,
});

class StructuredSoapView extends StatefulWidget {
  final Map<String, dynamic>? structured;
  final List<dynamic>? prescription;
  final List<dynamic>? currentMedications;
  final List<dynamic>? symptomsList;
  final bool editable;
  final TextEditingController? subjectiveController;
  final TextEditingController? objectiveController;
  final TextEditingController? assessmentController;
  final TextEditingController? planController;
  final TextEditingController? followUpController;
  final StructuredDataChanged? onChanged;

  const StructuredSoapView({
    super.key,
    this.structured,
    this.prescription,
    this.currentMedications,
    this.symptomsList,
    this.editable = false,
    this.subjectiveController,
    this.objectiveController,
    this.assessmentController,
    this.planController,
    this.followUpController,
    this.onChanged,
  });

  @override
  State<StructuredSoapView> createState() => _StructuredSoapViewState();
}

class _StructuredSoapViewState extends State<StructuredSoapView> {
  late Map<String, dynamic> _structured;
  late List<Map<String, dynamic>> _prescription;
  late List<Map<String, dynamic>> _currentMedications;
  late List<Map<String, dynamic>> _symptoms;
  late List<Map<String, dynamic>> _diagnoses;
  late List<Map<String, dynamic>> _planItems;
  late List<Map<String, dynamic>> _allergies;
  late List<Map<String, dynamic>> _pmhItems;
  late List<Map<String, dynamic>> _chronicItems;
  late List<Map<String, dynamic>> _existingConditionItems;
  DateTime? _prescriptionActiveUntil;

  @override
  void initState() {
    super.initState();
    _hydrateFromProps();
  }

  @override
  void didUpdateWidget(StructuredSoapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.structured != widget.structured ||
        oldWidget.prescription != widget.prescription ||
        oldWidget.currentMedications != widget.currentMedications ||
        oldWidget.symptomsList != widget.symptomsList) {
      _hydrateFromProps();
    }
  }

  Map<String, dynamic> get _soap {
    final soap = _structured['soap_note'];
    if (soap is Map<String, dynamic>) return soap;
    if (soap is Map) return Map<String, dynamic>.from(soap);
    return {};
  }

  Map<String, dynamic> get _objective {
    final obj = _soap['objective'];
    if (obj is Map<String, dynamic>) return obj;
    if (obj is Map) return Map<String, dynamic>.from(obj);
    return {};
  }

  void _hydrateFromProps() {
    _structured = widget.structured != null
        ? Map<String, dynamic>.from(widget.structured!)
        : <String, dynamic>{'soap_note': <String, dynamic>{}};

    _prescription = _normalizePrescription(widget.prescription ?? _structured['prescription']);
    _currentMedications = _normalizePrescription(
      widget.currentMedications ?? _structured['medications_current'],
      defaultAction: 'UNKNOWN',
    );
    _symptoms = _normalizeSymptoms(widget.symptomsList ?? _structured['symptoms']);

    final soap = _soap;
    final assessment = _asStrings(soap['assessment']);
    final diagRaw = _structured['diagnoses'];
    final diagStrings = diagRaw is List
        ? diagRaw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList()
        : assessment;
    _diagnoses = diagStrings.map((d) => {'name': d, 'active': true}).toList();

    final plan = _asStrings(soap['plan']);
    _planItems = plan.map((p) => {'text': p, 'active': true}).toList();

    final mh = _medicalHistory;
    _allergies = _asStrings(mh['allergies']).map((e) => {'name': e, 'active': true}).toList();
    _pmhItems = _asStrings(mh['past_medical_history']).map((e) => {'name': e, 'active': true}).toList();
    _chronicItems = _asStrings(mh['chronic_diseases']).map((e) => {'name': e, 'active': true}).toList();
    _existingConditionItems = _asStrings(mh['existing_conditions']).map((e) => {'name': e, 'active': true}).toList();

    final rawUntil = _structured['prescription_active_until'];
    if (rawUntil != null && rawUntil.toString().trim().isNotEmpty) {
      _prescriptionActiveUntil = DateTime.tryParse(rawUntil.toString());
    } else {
      _prescriptionActiveUntil = null;
    }
  }

  bool _isPlaceholderMedValue(String? value) {
    if (value == null) return true;
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == '—' || trimmed == '-';
  }

  String _formatDueDate(DateTime value) {
    final local = value.toLocal();
    final date = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$date $hour:$minute';
  }

  Future<DateTime?> _pickDueDateTime({DateTime? initial}) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return null;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initial != null
          ? TimeOfDay.fromDateTime(initial)
          : TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  List<Map<String, dynamic>> _normalizePrescription(dynamic raw, {String defaultAction = 'Start'}) {
    final list = raw is List ? raw : <dynamic>[];
    return list.map((m) {
      if (m is Map) {
        return {
          'name': (m['name'] ?? m['medication_name'] ?? '').toString(),
          'action': (m['action'] ?? defaultAction).toString(),
          'dosage': (m['dosage'] ?? '').toString(),
          'frequency': (m['frequency'] ?? '').toString(),
          'route': (m['route'] ?? '').toString(),
          'duration': (m['duration'] ?? '').toString(),
          'notes': (m['notes'] ?? '').toString(),
          'active': m['active'] != false,
        };
      }
      return {
        'name': m.toString(),
        'action': defaultAction,
        'dosage': '',
        'frequency': '',
        'route': '',
        'duration': '',
        'notes': '',
        'active': true,
      };
    }).where((m) => (m['name'] as String).trim().isNotEmpty).toList();
  }

  List<Map<String, dynamic>> _normalizeSymptoms(dynamic raw) {
    final list = raw is List ? raw : <dynamic>[];
    return list.map((s) {
      if (s is Map) {
        return {
          'name': (s['name'] ?? '').toString(),
          'duration': s['duration'],
          'severity': s['severity'],
          'location': s['location'],
          'active': s['active'] != false,
        };
      }
      return {'name': s.toString(), 'duration': null, 'severity': null, 'location': null, 'active': true};
    }).where((s) => (s['name'] as String).trim().isNotEmpty).toList();
  }

  List<String> _asStrings(dynamic value) {
    if (value == null) return [];
    if (value is String) return value.trim().isEmpty ? [] : [value.trim()];
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    return [value.toString()];
  }

  void _notifyParent() {
    final soap = Map<String, dynamic>.from(_soap);
    final activeDiagnoses = _diagnoses.where((d) => d['active'] != false).map((d) => d['name'].toString()).toList();
    final activePlan = _planItems.where((p) => p['active'] != false).map((p) => p['text'].toString()).toList();
    soap['assessment'] = activeDiagnoses;
    soap['plan'] = activePlan;
    _structured['soap_note'] = soap;
    _structured['diagnoses'] = activeDiagnoses;
    _structured['prescription'] = _prescription;
    _structured['medications_current'] = _currentMedications;
    _structured['symptoms'] = _symptoms;
    if (_prescriptionActiveUntil != null) {
      _structured['prescription_active_until'] = _prescriptionActiveUntil!.toUtc().toIso8601String();
    } else {
      _structured.remove('prescription_active_until');
    }

    final mh = Map<String, dynamic>.from(_medicalHistory);
    mh['allergies'] = _allergies.where((e) => e['active'] != false).map((e) => e['name'].toString()).toList();
    mh['past_medical_history'] = _pmhItems.where((e) => e['active'] != false).map((e) => e['name'].toString()).toList();
    mh['chronic_diseases'] = _chronicItems.where((e) => e['active'] != false).map((e) => e['name'].toString()).toList();
    mh['existing_conditions'] = _existingConditionItems.where((e) => e['active'] != false).map((e) => e['name'].toString()).toList();
    _structured['medical_history'] = mh;

    if (widget.followUpController != null) {
      final lines = widget.followUpController!.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      _structured['follow_up_items'] = lines;
      _structured['follow_up'] = lines.isNotEmpty ? lines.join('; ') : null;
    }

    widget.assessmentController?.text = activeDiagnoses.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n');
    widget.planController?.text = activePlan.map((p) => '• $p').join('\n');

    widget.onChanged?.call(
      structured: _structured,
      prescription: _prescription,
      currentMedications: _currentMedications,
      symptomsList: _symptoms,
      prescriptionActiveUntil: _prescriptionActiveUntil,
    );
    setState(() {});
  }

  InputDecoration _voiceInputDecoration(TextEditingController controller) {
    return InputDecoration(
      border: const OutlineInputBorder(),
      suffixIcon: VoiceMicSuffix(controller: controller, onTranscribed: _notifyParent),
    );
  }

  Future<String?> _promptText(String title, {String initial = '', int maxLines = 2}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: maxLines,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: widget.editable ? VoiceMicSuffix(controller: controller) : null,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(AppLocalizations.tr('save'))),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<Map<String, dynamic>?> _promptMedication({Map<String, dynamic>? initial, bool showDueDate = false}) async {
    final name = TextEditingController(text: initial?['name']?.toString() ?? '');
    final dose = TextEditingController(text: _isPlaceholderMedValue(initial?['dosage']?.toString()) ? '' : initial?['dosage']?.toString() ?? '');
    final freq = TextEditingController(text: _isPlaceholderMedValue(initial?['frequency']?.toString()) ? '' : initial?['frequency']?.toString() ?? '');
    final route = TextEditingController(text: initial?['route']?.toString() ?? '');
    final duration = TextEditingController(text: _isPlaceholderMedValue(initial?['duration']?.toString()) ? '' : initial?['duration']?.toString() ?? '');
    final notes = TextEditingController(text: initial?['notes']?.toString() ?? '');
    var applyDueDateToAll = false;
    DateTime? medDueDate = _prescriptionActiveUntil;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(initial == null ? AppLocalizations.tr('add_medication') : AppLocalizations.tr('edit')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.tr('medication'),
                    suffixIcon: VoiceMicSuffix(controller: name),
                  ),
                ),
                TextField(
                  controller: dose,
                  decoration: InputDecoration(
                    labelText: '${AppLocalizations.tr('dose')} (${AppLocalizations.tr('optional_field')})',
                  ),
                ),
                TextField(
                  controller: freq,
                  decoration: InputDecoration(
                    labelText: '${AppLocalizations.tr('frequency')} (${AppLocalizations.tr('optional_field')})',
                  ),
                ),
                TextField(
                  controller: route,
                  decoration: InputDecoration(
                    labelText: '${AppLocalizations.tr('route')} (${AppLocalizations.tr('optional_field')})',
                  ),
                ),
                TextField(
                  controller: duration,
                  decoration: InputDecoration(
                    labelText: '${AppLocalizations.tr('duration')} (${AppLocalizations.tr('optional_field')})',
                  ),
                ),
                TextField(controller: notes, decoration: InputDecoration(labelText: AppLocalizations.tr('instructions')), maxLines: 2),
                if (showDueDate) ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppLocalizations.tr('prescription_due_date')),
                    subtitle: Text(
                      medDueDate != null
                          ? _formatDueDate(medDueDate!)
                          : AppLocalizations.tr('prescription_due_date_hint'),
                    ),
                    trailing: const Icon(Icons.event),
                    onTap: () async {
                      final picked = await _pickDueDateTime(initial: medDueDate);
                      if (picked != null) setLocal(() => medDueDate = picked);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(AppLocalizations.tr('apply_due_date_all')),
                    value: applyDueDateToAll,
                    onChanged: medDueDate == null ? null : (v) => setLocal(() => applyDueDateToAll = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.tr('cancel'))),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.tr('save'))),
          ],
        ),
      ),
    );

    Map<String, dynamic>? out;
    if (result == true && name.text.trim().isNotEmpty) {
      out = {
        'name': name.text.trim(),
        'dosage': dose.text.trim(),
        'frequency': freq.text.trim(),
        'route': route.text.trim(),
        'duration': duration.text.trim(),
        'notes': notes.text.trim(),
      };
      if (showDueDate && applyDueDateToAll && medDueDate != null) {
        out['active_until'] = medDueDate!.toUtc().toIso8601String();
        _prescriptionActiveUntil = medDueDate;
      }
    }
    name.dispose();
    dose.dispose();
    freq.dispose();
    route.dispose();
    duration.dispose();
    notes.dispose();
    return out;
  }

  Map<String, dynamic> get _medicalHistory {
    final mh = _structured['medical_history'];
    if (mh is Map<String, dynamic>) return mh;
    if (mh is Map) return Map<String, dynamic>.from(mh);
    return {};
  }

  List<String> get _clinicalFindings => _asStrings(_structured['clinical_findings']);

  String get _clinicalSummary => (_structured['clinical_summary'] ?? '').toString().trim();

  List<String> get _followUpItems {
    final items = _structured['follow_up_items'];
    if (items is List) return _asStrings(items);
    final fu = _structured['follow_up'];
    if (fu is String && fu.trim().isNotEmpty) return [fu.trim()];
    return [];
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.2,
          ),
    );
  }

  Widget _card(BuildContext context, String title, Widget child, {Widget? trailing}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _sectionTitle(context, title)),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _bulletList(BuildContext context, List<String> items, {List<bool>? inactive}) {
    if (items.isEmpty) return Text('—', style: Theme.of(context).textTheme.bodyMedium);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• ${items[i]}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    decoration: inactive != null && i < inactive.length && inactive[i] ? TextDecoration.lineThrough : null,
                    color: inactive != null && i < inactive.length && inactive[i] ? Colors.grey : null,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _numberedList(BuildContext context, List<String> items, {List<bool>? inactive}) {
    if (items.isEmpty) return Text('—', style: Theme.of(context).textTheme.bodyMedium);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${i + 1}. ${items[i]}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    decoration: inactive != null && i < inactive.length && inactive[i] ? TextDecoration.lineThrough : null,
                    color: inactive != null && i < inactive.length && inactive[i] ? Colors.grey : null,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _editableToggleRow({
    required String label,
    required String subtitle,
    required bool active,
    required VoidCallback onToggle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        title: Text(
          label,
          style: TextStyle(
            decoration: active ? null : TextDecoration.lineThrough,
            color: active ? null : Colors.grey,
          ),
        ),
        subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: active ? AppLocalizations.tr('deactivate') : AppLocalizations.tr('activate'),
              child: Switch(
                value: active,
                onChanged: (_) => onToggle(),
              ),
            ),
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onDelete),
          ],
        ),
      ),
    );
  }

  Widget _clinicalSummarySection(BuildContext context) {
    final summary = _clinicalSummary;
    if (summary.isEmpty) return const SizedBox.shrink();
    return _card(
      context,
      AppLocalizations.tr('clinical_summary'),
      Text(
        summary,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
      ),
    );
  }

  Widget _clinicalFindingsSection(BuildContext context) {
    final findings = _clinicalFindings;
    if (findings.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, AppLocalizations.tr('clinical_findings')),
            const SizedBox(height: 10),
            ...findings.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCategory(BuildContext context, String title, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _bulletList(context, items),
        ],
      ),
    );
  }

  Widget _editableStringItems(
    BuildContext context, {
    required String title,
    required List<Map<String, dynamic>> items,
    required String addLabel,
  }) {
    if (items.isEmpty && !widget.editable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (!widget.editable)
            _bulletList(context, items.map((e) => e['name'].toString()).toList())
          else ...[
            for (var i = 0; i < items.length; i++)
              _editableToggleRow(
                label: items[i]['name'].toString(),
                subtitle: '',
                active: items[i]['active'] != false,
                onToggle: () {
                  items[i]['active'] = items[i]['active'] == false;
                  _notifyParent();
                },
                onEdit: () async {
                  final value = await _promptText(title, initial: items[i]['name'].toString());
                  if (value != null && value.isNotEmpty) {
                    items[i]['name'] = value;
                    _notifyParent();
                  }
                },
                onDelete: () {
                  items.removeAt(i);
                  _notifyParent();
                },
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final value = await _promptText(addLabel);
                  if (value != null && value.isNotEmpty) {
                    items.add({'name': value, 'active': true});
                    _notifyParent();
                  }
                },
                icon: const Icon(Icons.add),
                label: Text(addLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _medicalHistorySection(BuildContext context) {
    final mh = _medicalHistory;
    final fhx = _asStrings(mh['family_history']);
    final social = _asStrings(mh['social_history']);
    final surgeries = _asStrings(mh['previous_surgeries']);
    final smoking = mh['smoking']?.toString().trim() ?? '';
    final alcohol = mh['alcohol']?.toString().trim() ?? '';
    final hasEditable = widget.editable &&
        (_allergies.isNotEmpty ||
            _pmhItems.isNotEmpty ||
            _chronicItems.isNotEmpty ||
            _existingConditionItems.isNotEmpty ||
            true);
    final hasContent = _allergies.isNotEmpty ||
        _pmhItems.isNotEmpty ||
        _chronicItems.isNotEmpty ||
        _existingConditionItems.isNotEmpty ||
        fhx.isNotEmpty ||
        social.isNotEmpty ||
        surgeries.isNotEmpty ||
        smoking.isNotEmpty ||
        alcohol.isNotEmpty;
    if (!hasContent && !hasEditable) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          AppLocalizations.tr('medical_history'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        initiallyExpanded: widget.editable,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _editableStringItems(
                  context,
                  title: AppLocalizations.tr('allergies'),
                  items: _allergies,
                  addLabel: AppLocalizations.tr('add_allergy'),
                ),
                _editableStringItems(
                  context,
                  title: AppLocalizations.tr('chronic_diseases'),
                  items: _chronicItems,
                  addLabel: AppLocalizations.tr('add_chronic_disease'),
                ),
                _editableStringItems(
                  context,
                  title: AppLocalizations.tr('existing_conditions'),
                  items: _existingConditionItems,
                  addLabel: AppLocalizations.tr('add_existing_condition'),
                ),
                _editableStringItems(
                  context,
                  title: AppLocalizations.tr('past_medical_history'),
                  items: _pmhItems,
                  addLabel: AppLocalizations.tr('add_pmh_item'),
                ),
                _historyCategory(context, AppLocalizations.tr('family_history'), fhx),
                _historyCategory(context, AppLocalizations.tr('social_history'), social),
                if (smoking.isNotEmpty)
                  _historyCategory(context, AppLocalizations.tr('smoking_status'), [smoking]),
                if (alcohol.isNotEmpty)
                  _historyCategory(context, AppLocalizations.tr('alcohol_use'), [alcohol]),
                _historyCategory(context, AppLocalizations.tr('previous_surgeries'), surgeries),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _followUpSection(BuildContext context) {
    final items = _followUpItems;
    final controllerText = widget.followUpController?.text.trim() ?? '';
    if (items.isEmpty && controllerText.isEmpty && !widget.editable) return const SizedBox.shrink();

    if (widget.editable && widget.followUpController != null) {
      return _card(
        context,
        AppLocalizations.tr('follow_up'),
        TextField(
          controller: widget.followUpController,
          maxLines: 4,
          decoration: _voiceInputDecoration(widget.followUpController!),
          onChanged: (_) => _notifyParent(),
        ),
      );
    }

    final display = items.isNotEmpty ? items : (controllerText.isNotEmpty ? [controllerText] : <String>[]);
    if (display.isEmpty) return const SizedBox.shrink();
    return _card(context, AppLocalizations.tr('follow_up'), _bulletList(context, display));
  }

  Widget _symptomsSection(BuildContext context) {
    if (_symptoms.isEmpty && !widget.editable) return const SizedBox.shrink();

    if (!widget.editable) {
      final names = _symptoms.map((s) => s['name'].toString()).toList();
      final inactive = _symptoms.map((s) => s['active'] == false).toList();
      return _card(context, AppLocalizations.tr('symptoms'), _bulletList(context, names, inactive: inactive));
    }

    return _card(
      context,
      AppLocalizations.tr('symptoms'),
      Column(
        children: [
          for (var i = 0; i < _symptoms.length; i++)
            _editableToggleRow(
              label: _symptoms[i]['name'].toString(),
              subtitle: [
                if (_symptoms[i]['severity'] != null) _symptoms[i]['severity'].toString(),
                if (_symptoms[i]['duration'] != null) _symptoms[i]['duration'].toString(),
              ].where((s) => s.isNotEmpty).join(' · '),
              active: _symptoms[i]['active'] != false,
              onToggle: () {
                _symptoms[i]['active'] = _symptoms[i]['active'] == false;
                _notifyParent();
              },
              onEdit: () async {
                final value = await _promptText(AppLocalizations.tr('symptoms'), initial: _symptoms[i]['name'].toString());
                if (value != null && value.isNotEmpty) {
                  _symptoms[i]['name'] = value;
                  _notifyParent();
                }
              },
              onDelete: () {
                _symptoms.removeAt(i);
                _notifyParent();
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final value = await _promptText(AppLocalizations.tr('add_symptom'));
                if (value != null && value.isNotEmpty) {
                  _symptoms.add({'name': value, 'duration': null, 'severity': null, 'location': null, 'active': true});
                  _notifyParent();
                }
              },
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.tr('add_symptom')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diagnosesSection(BuildContext context) {
    if (_diagnoses.isEmpty && !widget.editable) return const SizedBox.shrink();

    if (!widget.editable) {
      final names = _diagnoses.map((d) => d['name'].toString()).toList();
      final inactive = _diagnoses.map((d) => d['active'] == false).toList();
      return _card(context, AppLocalizations.tr('diagnosis'), _numberedList(context, names, inactive: inactive));
    }

    return _card(
      context,
      AppLocalizations.tr('diagnosis'),
      Column(
        children: [
          for (var i = 0; i < _diagnoses.length; i++)
            _editableToggleRow(
              label: '${i + 1}. ${_diagnoses[i]['name']}',
              subtitle: '',
              active: _diagnoses[i]['active'] != false,
              onToggle: () {
                _diagnoses[i]['active'] = _diagnoses[i]['active'] == false;
                _notifyParent();
              },
              onEdit: () async {
                final value = await _promptText(AppLocalizations.tr('diagnosis'), initial: _diagnoses[i]['name'].toString());
                if (value != null && value.isNotEmpty) {
                  _diagnoses[i]['name'] = value;
                  _notifyParent();
                }
              },
              onDelete: () {
                _diagnoses.removeAt(i);
                _notifyParent();
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final value = await _promptText(AppLocalizations.tr('add_diagnosis'));
                if (value != null && value.isNotEmpty) {
                  _diagnoses.add({'name': value, 'active': true});
                  _notifyParent();
                }
              },
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.tr('add_diagnosis')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planSection(BuildContext context) {
    if (_planItems.isEmpty && !widget.editable && widget.planController?.text.trim().isEmpty != false) {
      return const SizedBox.shrink();
    }

    if (!widget.editable) {
      final items = _planItems.map((p) => p['text'].toString()).toList();
      final inactive = _planItems.map((p) => p['active'] == false).toList();
      if (items.isEmpty) {
        return _card(
          context,
          AppLocalizations.tr('soap_plan'),
          Text(widget.planController?.text.trim().isNotEmpty == true ? widget.planController!.text : '—'),
        );
      }
      return _card(context, AppLocalizations.tr('soap_plan'), _bulletList(context, items, inactive: inactive));
    }

    return _card(
      context,
      AppLocalizations.tr('soap_plan'),
      Column(
        children: [
          for (var i = 0; i < _planItems.length; i++)
            _editableToggleRow(
              label: _planItems[i]['text'].toString(),
              subtitle: '',
              active: _planItems[i]['active'] != false,
              onToggle: () {
                _planItems[i]['active'] = _planItems[i]['active'] == false;
                _notifyParent();
              },
              onEdit: () async {
                final value = await _promptText(AppLocalizations.tr('soap_plan'), initial: _planItems[i]['text'].toString(), maxLines: 3);
                if (value != null && value.isNotEmpty) {
                  _planItems[i]['text'] = value;
                  _notifyParent();
                }
              },
              onDelete: () {
                _planItems.removeAt(i);
                _notifyParent();
              },
            ),
          if (widget.planController != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: widget.planController,
                maxLines: 3,
                decoration: _voiceInputDecoration(widget.planController!).copyWith(
                  labelText: AppLocalizations.tr('treatment_plan'),
                ),
                onChanged: (_) => _notifyParent(),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final value = await _promptText(AppLocalizations.tr('add_plan_item'), maxLines: 3);
                if (value != null && value.isNotEmpty) {
                  _planItems.add({'text': value, 'active': true});
                  _notifyParent();
                }
              },
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.tr('add_plan_item')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _objectiveSection(BuildContext context) {
    if (widget.editable && widget.objectiveController != null) {
      return TextField(
        controller: widget.objectiveController,
        maxLines: 5,
        decoration: _voiceInputDecoration(widget.objectiveController!),
        onChanged: (_) => _notifyParent(),
      );
    }

    final sections = <MapEntry<String, String>>[
      MapEntry('vitals', AppLocalizations.tr('vitals')),
      MapEntry('physical_exam', AppLocalizations.tr('physical_examination')),
      MapEntry('ecg', AppLocalizations.tr('ecg')),
      MapEntry('laboratory_results', AppLocalizations.tr('labs')),
      MapEntry('imaging', AppLocalizations.tr('imaging')),
      MapEntry('echo', AppLocalizations.tr('echo')),
    ];

    final cards = <Widget>[];
    for (final section in sections) {
      final items = _asStrings(_objective[section.key]);
      if (items.isEmpty) continue;
      cards.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 6),
              _bulletList(context, items),
              if (section.key != 'echo') const Divider(height: 20),
            ],
          ),
        ),
      );
    }

    if (cards.isEmpty) {
      final vitalsSource = (_structured['vitals_source'] ?? 'sensor').toString();
      if (vitalsSource == 'sensor') {
        return Text(
          AppLocalizations.tr('sensor_off_patient'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
        );
      }
      return Text(widget.objectiveController?.text.trim().isNotEmpty == true ? widget.objectiveController!.text : '—');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: cards);
  }

  Widget _medicationEditableList(
    List<Map<String, dynamic>> list, {
    String defaultAction = 'Start',
    required VoidCallback onChanged,
    bool showDueDate = false,
  }) {
    return Column(
      children: [
        for (var i = 0; i < list.length; i++)
          _editableToggleRow(
            label: list[i]['name'].toString(),
            subtitle: [
              if ((list[i]['action'] ?? '').toString().isNotEmpty) list[i]['action'],
              if (!_isPlaceholderMedValue(list[i]['dosage']?.toString())) list[i]['dosage'],
              if (!_isPlaceholderMedValue(list[i]['frequency']?.toString())) list[i]['frequency'],
              if (!_isPlaceholderMedValue(list[i]['route']?.toString())) list[i]['route'],
              if (!_isPlaceholderMedValue(list[i]['duration']?.toString())) list[i]['duration'],
              if ((list[i]['notes'] ?? '').toString().trim().isNotEmpty) list[i]['notes'],
            ].where((s) => s.toString().trim().isNotEmpty).join(' · '),
            active: list[i]['active'] != false,
            onToggle: () {
              list[i]['active'] = list[i]['active'] == false;
              onChanged();
            },
            onEdit: () async {
              final updated = await _promptMedication(initial: list[i], showDueDate: showDueDate);
              if (updated != null) {
                list[i] = {...list[i], ...updated, 'active': list[i]['active'] ?? true};
                onChanged();
              }
            },
            onDelete: () {
              list.removeAt(i);
              onChanged();
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final med = await _promptMedication(showDueDate: showDueDate);
              if (med != null) {
                list.add({...med, 'action': defaultAction, 'notes': med['notes'] ?? '', 'active': true});
                onChanged();
              }
            },
            icon: const Icon(Icons.add),
            label: Text(AppLocalizations.tr('add_medication')),
          ),
        ),
      ],
    );
  }

  Widget _medicationReadTable(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return Text('—', style: Theme.of(context).textTheme.bodyMedium);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 44,
        columns: [
          DataColumn(label: Text(AppLocalizations.tr('medication'))),
          DataColumn(label: Text(AppLocalizations.tr('med_action'))),
          DataColumn(label: Text(AppLocalizations.tr('dose'))),
          DataColumn(label: Text(AppLocalizations.tr('frequency'))),
          DataColumn(label: Text(AppLocalizations.tr('route'))),
          DataColumn(label: Text(AppLocalizations.tr('instructions'))),
        ],
        rows: list.map((med) {
          final inactive = med['active'] == false;
          final style = inactive ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey) : null;
          return DataRow(cells: [
            DataCell(Text(med['name']?.toString() ?? '—', style: style)),
            DataCell(Text(med['action']?.toString() ?? '—', style: style)),
            DataCell(Text(_isPlaceholderMedValue(med['dosage']?.toString()) ? '—' : med['dosage'].toString(), style: style)),
            DataCell(Text(_isPlaceholderMedValue(med['frequency']?.toString()) ? '—' : med['frequency'].toString(), style: style)),
            DataCell(Text(med['route']?.toString() ?? '—', style: style)),
            DataCell(Text(med['notes']?.toString() ?? '—', style: style)),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _currentMedicationsSection(BuildContext context) {
    if (_currentMedications.isEmpty && !widget.editable) return const SizedBox.shrink();
    return _card(
      context,
      AppLocalizations.tr('current_medications'),
      widget.editable
          ? _medicationEditableList(_currentMedications, defaultAction: 'UNKNOWN', onChanged: _notifyParent)
          : _medicationReadTable(_currentMedications),
    );
  }

  Widget _newPrescriptionsSection(BuildContext context) {
    if (_prescription.isEmpty && !widget.editable) return const SizedBox.shrink();
    final activeCount = _prescription.where((m) => m['active'] != false).length;
    return _card(
      context,
      AppLocalizations.tr('new_prescriptions'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.editable && activeCount > 0) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                AppLocalizations.tr('prescription_due_date'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _prescriptionActiveUntil != null
                    ? _formatDueDate(_prescriptionActiveUntil!)
                    : AppLocalizations.tr('prescription_due_date_hint'),
              ),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final picked = await _pickDueDateTime(initial: _prescriptionActiveUntil);
                if (picked != null) {
                  setState(() => _prescriptionActiveUntil = picked);
                  _notifyParent();
                }
              },
            ),
            const Divider(),
          ] else if (_prescriptionActiveUntil != null) ...[
            Text(
              '${AppLocalizations.tr('prescription_due_date')}: ${_formatDueDate(_prescriptionActiveUntil!)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
          ],
          widget.editable
              ? _medicationEditableList(
                  _prescription,
                  defaultAction: 'Start',
                  onChanged: _notifyParent,
                  showDueDate: true,
                )
              : _medicationReadTable(_prescription),
        ],
      ),
    );
  }

  Widget _prescriptionSection(BuildContext context) {
    return Column(
      children: [
        _currentMedicationsSection(context),
        _newPrescriptionsSection(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjective = widget.editable && widget.subjectiveController != null
        ? TextField(
            controller: widget.subjectiveController,
            maxLines: 4,
            decoration: _voiceInputDecoration(widget.subjectiveController!),
            onChanged: (_) => _notifyParent(),
          )
        : Text(
            widget.subjectiveController?.text.trim().isNotEmpty == true
                ? widget.subjectiveController!.text
                : (_soap['subjective']?.toString() ?? '—'),
            style: Theme.of(context).textTheme.bodyMedium,
          );

    final assessmentItems = _asStrings(_soap['assessment']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _clinicalSummarySection(context),
        _clinicalFindingsSection(context),
        const SizedBox(height: 4),
        Text(AppLocalizations.tr('soap_notes'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _symptomsSection(context),
        _diagnosesSection(context),
        _card(context, AppLocalizations.tr('soap_subjective'), subjective),
        _medicalHistorySection(context),
        _card(context, AppLocalizations.tr('soap_objective'), _objectiveSection(context)),
        if (!widget.editable)
          _card(
            context,
            AppLocalizations.tr('soap_assessment'),
            widget.assessmentController?.text.trim().isNotEmpty == true
                ? Text(widget.assessmentController!.text, style: Theme.of(context).textTheme.bodyMedium)
                : _numberedList(context, assessmentItems),
          ),
        _planSection(context),
        _followUpSection(context),
        _prescriptionSection(context),
      ],
    );
  }
}
