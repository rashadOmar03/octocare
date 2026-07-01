class MedicalRecord {
  final String? id;
  final String? patientId;
  final String? doctorId;
  final String? patientName;
  final String? doctorName;
  final String? visitDate;
  final String? chiefComplaint;
  final String? symptoms;
  final String? diagnosis;
  final String? severity;
  final String? treatmentPlan;
  final String? notes;
  final String? soapSubjective;
  final String? soapObjective;
  final String? soapAssessment;
  final String? soapPlan;
  final Map<String, dynamic>? structuredData;
  final bool isActive;
  final String? createdAt;
  final List<dynamic>? prescriptions;
  final List<dynamic>? files;

  MedicalRecord({
    this.id,
    this.patientId,
    this.doctorId,
    this.patientName,
    this.doctorName,
    this.visitDate,
    this.chiefComplaint,
    this.symptoms,
    this.diagnosis,
    this.severity,
    this.treatmentPlan,
    this.notes,
    this.soapSubjective,
    this.soapObjective,
    this.soapAssessment,
    this.soapPlan,
    this.structuredData,
    this.isActive = true,
    this.createdAt,
    this.prescriptions,
    this.files,
  });

  factory MedicalRecord.fromJson(Map<String, dynamic> json) {
    return MedicalRecord(
      id: json['id']?.toString(),
      patientId: (json['patient_id'] ?? json['patient'])?.toString(),
      doctorId: (json['doctor_id'] ?? json['doctor'])?.toString(),
      patientName: json['patient_name'],
      doctorName: json['doctor_name'],
      visitDate: json['visit_date'],
      chiefComplaint: json['chief_complaint'],
      symptoms: json['symptoms'],
      diagnosis: json['diagnosis'],
      severity: json['severity'],
      treatmentPlan: json['treatment_plan'],
      notes: json['notes'],
      soapSubjective: json['soap_subjective'],
      soapObjective: json['soap_objective'],
      soapAssessment: json['soap_assessment'],
      soapPlan: json['soap_plan'],
      structuredData: json['structured_data'] is Map
          ? Map<String, dynamic>.from(json['structured_data'])
          : null,
      isActive: json['is_active'] != false,
      createdAt: json['created_at'],
      prescriptions: json['prescriptions'],
      files: json['files'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'patient': patientId,
      'doctor': doctorId,
      'doctor_name': doctorName,
      'visit_date': visitDate,
      'chief_complaint': chiefComplaint,
      'symptoms': symptoms,
      'diagnosis': diagnosis,
      'severity': severity,
      'treatment_plan': treatmentPlan,
      'notes': notes,
      'soap_subjective': soapSubjective,
      'soap_objective': soapObjective,
      'soap_assessment': soapAssessment,
      'soap_plan': soapPlan,
    };
  }
}
