import 'package:flutter/material.dart';
import '../l10n/localization.dart';

class AiReviewPanel extends StatelessWidget {
  final String? answer;
  final String message;
  final List<Map<String, dynamic>> suggestions;
  final Set<int> ignoredIndexes;
  final void Function(int index) onAdd;
  final void Function(int index) onIgnore;
  final VoidCallback? onClose;

  const AiReviewPanel({
    super.key,
    this.answer,
    required this.message,
    required this.suggestions,
    required this.ignoredIndexes,
    required this.onAdd,
    required this.onIgnore,
    this.onClose,
  });

  String _categoryLabel(String category) {
    switch (category) {
      case 'symptoms':
        return AppLocalizations.tr('symptoms');
      case 'diagnoses':
        return AppLocalizations.tr('diagnosis');
      case 'medications_current':
        return AppLocalizations.tr('current_medications');
      case 'prescription':
        return AppLocalizations.tr('new_prescriptions');
      case 'plan':
        return AppLocalizations.tr('soap_plan');
      case 'allergies':
        return AppLocalizations.tr('allergies');
      case 'medical_history':
        return AppLocalizations.tr('past_medical_history');
      case 'family_history':
        return AppLocalizations.tr('family_history');
      case 'social_history':
        return AppLocalizations.tr('social_history');
      case 'previous_surgeries':
        return AppLocalizations.tr('previous_surgeries');
      case 'follow_up':
        return AppLocalizations.tr('follow_up');
      case 'laboratory_results':
        return AppLocalizations.tr('labs');
      case 'imaging':
        return AppLocalizations.tr('imaging');
      case 'ecg':
        return AppLocalizations.tr('ecg');
      case 'echocardiogram':
        return AppLocalizations.tr('echo');
      case 'clinical_findings':
        return AppLocalizations.tr('clinical_findings');
      default:
        return category;
    }
  }

  Color _answerColor(BuildContext context, String? ans) {
    switch (ans) {
      case 'yes':
        return const Color(0xFF388E3C);
      case 'no':
        return Theme.of(context).colorScheme.error;
      default:
        return const Color(0xFFF57C00);
    }
  }

  String _answerLabel(String? ans) {
    switch (ans) {
      case 'yes':
        return AppLocalizations.tr('answer_yes');
      case 'no':
        return AppLocalizations.tr('answer_no');
      default:
        return AppLocalizations.tr('answer_partial');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = <MapEntry<int, Map<String, dynamic>>>[];
    for (var i = 0; i < suggestions.length; i++) {
      if (!ignoredIndexes.contains(i)) visible.add(MapEntry(i, suggestions[i]));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.tr('ai_review_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (onClose != null) IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
              ],
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (answer != null)
                    Container(
                      margin: const EdgeInsets.only(right: 10, top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _answerColor(context, answer).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _answerColor(context, answer)),
                      ),
                      child: Text(
                        _answerLabel(answer),
                        style: TextStyle(color: _answerColor(context, answer), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
                ],
              ),
            ],
            Text(AppLocalizations.tr('ai_review_subtitle'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              Text(
                answer == 'no'
                    ? AppLocalizations.tr('ai_review_confirmed_complete')
                    : AppLocalizations.tr('ai_review_no_suggestions'),
              )
            else
              ...visible.map((entry) {
                final i = entry.key;
                final s = entry.value;
                final confidence = s['confidence'];
                final confText = confidence is num ? '${(confidence * 100).round()}%' : '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Chip(label: Text(_categoryLabel(s['category']?.toString() ?? 'other'))),
                            if (confText.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('${AppLocalizations.tr('confidence')}: $confText',
                                  style: Theme.of(context).textTheme.labelSmall),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(s['suggested_value']?.toString() ?? '', style: Theme.of(context).textTheme.titleSmall),
                        if ((s['explanation'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(s['explanation'].toString(), style: Theme.of(context).textTheme.bodySmall),
                        ],
                        if ((s['source_snippet'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '"${s['source_snippet']}"',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: () => onIgnore(i), child: Text(AppLocalizations.tr('ignore'))),
                            TextButton(
                              onPressed: () => onIgnore(i),
                              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                              child: Text(AppLocalizations.tr('delete')),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(onPressed: () => onAdd(i), child: Text(AppLocalizations.tr('add'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
