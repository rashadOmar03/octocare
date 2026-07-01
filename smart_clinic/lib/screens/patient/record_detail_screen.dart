import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../models/medical_record.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/structured_soap_view.dart';

class RecordDetailScreen extends StatelessWidget {
  const RecordDetailScreen({super.key});

  Color _severityColor(String? severity) {
    switch (severity) {
      case 'severe':
        return const Color(0xFFD32F2F);
      case 'moderate':
        return const Color(0xFFF57C00);
      default:
        return const Color(0xFF388E3C);
    }
  }

  List<dynamic> _prescriptionItems(MedicalRecord record) {
    if (record.prescriptions == null) return [];
    final items = <dynamic>[];
    for (final p in record.prescriptions!) {
      if (p is Map && p['items'] is List) {
        items.addAll(p['items'] as List);
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final record = ModalRoute.of(context)?.settings.arguments as MedicalRecord?;
    if (record == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(AppLocalizations.tr('error'))),
      );
    }

    final hasStructured = record.structuredData != null && record.structuredData!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.tr('medical_records')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                            record.chiefComplaint ?? record.diagnosis ?? '',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        RoleBadge(
                          label: AppLocalizations.tr(record.severity ?? 'mild'),
                          color: _severityColor(record.severity),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${record.doctorName ?? ''} - ${record.visitDate ?? record.createdAt ?? ''}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (hasStructured)
              StructuredSoapView(
                structured: record.structuredData,
                prescription: _prescriptionItems(record),
              )
            else ...[
              _buildSection(context, AppLocalizations.tr('chief_complaint'), record.chiefComplaint),
              _buildSection(context, AppLocalizations.tr('symptoms'), record.symptoms),
              _buildSection(context, AppLocalizations.tr('diagnosis'), record.diagnosis),
              _buildSection(context, AppLocalizations.tr('treatment_plan'), record.treatmentPlan),
              _buildSection(context, AppLocalizations.tr('notes'), record.notes),
              if (record.soapSubjective != null || record.soapObjective != null || record.soapAssessment != null || record.soapPlan != null)
                _buildLegacySoapSection(context, record),
            ],
            if (!hasStructured && record.prescriptions != null && record.prescriptions!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(AppLocalizations.tr('prescriptions'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...record.prescriptions!.map((p) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.medication),
                      title: Text('${AppLocalizations.tr('prescriptions')} #${p['id'] ?? ''}'),
                      subtitle: Text(p['status'] ?? ''),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, String? content) {
    if (content == null || content.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 8),
              Text(content, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegacySoapSection(BuildContext context, MedicalRecord record) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ExpansionTile(
        title: Text(AppLocalizations.tr('soap_notes')),
        initiallyExpanded: false,
        children: [
          if (record.soapSubjective != null)
            _buildSoapItem(context, AppLocalizations.tr('soap_subjective'), record.soapSubjective!),
          if (record.soapObjective != null)
            _buildSoapItem(context, AppLocalizations.tr('soap_objective'), record.soapObjective!),
          if (record.soapAssessment != null)
            _buildSoapItem(context, AppLocalizations.tr('soap_assessment'), record.soapAssessment!),
          if (record.soapPlan != null)
            _buildSoapItem(context, AppLocalizations.tr('soap_plan'), record.soapPlan!),
        ],
      ),
    );
  }

  Widget _buildSoapItem(BuildContext context, String title, String content) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(content),
          const Divider(),
        ],
      ),
    );
  }
}
