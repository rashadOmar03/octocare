import 'package:flutter/material.dart';
import '../config/routes.dart';
import '../models/appointment.dart';
import '../l10n/localization.dart';
import 'ui_helpers.dart';

Future<bool?> openDoctorConsultation(BuildContext context, Appointment appointment) async {
  if (appointment.id == null || appointment.id!.isEmpty) {
    showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
    return false;
  }

  if (appointment.status == 'cancelled') {
    showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
    return false;
  }

  try {
    return await Navigator.of(context).pushNamed<bool>(
      AppRoutes.doctorConsultation,
      arguments: appointment,
    );
  } catch (e) {
    debugPrint('[Consultation] Navigation error: $e');
    if (context.mounted) {
      showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
    }
    return false;
  }
}
