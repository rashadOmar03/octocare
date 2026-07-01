import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import 'custom_text_field.dart';

class SoapNotesPanel extends StatelessWidget {
  final TextEditingController subjectiveController;
  final TextEditingController objectiveController;
  final TextEditingController assessmentController;
  final TextEditingController planController;
  final bool editable;

  const SoapNotesPanel({
    super.key,
    required this.subjectiveController,
    required this.objectiveController,
    required this.assessmentController,
    required this.planController,
    this.editable = true,
  });

  Widget _section(BuildContext context, String title, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (editable)
          CustomTextField(controller: controller, maxLines: 5)
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              controller.text.trim().isEmpty ? '—' : controller.text.trim(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.tr('soap_notes'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _section(context, AppLocalizations.tr('soap_subjective'), subjectiveController),
            _section(context, AppLocalizations.tr('soap_objective'), objectiveController),
            _section(context, AppLocalizations.tr('soap_assessment'), assessmentController),
            _section(context, AppLocalizations.tr('soap_plan'), planController),
          ],
        ),
      ),
    );
  }
}
