import 'package:flutter/material.dart';
import '../config/routes.dart';
import '../models/appointment.dart';
import '../l10n/localization.dart';
import 'ui_helpers.dart';

void openDoctorConsultation(BuildContext context, Appointment appointment) {
  if (appointment.isConsultationEditOnly || appointment.status == 'completed') {
    if (!appointment.hasConsultation && appointment.medicalRecordId == null) {
      showErrorSnackBar(context, AppLocalizations.tr('no_consultation_to_edit'));
      return;
    }
    Navigator.pushNamed(context, AppRoutes.doctorConsultation, arguments: appointment);
    return;
  }
  if (appointment.isConsultationEditable) {
    Navigator.pushNamed(context, AppRoutes.doctorConsultation, arguments: appointment);
    return;
  }
  if (appointment.status == 'arrived' && !appointment.isPaid) {
    showErrorSnackBar(context, AppLocalizations.tr('payment_required_consultation'));
    return;
  }
  if (appointment.status == 'confirmed') {
    showErrorSnackBar(context, AppLocalizations.tr('arrived_required_consultation'));
    return;
  }
  showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
}
