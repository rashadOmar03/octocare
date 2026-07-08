import 'package:flutter/material.dart';
import '../config/routes.dart';
import '../models/appointment.dart';
import '../services/api_service.dart';
import '../services/appointment_service.dart';
import '../l10n/localization.dart';
import 'ui_helpers.dart';

Future<bool?> openDoctorConsultation(BuildContext context, Appointment appointment) async {
  final appointmentId = appointment.id;
  if (appointmentId == null || appointmentId.isEmpty) {
    showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
    return false;
  }

  final navigator = Navigator.of(context);
  final appointmentService = AppointmentService();

  Future<Appointment?> loadFromServer() async {
    try {
      final raw = await ApiService.instance.get('/appointments/$appointmentId');
      if (raw is Map) {
        return Appointment.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    return null;
  }

  try {
    final serverApt = await loadFromServer();
    final apt = serverApt ?? appointment;

    if (apt.status == 'completed' || apt.isConsultationEditOnly) {
      if (!apt.hasConsultation && apt.medicalRecordId == null) {
        try { showErrorSnackBar(context, AppLocalizations.tr('no_record_for_appointment')); } catch (_) {}
        return false;
      }
      return navigator.pushNamed<bool>(AppRoutes.doctorConsultation, arguments: apt);
    }

    if (apt.status == 'cancelled') {
      try { showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available')); } catch (_) {}
      return false;
    }

    final hasInProgressRecord = apt.hasConsultation || apt.medicalRecordId != null;
    if (hasInProgressRecord) {
      return navigator.pushNamed<bool>(AppRoutes.doctorConsultation, arguments: apt);
    }

    Appointment navigateWith = apt;
    try {
      navigateWith = await appointmentService.startConsultation(appointmentId);
    } catch (_) {
      final retryApt = await loadFromServer();
      if (retryApt != null) navigateWith = retryApt;
    }

    return navigator.pushNamed<bool>(AppRoutes.doctorConsultation, arguments: navigateWith);
  } catch (_) {
    try {
      return navigator.pushNamed<bool>(AppRoutes.doctorConsultation, arguments: appointment);
    } catch (_) {
      return false;
    }
  }
}
