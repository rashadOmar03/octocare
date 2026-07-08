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

  Future<Appointment> loadFromServer() async {
    final raw = await ApiService.instance.get('/appointments/$appointmentId');
    if (raw is! Map) {
      throw ApiException('Unexpected appointment response.', 500);
    }
    return Appointment.fromJson(Map<String, dynamic>.from(raw));
  }

  try {
    var apt = await loadFromServer();

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

    final hasInProgressRecord =
        apt.hasConsultation || apt.medicalRecordId != null;

    if (!hasInProgressRecord) {
      try {
        apt = await appointmentService.startConsultation(appointmentId);
      } catch (startError) {
        apt = await loadFromServer();
        final canProceed = apt.isPaid && _isActiveVisitStatus(apt.status);
        if (!canProceed) {
          if (context.mounted) {
            showErrorSnackBar(context, consultationErrorMessage(startError));
          }
          return false;
        }
      }
    } else {
      apt = await loadFromServer();
    }

    if (!context.mounted) return false;
    return Navigator.pushNamed<bool>(context, AppRoutes.doctorConsultation, arguments: apt);
  } catch (e) {
    if (context.mounted) {
      showErrorSnackBar(context, consultationErrorMessage(e));
    }
    return false;
  }
}
