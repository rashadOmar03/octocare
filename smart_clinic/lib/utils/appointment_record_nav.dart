import 'package:flutter/material.dart';
import '../config/routes.dart';
import '../models/appointment.dart';
import '../services/api_service.dart';
import '../services/medical_service.dart';
import '../l10n/localization.dart';
import 'ui_helpers.dart';

Future<Appointment> _freshAppointment(Appointment appointment) async {
  if (appointment.id == null) return appointment;
  try {
    final fresh = Map<String, dynamic>.from(
      await ApiService.instance.get('/appointments/${appointment.id}'),
    );
    return Appointment.fromJson(fresh);
  } catch (_) {
    return appointment;
  }
}

/// Opens the medical record linked to a completed appointment (read-only detail screen).
Future<void> openAppointmentMedicalRecord(
  BuildContext context,
  Appointment appointment, {
  String recordDetailRoute = AppRoutes.doctorRecordDetail,
}) async {
  var apt = await _freshAppointment(appointment);
  var recordId = apt.medicalRecordId;
  if (recordId == null && !apt.hasConsultation) {
    if (context.mounted) {
      showErrorSnackBar(context, AppLocalizations.tr('no_record_for_appointment'));
    }
    return;
  }

  try {
    final record = await MedicalService().getRecordDetail(recordId ?? apt.medicalRecordId!);
    if (context.mounted) {
      await Navigator.pushNamed(context, recordDetailRoute, arguments: record);
    }
  } catch (e) {
    if (context.mounted) showErrorSnackBar(context, e);
  }
}
