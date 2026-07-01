class AIConversation {
  final String? id;
  final String? title;
  final String? createdAt;
  final List<AIMessage>? messages;

  AIConversation({
    this.id,
    this.title,
    this.createdAt,
    this.messages,
  });

  factory AIConversation.fromJson(Map<String, dynamic> json) {
    return AIConversation(
      id: json['id']?.toString(),
      title: json['title'],
      createdAt: json['created_at'],
      messages: json['messages'] != null
          ? (json['messages'] as List).map((e) => AIMessage.fromJson(e)).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
    };
  }
}

class AIMessage {
  final String? role;
  final String? content;
  final String? timestamp;

  AIMessage({
    this.role,
    this.content,
    this.timestamp,
  });

  factory AIMessage.fromJson(Map<String, dynamic> json) {
    return AIMessage(
      role: json['role'],
      content: json['content'],
      timestamp: json['timestamp'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
    };
  }
}

class AISuggestion {
  final String? id;
  final String? patientId;
  final String? doctorId;
  final String? patientName;
  final String? appointmentId;
  final String? transcript;
  final String? chiefComplaint;
  final String? severity;
  final dynamic diagnosis;
  final dynamic symptoms;
  final dynamic treatmentPlan;
  final List<dynamic>? medications;
  final Map<String, dynamic>? soapNote;
  final Map<String, dynamic>? extractedData;
  final String? status;
  final String? createdAt;

  AISuggestion({
    this.id,
    this.patientId,
    this.doctorId,
    this.patientName,
    this.appointmentId,
    this.transcript,
    this.chiefComplaint,
    this.severity,
    this.diagnosis,
    this.symptoms,
    this.treatmentPlan,
    this.medications,
    this.soapNote,
    this.extractedData,
    this.status,
    this.createdAt,
  });

  factory AISuggestion.fromJson(Map<String, dynamic> json) {
    return AISuggestion(
      id: json['id']?.toString(),
      patientId: (json['patient_id'] ?? json['patient'])?.toString(),
      doctorId: (json['doctor_id'] ?? json['doctor'])?.toString(),
      patientName: json['patient_name'],
      appointmentId: json['appointment_id']?.toString(),
      transcript: json['transcript'],
      chiefComplaint: json['chief_complaint'],
      severity: json['severity'],
      diagnosis: json['diagnosis'],
      symptoms: json['symptoms'],
      treatmentPlan: json['treatment_plan'],
      medications: json['medications'] is List ? json['medications'] : null,
      soapNote: json['soap_note'] is Map ? Map<String, dynamic>.from(json['soap_note']) : null,
      extractedData: json['extracted_data'] is Map ? Map<String, dynamic>.from(json['extracted_data']) : null,
      status: json['status'],
      createdAt: json['created_at'],
    );
  }

  String get diagnosisText {
    if (diagnosis is List) return (diagnosis as List).join(', ');
    if (diagnosis is String) return diagnosis;
    return '';
  }

  String get symptomsText {
    if (symptoms is List) {
      return (symptoms as List).map((s) {
        if (s is Map) return s['name'] ?? s.toString();
        return s.toString();
      }).join(', ');
    }
    if (symptoms is String) return symptoms;
    return '';
  }

  String get treatmentText {
    if (treatmentPlan is List) return (treatmentPlan as List).join(', ');
    if (treatmentPlan is String) return treatmentPlan;
    return '';
  }
}
