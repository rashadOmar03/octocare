class ClinicSettings {
  final String? clinicName;
  final String? address;
  final String? phone;
  final String? email;
  final double? defaultFee;
  final String? workingHoursStart;
  final String? workingHoursEnd;
  final List<String>? workingDays;
  final bool? notificationsEnabled;
  final bool? smsEnabled;
  final bool? emailEnabled;

  ClinicSettings({
    this.clinicName,
    this.address,
    this.phone,
    this.email,
    this.defaultFee,
    this.workingHoursStart,
    this.workingHoursEnd,
    this.workingDays,
    this.notificationsEnabled,
    this.smsEnabled,
    this.emailEnabled,
  });

  factory ClinicSettings.fromJson(Map<String, dynamic> json) {
    return ClinicSettings(
      clinicName: json['clinic_name'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      defaultFee: json['default_fee'] != null ? double.tryParse(json['default_fee'].toString()) : null,
      workingHoursStart: json['working_hours_start'],
      workingHoursEnd: json['working_hours_end'],
      workingDays: json['working_days'] != null ? List<String>.from(json['working_days']) : null,
      notificationsEnabled: json['notifications_enabled'],
      smsEnabled: json['sms_enabled'],
      emailEnabled: json['email_enabled'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clinic_name': clinicName,
      'address': address,
      'phone': phone,
      'email': email,
      'default_fee': defaultFee,
      'working_hours_start': workingHoursStart,
      'working_hours_end': workingHoursEnd,
      'working_days': workingDays,
      'notifications_enabled': notificationsEnabled,
      'sms_enabled': smsEnabled,
      'email_enabled': emailEnabled,
    };
  }
}
