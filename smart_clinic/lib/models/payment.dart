class Payment {
  final String? id;
  final String? appointmentId;
  final String? patientName;
  final String? doctorName;
  final double? amount;
  final String? method;
  final String? status;
  final String? date;
  final String? appointmentDate;
  final String? timeSlot;
  final String? createdAt;
  final String? proofUrl;
  final String? invoiceRef;
  final String? receptionistName;

  final String? refundReason;
  final String? refundStaffName;
  final String? refundedAt;
  final String? refundProofUrl;

  Payment({
    this.id,
    this.appointmentId,
    this.patientName,
    this.doctorName,
    this.amount,
    this.method,
    this.status,
    this.date,
    this.appointmentDate,
    this.timeSlot,
    this.createdAt,
    this.proofUrl,
    this.invoiceRef,
    this.receptionistName,
    this.refundReason,
    this.refundStaffName,
    this.refundedAt,
    this.refundProofUrl,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id']?.toString(),
      appointmentId: (json['appointment_id'] ?? json['appointment'])?.toString(),
      patientName: json['patient_name'],
      doctorName: json['doctor_name'],
      amount: json['amount'] != null ? double.tryParse(json['amount'].toString()) : null,
      method: json['method'] ?? json['payment_method'],
      status: json['payment_status'] ?? json['status'],
      date: json['date'] ?? json['appointment_date'],
      appointmentDate: json['appointment_date']?.toString(),
      timeSlot: json['time_slot']?.toString(),
      createdAt: json['created_at']?.toString(),
      proofUrl: json['proof_url'],
      invoiceRef: json['invoice_ref'],
      receptionistName: json['receptionist_name'],
      refundReason: json['refund_reason'],
      refundStaffName: json['refund_staff_name'],
      refundedAt: json['refunded_at']?.toString(),
      refundProofUrl: json['refund_proof_url'],
    );
  }
}
