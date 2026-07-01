class Prescription {
  final String? id;
  final String? patientId;
  final String? doctorId;
  final String? recordId;
  final String? patientName;
  final String? doctorName;
  final String? status;
  final String? notes;
  final String? createdAt;
  final String? activeUntil;
  final List<PrescriptionItem>? items;

  Prescription({
    this.id,
    this.patientId,
    this.doctorId,
    this.recordId,
    this.patientName,
    this.doctorName,
    this.status,
    this.notes,
    this.createdAt,
    this.activeUntil,
    this.items,
  });

  factory Prescription.fromJson(Map<String, dynamic> json) {
    return Prescription(
      id: json['id']?.toString(),
      patientId: (json['patient_id'] ?? json['patient'])?.toString(),
      doctorId: (json['doctor_id'] ?? json['doctor'])?.toString(),
      recordId: (json['record_id'] ?? json['record'] ?? json['medical_record_id'])?.toString(),
      patientName: json['patient_name'],
      doctorName: json['doctor_name'],
      status: json['status'],
      notes: json['notes'],
      createdAt: json['created_at'],
      activeUntil: json['active_until']?.toString(),
      items: json['items'] != null
          ? (json['items'] as List).map((e) => PrescriptionItem.fromJson(e)).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient': patientId,
      'doctor': doctorId,
      'record': recordId,
      'status': status,
      'notes': notes,
      'items': items?.map((e) => e.toJson()).toList(),
    };
  }
}

class PrescriptionItem {
  final String? id;
  final String? medicationName;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final String? notes;

  PrescriptionItem({
    this.id,
    this.medicationName,
    this.dosage,
    this.frequency,
    this.duration,
    this.notes,
  });

  factory PrescriptionItem.fromJson(Map<String, dynamic> json) {
    return PrescriptionItem(
      id: json['id']?.toString(),
      medicationName: json['medication_name'],
      dosage: json['dosage'],
      frequency: json['frequency'],
      duration: json['duration'],
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'medication_name': medicationName,
      'dosage': dosage,
      'frequency': frequency,
      'duration': duration,
      'notes': notes,
    };
  }
}
