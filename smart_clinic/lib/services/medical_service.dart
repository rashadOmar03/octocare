import 'api_service.dart';
import '../models/medical_record.dart';
import '../models/prescription.dart';

class MedicalService {
  final ApiService _api = ApiService.instance;

  Future<MedicalRecord> createRecord(Map<String, dynamic> data) async {
    final response = await _api.post('/records/', data);
    return MedicalRecord.fromJson(Map<String, dynamic>.from(response));
  }

  Future<MedicalRecord> updateRecord(String id, Map<String, dynamic> data) async {
    final response = await _api.put('/records/$id', data);
    return MedicalRecord.fromJson(Map<String, dynamic>.from(response));
  }

  Future<List<MedicalRecord>> getPatientRecords({String? patientId, bool includeInactive = false}) async {
    String endpoint = patientId != null ? '/records/patient/$patientId' : '/records/patient/me';
    if (includeInactive && patientId != null) endpoint += '?include_inactive=true';
    final response = await _api.get(endpoint);
    final List<dynamic> data = response is List ? response : (response['items'] ?? []);
    return data.map((e) => MedicalRecord.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<MedicalRecord> getRecordDetail(String id) async {
    final response = await _api.get('/records/$id');
    return MedicalRecord.fromJson(Map<String, dynamic>.from(response));
  }

  Future<Prescription> createPrescription(Map<String, dynamic> data) async {
    final response = await _api.post('/prescriptions/', data);
    return Prescription.fromJson(Map<String, dynamic>.from(response));
  }

  Future<List<Prescription>> getPrescriptions({String? patientId, bool includeInactive = false}) async {
    String endpoint = '/prescriptions/';
    final params = <String>[];
    if (patientId != null) params.add('patient_id=$patientId');
    if (includeInactive) params.add('include_inactive=true');
    if (params.isNotEmpty) endpoint += '?${params.join('&')}';
    final response = await _api.get(endpoint);
    final List<dynamic> data = response is List ? response : (response['items'] ?? []);
    return data.map((e) => Prescription.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Prescription> getPrescriptionDetail(String id) async {
    final response = await _api.get('/prescriptions/$id');
    return Prescription.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> updatePrescriptionStatus(String id, String status, {DateTime? activeUntil}) async {
    await _api.put('/prescriptions/$id/status', {
      'status': status,
      if (activeUntil != null) 'active_until': activeUntil.toUtc().toIso8601String(),
    });
  }

  Future<void> deletePrescription(String id) async {
    await _api.delete('/prescriptions/$id');
  }

  Future<void> updatePrescription(String id, List<Map<String, dynamic>> items, {String? status}) async {
    await _api.put('/prescriptions/$id', {
      'items': items,
      if (status != null) 'status': status,
    });
  }

  Future<void> setRecordActive(String id, bool isActive) async {
    await _api.put('/records/$id/active', {'is_active': isActive});
  }

  Future<void> deleteRecord(String id) async {
    await _api.delete('/records/$id');
  }

  Future<Map<String, dynamic>> getDoctorActivityReport({String? patientId}) async {
    String endpoint = '/doctors/me/activity-report';
    if (patientId != null) endpoint += '?patient_id=$patientId';
    return Map<String, dynamic>.from(await _api.get(endpoint));
  }
}
