import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/api_service.dart';
import '../../models/ai_conversation.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/empty_state.dart';

class DoctorAiQueueScreen extends StatefulWidget {
  const DoctorAiQueueScreen({super.key});

  @override
  State<DoctorAiQueueScreen> createState() => _DoctorAiQueueScreenState();
}

class _DoctorAiQueueScreenState extends State<DoctorAiQueueScreen> {
  List<AISuggestion> _suggestions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.instance.get('/ai/suggestions');
      final List<dynamic> data = response is List ? response : (response['results'] ?? []);
      _suggestions = data.map((e) => AISuggestion.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _approve(String id) async {
    try {
      await ApiService.instance.put('/ai/suggestions/$id/approve', {});
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _reject(String id) async {
    try {
      await ApiService.instance.put('/ai/suggestions/$id/reject', {});
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.tr('success')), backgroundColor: const Color(0xFF388E3C)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showDetail(AISuggestion s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => _SuggestionDetail(
          suggestion: s,
          scrollController: scrollController,
          onApprove: () {
            Navigator.pop(ctx);
            _approve(s.id!);
          },
          onReject: () {
            Navigator.pop(ctx);
            _reject(s.id!);
          },
        ),
      ),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('ai_suggestions'))),
      body: _isLoading
          ? const LoadingWidget()
          : _suggestions.isEmpty
              ? EmptyState(icon: Icons.check_circle, message: AppLocalizations.tr('no_data'))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _suggestions.length,
                    itemBuilder: (ctx, i) {
                      final s = _suggestions[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => _showDetail(s),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      child: Text(
                                        (s.patientName?.isNotEmpty == true) ? s.patientName![0].toUpperCase() : '?',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(s.patientName ?? 'Patient', style: Theme.of(context).textTheme.titleMedium),
                                          Text(s.createdAt ?? '', style: Theme.of(context).textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                    if (s.severity != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _severityColor(s.severity).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          AppLocalizations.tr(s.severity!),
                                          style: TextStyle(color: _severityColor(s.severity), fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                  ],
                                ),
                                if (s.chiefComplaint != null && s.chiefComplaint!.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    s.chiefComplaint!,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                                if (s.diagnosisText.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${AppLocalizations.tr('diagnosis')}: ${s.diagnosisText}',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        AppLocalizations.tr('tap_to_review'),
                                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_ios, size: 14, color: Theme.of(context).colorScheme.primary),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _SuggestionDetail extends StatelessWidget {
  final AISuggestion suggestion;
  final ScrollController scrollController;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _SuggestionDetail({
    required this.suggestion,
    required this.scrollController,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.smart_toy, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${AppLocalizations.tr('ai_suggestions')} - ${s.patientName ?? "Patient"}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              if (s.chiefComplaint != null)
                _section(context, AppLocalizations.tr('chief_complaint'), s.chiefComplaint!, Icons.report_problem),
              if (s.symptomsText.isNotEmpty)
                _section(context, AppLocalizations.tr('symptoms'), s.symptomsText, Icons.sick),
              if (s.diagnosisText.isNotEmpty)
                _section(context, AppLocalizations.tr('diagnosis'), s.diagnosisText, Icons.medical_information),
              if (s.severity != null)
                _section(context, AppLocalizations.tr('severity'), AppLocalizations.tr(s.severity!), Icons.warning_amber),
              if (s.treatmentText.isNotEmpty)
                _section(context, AppLocalizations.tr('treatment_plan'), s.treatmentText, Icons.healing),
              if (s.medications != null && s.medications!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(AppLocalizations.tr('medications'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...s.medications!.map((m) {
                  if (m is Map) {
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.medication, color: Color(0xFF1565C0)),
                        title: Text(m['name'] ?? ''),
                        subtitle: Text('${m['dosage'] ?? ''} - ${m['frequency'] ?? ''} - ${m['duration'] ?? ''}'),
                      ),
                    );
                  }
                  return ListTile(title: Text(m.toString()));
                }),
              ],
              if (s.soapNote != null && s.soapNote!.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: Text(AppLocalizations.tr('soap_notes')),
                  initiallyExpanded: true,
                  children: [
                    if (s.soapNote!['subjective'] != null)
                      _soapItem(context, AppLocalizations.tr('soap_subjective'), s.soapNote!['subjective']),
                    if (s.soapNote!['objective'] != null)
                      _soapItem(context, AppLocalizations.tr('soap_objective'), s.soapNote!['objective']),
                    if (s.soapNote!['assessment'] != null)
                      _soapItem(context, AppLocalizations.tr('soap_assessment'), s.soapNote!['assessment']),
                    if (s.soapNote!['plan'] != null)
                      _soapItem(context, AppLocalizations.tr('soap_plan'), s.soapNote!['plan']),
                  ],
                ),
              ],
              if (s.transcript != null && s.transcript!.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: Text(AppLocalizations.tr('notes')),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(s.transcript!, style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: Text(AppLocalizations.tr('reject')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD32F2F),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: Text(AppLocalizations.tr('approve')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title, String content, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 4),
                    Text(content, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _soapItem(BuildContext context, String title, String content) {
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
