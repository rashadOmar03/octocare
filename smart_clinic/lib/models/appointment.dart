class Appointment {
  final String? id;
  final String? patientId;
  final String? doctorId;
  final String? patientName;
  final String? doctorName;
  final String? specialtyName;
  final String? date;
  final String? timeSlot;
  final String? status;
  final String? notes;
  final int? queueNumber;
  final String? createdAt;
  final bool isPaid;
  final String? paymentStatus;
  final bool needsPayment;
  final String? medicalRecordId;
  final bool hasConsultation;
  final String? patientPhotoUrl;
  final double? consultationFee;

  Appointment({
    this.id,
    this.patientId,
    this.doctorId,
    this.patientName,
    this.doctorName,
    this.specialtyName,
    this.date,
    this.timeSlot,
    this.status,
    this.notes,
    this.queueNumber,
    this.createdAt,
    this.isPaid = false,
    this.paymentStatus,
    this.needsPayment = false,
    this.medicalRecordId,
    this.hasConsultation = false,
    this.patientPhotoUrl,
    this.consultationFee,
  });

  bool get isConsultationEditable =>
      isPaid && (status == 'arrived' || status == 'confirmed' || status == 'pending');
  bool get canDoctorStartConsultation =>
      isPaid && (status == 'arrived' || status == 'confirmed' || status == 'pending');
  bool get isConsultationEditOnly => status == 'completed' && (hasConsultation || medicalRecordId != null);

  bool get isToday {
    if (date == null || date!.isEmpty) return false;
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return date == today;
  }

  factory Appointment.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value) {
      if (value == true || value == 1) return true;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'true' || normalized == '1';
      }
      return false;
    }

    final paymentStatus = json['payment_status']?.toString();
    final isPaid = parseBool(json['is_paid']) || paymentStatus == 'paid';

    return Appointment(
      id: json['id']?.toString(),
      patientId: (json['patient_id'] ?? json['patient'])?.toString(),
      doctorId: (json['doctor_id'] ?? json['doctor'])?.toString(),
      patientName: json['patient_name'],
      doctorName: json['doctor_name'],
      specialtyName: json['specialty_name'],
      date: json['date']?.toString(),
      timeSlot: json['time_slot'] ?? json['time'],
      status: json['status'],
      notes: json['notes'],
      queueNumber: json['queue_number'] is int ? json['queue_number'] : int.tryParse(json['queue_number']?.toString() ?? ''),
      createdAt: json['created_at']?.toString(),
      isPaid: isPaid,
      paymentStatus: paymentStatus,
      needsPayment: parseBool(json['needs_payment']) || paymentStatus == 'refunded',
      medicalRecordId: json['medical_record_id']?.toString(),
      hasConsultation: json['has_consultation'] == true || json['medical_record_id'] != null,
      patientPhotoUrl: json['patient_photo_url']?.toString(),
      consultationFee: json['consultation_fee'] == null
          ? null
          : (json['consultation_fee'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient_id': patientId,
      'doctor_id': doctorId,
      'date': date,
      'time_slot': timeSlot,
      'status': status,
      'notes': notes,
    };
  }
}
