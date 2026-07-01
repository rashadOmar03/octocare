import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../models/prescription.dart';
import '../../services/medical_service.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/role_badge.dart';

class PrescriptionDetailScreen extends StatefulWidget {
  const PrescriptionDetailScreen({super.key});

  @override
  State<PrescriptionDetailScreen> createState() => _PrescriptionDetailScreenState();
}

class _PrescriptionDetailScreenState extends State<PrescriptionDetailScreen> {
  final MedicalService _service = MedicalService();
  Prescription? _prescription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is Prescription) {
      if (arg.items != null && arg.items!.isNotEmpty) {
        setState(() {
          _prescription = arg;
          _isLoading = false;
        });
        return;
      }
      if (arg.id != null) {
        try {
          final detail = await _service.getPrescriptionDetail(arg.id!);
          setState(() {
            _prescription = detail;
            _isLoading = false;
          });
          return;
        } catch (_) {}
      }
      setState(() {
        _prescription = arg;
        _isLoading = false;
      });
    } else if (arg is Map) {
      final id = arg['id']?.toString();
      if (id != null) {
        try {
          final detail = await _service.getPrescriptionDetail(id);
          setState(() {
            _prescription = detail;
            _isLoading = false;
          });
          return;
        } catch (_) {}
      }
      setState(() => _isLoading = false);
    } else if (arg is String) {
      try {
        final detail = await _service.getPrescriptionDetail(arg);
        setState(() {
          _prescription = detail;
          _isLoading = false;
        });
        return;
      } catch (_) {}
      setState(() => _isLoading = false);
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.tr('prescriptions'))),
        body: const LoadingWidget(),
      );
    }

    final prescription = _prescription;
    if (prescription == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(AppLocalizations.tr('error'))),
      );
    }

    String? formatDueDate(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      return raw.replaceFirst('T', ' ').split('.').first;
    }

    bool showMedValue(String? value) {
      if (value == null) return false;
      final trimmed = value.trim();
      return trimmed.isNotEmpty && trimmed != '—' && trimmed != '-';
    }

    final dueDate = formatDueDate(prescription.activeUntil);

    return Scaffold(
      appBar: AppBar(
        title: Text('${AppLocalizations.tr('prescriptions')} #${prescription.id ?? ''}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${AppLocalizations.tr('prescriptions')} #${prescription.id ?? ''}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      RoleBadge(
                        label: AppLocalizations.tr(prescription.status ?? 'active'),
                        color: const Color(0xFF388E3C),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (prescription.doctorName != null)
                    Text('${AppLocalizations.tr('doctor')}: ${prescription.doctorName}'),
                  if (prescription.createdAt != null)
                    Text('${AppLocalizations.tr('date')}: ${prescription.createdAt}'),
                  if (dueDate != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${AppLocalizations.tr('prescription_due_date')}: $dueDate',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (prescription.notes != null && prescription.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(context, AppLocalizations.tr('notes'), prescription.notes!),
          ],
          const SizedBox(height: 16),
          Text(AppLocalizations.tr('medications'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (prescription.items == null || prescription.items!.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(AppLocalizations.tr('no_data')),
              ),
            )
          else
            ...prescription.items!.map((item) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.medication),
                    title: Text(item.medicationName ?? AppLocalizations.tr('medication_name')),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showMedValue(item.dosage))
                          Text('${AppLocalizations.tr('dosage')}: ${item.dosage}'),
                        if (showMedValue(item.frequency))
                          Text('${AppLocalizations.tr('frequency')}: ${item.frequency}'),
                        if (showMedValue(item.duration))
                          Text('${AppLocalizations.tr('duration')}: ${item.duration}'),
                        if (item.notes != null && item.notes!.isNotEmpty)
                          Text(item.notes!),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String content) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            Text(content),
          ],
        ),
      ),
    );
  }
}
