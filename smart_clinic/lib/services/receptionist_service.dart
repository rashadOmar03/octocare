import 'api_service.dart';
import '../models/appointment.dart';

class ReceptionistDashboardData {
  final int todayAppointments;
  final int pending;
  final int confirmed;
  final int completed;
  final int arrived;
  final double todayRevenue;

  ReceptionistDashboardData({
    required this.todayAppointments,
    required this.pending,
    required this.confirmed,
    required this.completed,
    required this.arrived,
    required this.todayRevenue,
  });

  factory ReceptionistDashboardData.fromJson(Map<String, dynamic> json) {
    return ReceptionistDashboardData(
      todayAppointments: json['today_appointments'] ?? 0,
      pending: json['pending_appointments'] ?? 0,
      confirmed: json['confirmed_appointments'] ?? 0,
      completed: json['completed_appointments'] ?? 0,
      arrived: json['arrived_appointments'] ?? 0,
      todayRevenue: (json['today_revenue'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ReceptionistClinicInfo {
  final double defaultFee;
  final int appointmentDuration;

  ReceptionistClinicInfo({required this.defaultFee, required this.appointmentDuration});

  factory ReceptionistClinicInfo.fromJson(Map<String, dynamic> json) {
    return ReceptionistClinicInfo(
      defaultFee: (json['default_fee'] as num?)?.toDouble() ?? 100,
      appointmentDuration: json['appointment_duration'] ?? 30,
    );
  }
}

class PatientSearchResult {
  final String profileId;
  final String name;
  final String? email;
  final String? phone;

  PatientSearchResult({
    required this.profileId,
    required this.name,
    this.email,
    this.phone,
  });

  factory PatientSearchResult.fromJson(Map<String, dynamic> json) {
    return PatientSearchResult(
      profileId: json['profile_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
    );
  }
}

class ReceptionistService {
  final ApiService _api = ApiService.instance;

  Future<ReceptionistDashboardData> getDashboard() async {
    final response = await _api.get('/receptionist/dashboard');
    return ReceptionistDashboardData.fromJson(Map<String, dynamic>.from(response));
  }

  Future<ReceptionistClinicInfo> getClinicInfo() async {
    final response = await _api.get('/receptionist/clinic-info');
    return ReceptionistClinicInfo.fromJson(Map<String, dynamic>.from(response));
  }

  Future<List<PatientSearchResult>> searchPatients(String query) async {
    if (query.trim().isEmpty) return [];
    final response = await _api.get('/receptionist/patients/search?q=${Uri.encodeQueryComponent(query.trim())}');
    final list = response is List ? response : (response['results'] ?? []);
    return List<PatientSearchResult>.from(
      (list as List).map((e) => PatientSearchResult.fromJson(Map<String, dynamic>.from(e as Map))),
    );
  }

  Future<List<Map<String, dynamic>>> getDoctors() async {
    final response = await _api.get('/receptionist/doctors');
    final list = response is List ? response : (response['results'] ?? []);
    return List<Map<String, dynamic>>.from(
      (list as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  Future<List<String>> getAvailableSlots(String doctorId, String date) async {
    final response = await _api.get('/receptionist/available-slots?doctor_id=$doctorId&date=$date');
    final slots = response is List ? response : (response['slots'] as List? ?? []);
    return slots.map((e) => e.toString()).toList();
  }

  Future<Appointment> bookAppointment({
    required String patientId,
    required String doctorId,
    required String date,
    required String timeSlot,
    String? notes,
  }) async {
    final response = await _api.post('/receptionist/appointments', {
      'patient_id': patientId,
      'doctor_id': doctorId,
      'date': date,
      'time_slot': timeSlot,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return Appointment.fromJson(Map<String, dynamic>.from(response));
  }

  Future<List<Appointment>> getQueue({String? doctorId}) async {
    var endpoint = '/receptionist/queue';
    if (doctorId != null && doctorId.isNotEmpty) {
      endpoint += '?doctor_id=$doctorId';
    }
    final response = await _api.get(endpoint);
    final list = response is List ? response : (response['results'] ?? []);
    return List<Appointment>.from(
      (list as List).map((e) => Appointment.fromJson(Map<String, dynamic>.from(e as Map))),
    );
  }
}
