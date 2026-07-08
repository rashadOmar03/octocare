import 'api_service.dart';
import 'appointment_service.dart';
import '../models/appointment.dart';

class ReceptionistDashboardData {
  final int todayAppointments;
  final int pending;
  final int confirmed;
  final int completed;
  final int arrived;
  final double todayRevenue;
  final int actionRequired;

  ReceptionistDashboardData({
    required this.todayAppointments,
    required this.pending,
    required this.confirmed,
    required this.completed,
    required this.arrived,
    required this.todayRevenue,
    this.actionRequired = 0,
  });

  factory ReceptionistDashboardData.fromJson(Map<String, dynamic> json) {
    return ReceptionistDashboardData(
      todayAppointments: json['today_appointments'] ?? 0,
      pending: json['pending_appointments'] ?? 0,
      confirmed: json['confirmed_appointments'] ?? 0,
      completed: json['completed_appointments'] ?? 0,
      arrived: json['arrived_appointments'] ?? 0,
      todayRevenue: (json['today_revenue'] as num?)?.toDouble() ?? 0,
      actionRequired: json['action_required_appointments'] ?? 0,
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

  Future<double> getRevenueSummary({String? date}) async {
    var endpoint = '/receptionist/revenue-summary';
    if (date != null && date.isNotEmpty) {
      endpoint += '?date=$date';
    }
    final response = await _api.get(endpoint);
    final map = Map<String, dynamic>.from(response);
    return (map['net_revenue'] as num?)?.toDouble() ?? 0;
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

  Future<Map<String, dynamic>> fetchAvailableSlotsMeta(
    String doctorId,
    String date, {
    String? excludeAppointmentId,
  }) async {
    var endpoint = '/receptionist/available-slots?doctor_id=$doctorId&date=$date';
    if (excludeAppointmentId != null && excludeAppointmentId.isNotEmpty) {
      endpoint += '&exclude_appointment_id=$excludeAppointmentId';
    }
    final response = await _api.get(endpoint);
    if (response is List) {
      return {'slots': response.map((e) => e.toString()).toList(), 'reason': null};
    }
    final map = Map<String, dynamic>.from(response as Map);
    final slots = (map['slots'] as List? ?? []).map((e) => e.toString()).toList();
    return {
      'slots': slots,
      'reason': map['reason']?.toString(),
      'doctor_on_vacation': map['doctor_on_vacation'] == true || map['reason'] == 'vacation',
      'clinic_closed': map['clinic_closed'] == true || map['reason'] == 'clinic_closed',
      'doctor_day_off': map['doctor_day_off'] == true || map['reason'] == 'doctor_day_off',
      'all_slots_booked': map['all_slots_booked'] == true || map['reason'] == 'all_slots_booked',
      'working_days_label': map['working_days_label']?.toString() ?? '',
      'vacation_reason': map['vacation_reason']?.toString(),
    };
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

  Future<List<Appointment>> getAppointments({
    String? status,
    String? date,
    bool allHistory = false,
  }) async {
    if (allHistory) {
      return AppointmentService().getAppointments(status: status);
    }
    if (date != null) {
      final response = await _api.get('/receptionist/appointments?date=$date${status != null ? '&status=$status' : ''}');
      final list = response is List ? response : (response['results'] ?? []);
      return List<Appointment>.from(
        (list as List).map((e) => Appointment.fromJson(Map<String, dynamic>.from(e as Map))),
      );
    }
    return AppointmentService().getAppointments(status: status);
  }

  Future<List<Appointment>> getActionRequiredAppointments() async {
    final response = await _api.get('/receptionist/action-required-appointments');
    final list = response is List ? response : (response['results'] ?? []);
    return List<Appointment>.from(
      (list as List).map((e) => Appointment.fromJson(Map<String, dynamic>.from(e as Map))),
    );
  }

  Future<List<Appointment>> getQueue({String? doctorId, String? date}) async {
    var endpoint = '/receptionist/queue';
    final params = <String>[];
    if (doctorId != null && doctorId.isNotEmpty) {
      params.add('doctor_id=$doctorId');
    }
    if (date != null && date.isNotEmpty) {
      params.add('date=$date');
    } else {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      params.add('date=$today');
    }
    if (params.isNotEmpty) {
      endpoint += '?${params.join('&')}';
    }
    final response = await _api.get(endpoint);
    final list = response is List ? response : (response['results'] ?? []);
    return List<Appointment>.from(
      (list as List).map((e) => Appointment.fromJson(Map<String, dynamic>.from(e as Map))),
    );
  }
}
