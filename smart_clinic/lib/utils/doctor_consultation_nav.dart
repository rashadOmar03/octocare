import 'package:flutter/material.dart';
import '../config/routes.dart';
import '../models/appointment.dart';
import '../services/api_service.dart';
import '../services/appointment_service.dart';
import '../l10n/localization.dart';
import 'ui_helpers.dart';

Future<bool?> openDoctorConsultation(BuildContext context, Appointment appointment) async {
  final appointmentService = AppointmentService();

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

  if (appointment.canDoctorStartConsultation) {
    try {
      var apt = await freshAppointment(appointment);
      if (!apt.isConsultationEditable && apt.id != null) {
        apt = await appointmentService.startConsultation(apt.id!);
      }
      if (!context.mounted) return false;
      return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: apt);
    } catch (e) {
      if (context.mounted) {
        final message = e.toString().contains('payment')
            ? AppLocalizations.tr('payment_required_consultation')
            : AppLocalizations.tr('consultation_not_available');
        showErrorSnackBar(context, message);
      }
      return false;
    }
  }

  if (appointment.status == 'arrived' && !appointment.isPaid) {
    showErrorSnackBar(context, AppLocalizations.tr('payment_required_consultation'));
    return false;
  }
  if (appointment.status == 'confirmed' || appointment.status == 'pending') {
    showErrorSnackBar(context, AppLocalizations.tr('payment_required_consultation'));
    return false;
  }
  showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
  return false;
}
