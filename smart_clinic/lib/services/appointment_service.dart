import 'api_service.dart';
import '../models/appointment.dart';

class AppointmentService {
  final ApiService _api = ApiService.instance;

  Future<List<Appointment>> getAppointments({String? status, String? date}) async {
    String endpoint = '/appointments/';
    final params = <String>[];
    if (status != null) params.add('status=$status');
    if (date != null) params.add('date=$date');
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

  Future<void> leaveQueue(String id) async {
    await _api.put('/appointments/$id/leave-queue', {});
  }

  Future<void> receptionistReschedule(String id, Map<String, dynamic> data) async {
    await _api.put('/appointments/$id/receptionist-reschedule', data);
  }

  Future<void> completeAppointment(String id) async {
    await _api.put('/appointments/$id/complete', {});
  }

  Future<List<Map<String, dynamic>>> getAvailableSlots(String doctorId, String date) async {
    final response = await _api.get('/appointments/available-slots?doctor_id=$doctorId&date=$date');
    if (response is List) {
      return List<Map<String, dynamic>>.from(
        response.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return (response['slots'] as List? ?? []).map((e) => <String, dynamic>{'time': e.toString(), 'available': true}).toList();
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
