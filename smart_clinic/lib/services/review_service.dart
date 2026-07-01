import 'api_service.dart';

class ReviewService {
  final ApiService _api = ApiService.instance;

  Future<List<Map<String, dynamic>>> getPendingReviews() async {
    final response = await _api.get('/reviews/pending');
    final list = response is List ? response : (response['items'] ?? []);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getDoctorReviews(String doctorId) async {
    return Map<String, dynamic>.from(await _api.get('/reviews/doctor/$doctorId'));
  }

  Future<void> submitReview({
    required String appointmentId,
    required int doctorRating,
    int? receptionistRating,
    String? doctorComment,
    String? receptionistComment,
  }) async {
    await _api.post('/reviews/', {
      'appointment_id': appointmentId,
      'doctor_rating': doctorRating,
      if (receptionistRating != null) 'receptionist_rating': receptionistRating,
      if (doctorComment != null && doctorComment.trim().isNotEmpty) 'doctor_comment': doctorComment.trim(),
      if (receptionistComment != null && receptionistComment.trim().isNotEmpty)
        'receptionist_comment': receptionistComment.trim(),
    });
  }
}
