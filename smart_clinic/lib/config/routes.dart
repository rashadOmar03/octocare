class AppRoutes {
  static const String login = '/login';
  static const String register = '/register';
  static const String profileComplete = '/profile-complete';
  static const String changePassword = '/change-password';
  static const String verifyEmail = '/verify-email';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  // Patient routes
  static const String patientHome = '/patient/home';
  static const String patientAppointments = '/patient/appointments';
  static const String patientBookAppointment = '/patient/book-appointment';
  static const String patientRecords = '/patient/records';
  static const String patientRecordDetail = '/patient/record-detail';
  static const String patientPrescriptionDetail = '/patient/prescription-detail';
  static const String patientAi = '/patient/ai';
  static const String patientSensors = '/patient/sensors';
  static const String patientNotifications = '/patient/notifications';
  static const String patientProfile = '/patient/profile';
  static const String patientReports = '/patient/reports';
  static const String patientReview = '/patient/review';

  // Doctor routes
  static const String doctorHome = '/doctor/home';
  static const String doctorAppointments = '/doctor/appointments';
  static const String doctorWaitingQueue = '/doctor/waiting-queue';
  static const String doctorConfirmedToday = '/doctor/confirmed-today';
  static const String doctorPatients = '/doctor/patients';
  static const String doctorPatientDetail = '/doctor/patient-detail';
  static const String doctorConsultation = '/doctor/consultation';
  static const String doctorAiQueue = '/doctor/ai-queue';
  static const String doctorAi = '/doctor/ai';
  static const String doctorCreateRecord = '/doctor/records/create';
  static const String doctorCreatePrescription = '/doctor/prescriptions/create';
  static const String doctorPrescriptionDetail = '/doctor/prescription-detail';
  static const String doctorRecordDetail = '/doctor/record-detail';
  static const String doctorProfile = '/doctor/profile';
  static const String doctorNotifications = '/doctor/notifications';
  static const String doctorSensors = '/doctor/sensors';
  static const String doctorReports = '/doctor/reports';

  // Receptionist routes
  static const String receptionistHome = '/receptionist/home';
  static const String receptionistAppointments = '/receptionist/appointments';
  static const String receptionistQueue = '/receptionist/queue';
  static const String receptionistPayments = '/receptionist/payments';
  static const String receptionistRegisterPatient = '/receptionist/register-patient';
  static const String receptionistBookAppointment = '/receptionist/book-appointment';
  static const String receptionistProfile = '/receptionist/profile';
  static const String receptionistNotifications = '/receptionist/notifications';
  static const String receptionistRecordDetail = '/receptionist/record-detail';
  static const String receptionistReports = '/receptionist/reports';

  // Admin routes
  static const String adminHome = '/admin/home';
  static const String adminUsers = '/admin/users';
  static const String adminCreateDoctor = '/admin/doctors/create';
  static const String adminCreateReceptionist = '/admin/receptionists/create';
  static const String adminCreatePatient = '/admin/patients/create';
  static const String adminCreateAdmin = '/admin/admins/create';
  static const String adminPatientDetail = '/admin/patient-detail';
  static const String adminSpecialties = '/admin/specialties';
  static const String adminReports = '/admin/reports';
  static const String adminAppointments = '/admin/appointments';
  static const String adminPrescriptions = '/admin/prescriptions';
  static const String adminRevenue = '/admin/revenue';
  static const String adminPrescriptionDetail = '/admin/prescription-detail';
  static const String adminSettings = '/admin/settings';
  static const String adminProfile = '/admin/profile';
  static const String adminAi = '/admin/ai';
  static const String adminNotifications = '/admin/notifications';

  // Receptionist AI
  static const String receptionistAi = '/receptionist/ai';
}
