import 'package:flutter/material.dart';
import '../config/routes.dart';
import '../models/appointment.dart';
import '../services/api_service.dart';
import '../l10n/localization.dart';
import 'ui_helpers.dart';

Future<bool?> openDoctorConsultation(BuildContext context, Appointment appointment) async {
  Future<Appointment> freshAppointment(Appointment apt) async {
    if (apt.id == null) return apt;
    try {
      final fresh = Map<String, dynamic>.from(
        await ApiService.instance.get('/appointments/${apt.id}'),
      );
      return Appointment.fromJson(fresh);
    } catch (_) {
      return apt;
    }
  }

  if (appointment.status == 'completed' || appointment.isConsultationEditOnly) {
    final apt = await freshAppointment(appointment);
    if (!apt.hasConsultation && apt.medicalRecordId == null) {
      if (context.mounted) {
        showErrorSnackBar(context, AppLocalizations.tr('no_record_for_appointment'));
      }
      return false;
    }
    return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: apt);
  }
  if (appointment.isConsultationEditable) {
    final apt = await freshAppointment(appointment);
    return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: apt);
  }
  if (appointment.status == 'arrived' && !appointment.isPaid) {
    showErrorSnackBar(context, AppLocalizations.tr('payment_required_consultation'));
    return false;
  }
  if (appointment.status == 'confirmed') {
    showErrorSnackBar(context, AppLocalizations.tr('arrived_required_consultation'));
    return false;
  }
  showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
  return false;
}
