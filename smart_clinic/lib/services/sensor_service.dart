import 'api_service.dart';
import '../models/sensor_reading.dart';

class SensorService {
  final ApiService _api = ApiService.instance;

  Future<Map<String, dynamic>> uploadReading(Map<String, dynamic> data) async {
    final response = await _api.post('/sensors/upload', data);
    return Map<String, dynamic>.from(response);
  }

  Future<SensorReading?> getLatest({String? patientId}) async {
    String endpoint = '/sensors/latest/${patientId ?? "me"}';
    try {
      final response = await _api.get(endpoint);
      if (response != null && response is Map && response.isNotEmpty) {
        return SensorReading.fromJson(Map<String, dynamic>.from(response));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<SensorReading>> getHistory({String? patientId, String? period}) async {
    String endpoint = '/sensors/history/${patientId ?? "me"}';
    if (period != null) endpoint += '?period=$period';

    try {
      final response = await _api.get(endpoint);
      final List<dynamic> data = response is List ? response : (response['items'] ?? []);
      return data.map((e) => SensorReading.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAlerts({String? patientId}) async {
    String endpoint = '/sensors/alerts/${patientId ?? "me"}';
    try {
      final response = await _api.get(endpoint);
      final List<dynamic> data = response is List ? response : (response['items'] ?? []);
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }
}
