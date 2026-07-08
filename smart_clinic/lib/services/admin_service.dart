import 'api_service.dart';
import 'report_download_service.dart';

class AdminService {
  final ApiService _api = ApiService.instance;

  Future<Map<String, dynamic>> getDashboard() async {
    final response = await _api.get('/admin/dashboard');
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> createDoctor(Map<String, dynamic> data) async {
    final response = await _api.post('/admin/doctors', data);
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> createReceptionist(Map<String, dynamic> data) async {
    final response = await _api.post('/admin/receptionists', data);
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> createAdmin(Map<String, dynamic> data) async {
    final response = await _api.post('/admin/admins', data);
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> createPatient(Map<String, dynamic> data) async {
    final response = await _api.post('/receptionist/patients', data);
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> getUsers({String? role}) async {
    String endpoint = '/admin/users';
    if (role != null) endpoint += '?role=$role';
    final response = await _api.get(endpoint);
    final List<dynamic> data = response is List ? response : (response['items'] ?? []);
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getSpecialties() async {
    final response = await _api.get('/admin/specialties');
    final List<dynamic> data = response is List ? response : (response['items'] ?? []);
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> createSpecialty(Map<String, dynamic> data) async {
    await _api.post('/admin/specialties', data);
  }

  Future<void> updateSpecialty(int id, Map<String, dynamic> data) async {
    await _api.put('/admin/specialties/$id', data);
  }

  Future<void> deleteSpecialty(int id) async {
    await _api.delete('/admin/specialties/$id');
  }

  Future<Map<String, dynamic>> getSettings() async {
    final response = await _api.get('/admin/settings');
    return Map<String, dynamic>.from(response);
  }

  Future<void> updateSettings(Map<String, dynamic> data) async {
    await _api.put('/admin/settings', data);
  }

  Future<Map<String, dynamic>> getDoctorManage(String doctorId) async {
    final response = await _api.get('/admin/doctors/$doctorId/manage');
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> updateDoctorSchedule(String doctorId, Map<String, dynamic> data) async {
    final response = await _api.put('/admin/doctors/$doctorId/schedule', data);
    return Map<String, dynamic>.from(response);
  }

  Future<void> addDoctorTimeOff(String doctorId, Map<String, dynamic> data) async {
    await _api.post('/admin/doctors/$doctorId/time-off', data);
  }

  Future<void> deleteDoctorTimeOff(String doctorId, String timeOffId) async {
    await _api.delete('/admin/doctors/$doctorId/time-off/$timeOffId');
  }

  Future<Map<String, dynamic>> updateDoctorFee(String doctorId, double? fee) async {
    final response = await _api.put('/admin/doctors/$doctorId/fee', {'consultation_fee': fee});
    return Map<String, dynamic>.from(response);
  }

  Future<dynamic> getChartData(String chartType) async {
    final response = await _api.get('/admin/charts/$chartType');
    return response;
  }

  Future<void> toggleUserActive(String userId, bool active) async {
    await _api.put('/admin/users/$userId', {'is_active': active});
  }

  Future<void> deleteUser(String userId) async {
    await _api.delete('/admin/users/$userId');
  }

  Future<Map<String, dynamic>> purgeAllPatients() async {
    final response = await _api.post('/admin/purge-patients', {'confirm': 'DELETE_ALL_PATIENTS'});
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> getPatientDetail(String userId) async {
    final response = await _api.get('/admin/patients/$userId/detail');
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> getPayments({String? status}) async {
    var endpoint = '/receptionist/payments';
    if (status != null && status.isNotEmpty) endpoint += '?status=$status';
    final response = await _api.get(endpoint);
    final List<dynamic> data = response is List ? response : (response['items'] ?? []);
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> downloadReport(String reportType, {Map<String, String>? params, String format = 'pdf'}) async {
    await ReportDownloadService.download(
      '/reports/$reportType',
      filename: '$reportType.$format',
      queryParams: params,
      format: format,
    );
  }

  String getReportUrl(Map<String, dynamic> params) {
    final queryParts = <String>[];
    params.forEach((key, value) {
      if (value != null && key != 'type') queryParts.add('$key=$value');
    });
    final query = queryParts.isNotEmpty ? '?${queryParts.join('&')}' : '';
    final reportType = params['type'] ?? 'appointments';
    return '${_api.baseUrl}/reports/$reportType$query';
  }
}
