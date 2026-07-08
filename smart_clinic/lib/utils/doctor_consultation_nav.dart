import 'package:flutter/material.dart';
import '../config/routes.dart';
import '../models/appointment.dart';
import '../services/api_service.dart';
import '../services/appointment_service.dart';
import '../l10n/localization.dart';
import 'ui_helpers.dart';

bool _isActiveVisitStatus(String? status) =>
    status == 'arrived' || status == 'confirmed' || status == 'pending';

Future<bool?> openDoctorConsultation(BuildContext context, Appointment appointment) async {
  final appointmentId = appointment.id;
  if (appointmentId == null || appointmentId.isEmpty) {
    showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
    return false;
  }

  final appointmentService = AppointmentService();

  String consultationErrorMessage(Object error) {
    if (error is ApiException && error.message.isNotEmpty) {
      return error.message;
    }
    final text = error.toString().toLowerCase();
    if (text.contains('payment')) {
      return AppLocalizations.tr('payment_required_consultation');
    }
    if (text.contains('arrived') || text.contains('queue')) {
      return AppLocalizations.tr('arrived_required_consultation');
    }
    return AppLocalizations.tr('consultation_not_available');
  }

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
        if (context.mounted) {
          showErrorSnackBar(context, AppLocalizations.tr('no_record_for_appointment'));
        }
        return false;
      }
      if (!context.mounted) return false;
      return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: apt);
    }

    if (apt.status == 'cancelled') {
      if (context.mounted) {
        showErrorSnackBar(context, AppLocalizations.tr('consultation_not_available'));
      }
      return false;
    }

    final hasInProgressRecord = apt.hasConsultation || apt.medicalRecordId != null;

    if (hasInProgressRecord) {
      if (!context.mounted) return false;
      return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: apt);
    }

    try {
      final started = await appointmentService.startConsultation(appointmentId);
      if (!context.mounted) return false;
      return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: started);
    } catch (startError) {
      final retryApt = await loadFromServer();
      final latest = retryApt ?? apt;
      final canProceed = latest.isPaid && _isActiveVisitStatus(latest.status);
      if (!canProceed) {
        if (context.mounted) {
          showErrorSnackBar(context, consultationErrorMessage(startError));
        }
        return false;
      }
      if (!context.mounted) return false;
      return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: latest);
    }
  } catch (e) {
    final canFallback = appointment.isPaid && _isActiveVisitStatus(appointment.status);
    if (canFallback) {
      if (!context.mounted) return false;
      return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: appointment);
    }
    if (context.mounted) {
      showErrorSnackBar(context, consultationErrorMessage(e));
    }
    return false;
  }
}
