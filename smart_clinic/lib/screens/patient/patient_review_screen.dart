import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/review_service.dart';
import '../../utils/ui_helpers.dart';

class PatientReviewScreen extends StatefulWidget {
  const PatientReviewScreen({super.key});

  @override
  State<PatientReviewScreen> createState() => _PatientReviewScreenState();
}

class _PatientReviewScreenState extends State<PatientReviewScreen> {
  final ReviewService _service = ReviewService();
  final _doctorCommentController = TextEditingController();
  final _receptionistCommentController = TextEditingController();

  Map<String, dynamic>? _visit;
  int _doctorStars = 0;
  int _receptionistStars = 0;
  bool _submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (_visit == null && args is Map) {
      _visit = Map<String, dynamic>.from(args);
    }
  }

  @override
  void dispose() {
    _doctorCommentController.dispose();
    _receptionistCommentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final visit = _visit;
    if (visit == null) return;
    if (_doctorStars < 1) {
      showErrorSnackBar(context, AppLocalizations.tr('doctor_rating_required'));
      return;
    }
    final receptionistId = visit['receptionist_id']?.toString();
    if (receptionistId != null && receptionistId.isNotEmpty && _receptionistStars < 1) {
      showErrorSnackBar(context, AppLocalizations.tr('receptionist_rating_required'));
      return;
    }

    setState(() => _submitting = true);
    try {
      await _service.submitReview(
        appointmentId: visit['appointment_id']?.toString() ?? '',
        doctorRating: _doctorStars,
        receptionistRating: receptionistId != null && receptionistId.isNotEmpty ? _receptionistStars : null,
        doctorComment: _doctorCommentController.text,
        receptionistComment: _receptionistCommentController.text,
      );
      if (mounted) {
        showSuccessSnackBar(context, AppLocalizations.tr('review_submitted'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    }
    if (mounted) setState(() => _submitting = false);
  }

  Widget _starRow(int value, ValueChanged<int> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final star = i + 1;
        return IconButton(
          onPressed: () => setState(() => onChanged(star)),
          icon: Icon(
            star <= value ? Icons.star : Icons.star_border,
            color: const Color(0xFFF9A825),
            size: 36,
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visit = _visit;
    if (visit == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.tr('leave_review'))),
        body: Center(child: Text(AppLocalizations.tr('no_data'))),
      );
    }

    final doctorName = visit['doctor_name']?.toString() ?? AppLocalizations.tr('doctor');
    final receptionistName = visit['receptionist_name']?.toString();
    final hasReceptionist = visit['receptionist_id'] != null && visit['receptionist_id'].toString().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.tr('leave_review'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${visit['date'] ?? ''} · ${visit['time_slot'] ?? ''}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Text(AppLocalizations.tr('rate_doctor'), style: Theme.of(context).textTheme.titleMedium),
          Text(doctorName),
          _starRow(_doctorStars, (v) => _doctorStars = v),
          TextField(
            controller: _doctorCommentController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: AppLocalizations.tr('review_comment'),
              hintText: AppLocalizations.tr('review_comment_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
          if (hasReceptionist) ...[
            const SizedBox(height: 24),
            Text(AppLocalizations.tr('rate_receptionist'), style: Theme.of(context).textTheme.titleMedium),
            Text(receptionistName ?? AppLocalizations.tr('receptionist')),
            _starRow(_receptionistStars, (v) => _receptionistStars = v),
            TextField(
              controller: _receptionistCommentController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: AppLocalizations.tr('review_comment'),
                hintText: AppLocalizations.tr('review_comment_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(AppLocalizations.tr('submit_review')),
          ),
        ],
      ),
    );
  }
}
