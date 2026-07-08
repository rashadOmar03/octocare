import 'api_service.dart';
import '../models/appointment.dart';

class AppointmentService {
  final ApiService _api = ApiService.instance;

  Future<List<Appointment>> getAppointments({String? status, String? date, String? dateFrom, String? dateTo}) async {
    String endpoint = '/appointments/';
    final params = <String>[];
    if (status != null) params.add('status=$status');
    if (date != null) params.add('date=$date');
    if (dateFrom != null) params.add('date_from=$dateFrom');
    if (dateTo != null) params.add('date_to=$dateTo');
    if (params.isNotEmpty) endpoint += '?${params.join('&')}';

    final response = await _api.get(endpoint);
    final list = response is List ? response : (response['items'] ?? []);
    return List<Appointment>.from(
      (list as List).map((e) => Appointment.fromJson(Map<String, dynamic>.from(e as Map))),
    );
  }

  Future<Appointment> bookAppointment(Map<String, dynamic> data) async {
    final response = await _api.post('/appointments/', data);
    return Appointment.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> cancelAppointment(String id) async {
    await _api.put('/appointments/$id/cancel', {});
  }

  Future<void> confirmAppointment(String id) async {
    await _api.put('/appointments/$id/confirm', {});
  }

  Future<void> rescheduleAppointment(String id, Map<String, dynamic> data) async {
    await _api.put('/appointments/$id/reschedule', data);
  }

  Future<void> markArrived(String id) async {
    await _api.put('/appointments/$id/arrive', {});
  }

  Future<Appointment> startConsultation(String id) async {
    final response = await _api.put('/appointments/$id/start-consultation', {});
    return Appointment.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> leaveQueue(String id) async {
    await _api.put('/appointments/$id/leave-queue', {});
  }

  Future<void> receptionistReschedule(String id, Map<String, dynamic> data) async {
    await _api.put('/appointments/$id/receptionist-reschedule', data);
  }

  Future<void> completeAppointment(String id) async {
    await _api.put('/appointments/$id/complete', {});
  }

  Future<List<Map<String, dynamic>>> getAvailableSlots(
    String doctorId,
    String date, {
    String? excludeAppointmentId,
  }) async {
    final result = await fetchAvailableSlots(
      doctorId,
      date,
      excludeAppointmentId: excludeAppointmentId,
    );
    return result['slots'] as List<Map<String, dynamic>>;
  }

  Future<Map<String, dynamic>> fetchAvailableSlots(
    String doctorId,
    String date, {
    String? excludeAppointmentId,
  }) async {
    var endpoint = '/appointments/available-slots?doctor_id=$doctorId&date=$date';
    if (excludeAppointmentId != null && excludeAppointmentId.isNotEmpty) {
      endpoint += '&exclude_appointment_id=$excludeAppointmentId';
    }
    final response = await _api.get(endpoint);
    if (response is List) {
      return {
        'slots': List<Map<String, dynamic>>.from(
          response.map((e) => Map<String, dynamic>.from(e as Map)),
        ),
        'doctor_on_vacation': false,
        'vacation_reason': null,
      };
    }
    final slots = (response['slots'] as List? ?? [])
        .map((e) => <String, dynamic>{'time': e.toString(), 'available': true})
        .toList();
    return {
      'slots': slots,
      'doctor_on_vacation': response['doctor_on_vacation'] == true || response['reason'] == 'vacation',
      'vacation_reason': response['vacation_reason']?.toString(),
      'reason': response['reason']?.toString(),
      'clinic_closed': response['clinic_closed'] == true,
      'doctor_day_off': response['doctor_day_off'] == true,
      'all_slots_booked': response['all_slots_booked'] == true,
      'working_days_label': response['working_days_label']?.toString(),
    };
  }

  Future<List<Appointment>> getDoctorQueue({String? date}) async {
    final now = DateTime.now();
    final today = date ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return getAppointments(status: 'arrived', date: today);
  }

  Future<Map<String, dynamic>?> getMyQueueStatus() async {
    try {
      final response = await _api.get('/appointments/my-queue');
      if (response is Map && response['in_queue'] == true) {
        return Map<String, dynamic>.from(response);
      }
    } catch (_) {}
    return null;
  }

  Future<List<Appointment>> getTodayAppointments() async {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return getAppointments(date: date);
  }
}
