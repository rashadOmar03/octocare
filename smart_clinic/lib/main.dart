import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/app_theme.dart';
import 'config/routes.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'services/api_service.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/profile_complete_screen.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/auth/verify_email_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/reset_password_screen.dart';

import 'screens/patient/patient_home_screen.dart';
import 'screens/patient/patient_appointments_screen.dart';
import 'screens/patient/book_appointment_screen.dart';
import 'screens/patient/patient_records_screen.dart';
import 'screens/patient/record_detail_screen.dart';
import 'screens/patient/patient_ai_screen.dart';
import 'screens/patient/patient_sensors_screen.dart';
import 'screens/patient/patient_profile_screen.dart';
import 'screens/patient/patient_reports_screen.dart';
import 'screens/patient/patient_review_screen.dart';
import 'screens/shared/prescription_detail_screen.dart';

import 'screens/doctor/doctor_home_screen.dart';
import 'screens/doctor/doctor_appointments_screen.dart';
import 'screens/doctor/doctor_patients_screen.dart';
import 'screens/doctor/doctor_patient_detail_screen.dart';
import 'screens/doctor/doctor_consultation_screen.dart';
import 'screens/doctor/doctor_ai_queue_screen.dart';
import 'screens/doctor/doctor_ai_screen.dart';
import 'screens/doctor/doctor_create_record_screen.dart';
import 'screens/doctor/doctor_create_prescription_screen.dart';
import 'screens/doctor/doctor_profile_screen.dart';
import 'screens/doctor/doctor_reports_screen.dart';
import 'screens/doctor/doctor_sensor_screen.dart';

import 'screens/receptionist/receptionist_home_screen.dart';
import 'screens/receptionist/receptionist_appointments_screen.dart';
import 'screens/receptionist/receptionist_queue_screen.dart';
import 'screens/receptionist/receptionist_payments_screen.dart';
import 'screens/receptionist/receptionist_register_patient_screen.dart';
import 'screens/receptionist/receptionist_profile_screen.dart';
import 'screens/receptionist/receptionist_reports_screen.dart';
import 'screens/receptionist/receptionist_book_appointment_screen.dart';
import 'widgets/role_guard.dart';

import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/admin_users_screen.dart';
import 'screens/admin/admin_create_doctor_screen.dart';
import 'screens/admin/admin_create_receptionist_screen.dart';
import 'screens/admin/admin_create_patient_screen.dart';
import 'screens/admin/admin_create_admin_screen.dart';
import 'screens/admin/admin_patient_detail_screen.dart';
import 'screens/admin/admin_specialties_screen.dart';
import 'screens/admin/admin_reports_screen.dart';
import 'screens/admin/admin_appointments_screen.dart';
import 'screens/admin/admin_prescriptions_screen.dart';
import 'screens/admin/admin_revenue_screen.dart';
import 'screens/admin/admin_settings_screen.dart';
import 'screens/admin/admin_profile_screen.dart';
import 'screens/shared/ai_chat_screen.dart';
import 'screens/shared/notifications_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authProvider = AuthProvider();
  final themeProvider = ThemeProvider();
  final localeProvider = LocaleProvider();

  await Future.wait([
    authProvider.init(),
    themeProvider.init(),
    localeProvider.init(),
  ]);

  final initialRoute = authProvider.isLoggedIn ? authProvider.getPostAuthRoute() : AppRoutes.login;

  if (authProvider.token != null) {
    ApiService.instance.setToken(authProvider.token!);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: localeProvider),
      ],
      child: SmartClinicApp(initialRoute: initialRoute),
    ),
  );
}

class SmartClinicApp extends StatelessWidget {
  final String initialRoute;

  const SmartClinicApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);

    return Directionality(
      textDirection: localeProvider.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: MaterialApp(
        title: 'Smart Clinic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeProvider.themeMode,
        locale: localeProvider.locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: initialRoute,
        routes: {
          AppRoutes.login: (_) => const LoginScreen(),
          AppRoutes.register: (_) => const RegisterScreen(),
          AppRoutes.profileComplete: (_) => const ProfileCompleteScreen(),
          AppRoutes.changePassword: (_) => const ChangePasswordScreen(),
          AppRoutes.verifyEmail: (ctx) {
            final args = ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>?;
            return VerifyEmailScreen(email: args?['email']?.toString() ?? '');
          },
          AppRoutes.forgotPassword: (_) => const ForgotPasswordScreen(),
          AppRoutes.resetPassword: (ctx) {
            final args = ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>?;
            return ResetPasswordScreen(email: args?['email']?.toString() ?? '');
          },

          // Patient
          AppRoutes.patientHome: (_) => const RoleGuard(requiredRole: 'patient', child: PatientHomeScreen()),
          AppRoutes.patientAppointments: (_) => const RoleGuard(requiredRole: 'patient', child: PatientAppointmentsScreen()),
          AppRoutes.patientBookAppointment: (_) => const RoleGuard(requiredRole: 'patient', child: BookAppointmentScreen()),
          AppRoutes.patientRecords: (_) => const RoleGuard(requiredRole: 'patient', child: PatientRecordsScreen()),
          AppRoutes.patientRecordDetail: (_) => const RoleGuard(requiredRole: 'patient', child: RecordDetailScreen()),
          AppRoutes.patientPrescriptionDetail: (_) => const RoleGuard(requiredRole: 'patient', child: PrescriptionDetailScreen()),
          AppRoutes.patientAi: (_) => const RoleGuard(requiredRole: 'patient', child: PatientAiScreen()),
          AppRoutes.patientSensors: (_) => const RoleGuard(requiredRole: 'patient', child: PatientSensorsScreen()),
          AppRoutes.patientNotifications: (_) => const RoleGuard(requiredRole: 'patient', child: NotificationsScreen()),
          AppRoutes.patientProfile: (_) => const RoleGuard(requiredRole: 'patient', child: PatientProfileScreen()),
          AppRoutes.patientReports: (_) => const RoleGuard(requiredRole: 'patient', child: PatientReportsScreen()),
          AppRoutes.patientReview: (_) => const RoleGuard(requiredRole: 'patient', child: PatientReviewScreen()),

          // Doctor
          AppRoutes.doctorHome: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorHomeScreen()),
          AppRoutes.doctorAppointments: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorAppointmentsScreen()),
          AppRoutes.doctorWaitingQueue: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorAppointmentsScreen(initialStatusFilter: 'arrived')),
          AppRoutes.doctorConfirmedToday: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorAppointmentsScreen(initialStatusFilter: 'confirmed')),
          AppRoutes.doctorPatients: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorPatientsScreen()),
          AppRoutes.doctorPatientDetail: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorPatientDetailScreen()),
          AppRoutes.doctorConsultation: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorConsultationScreen()),
          AppRoutes.doctorAiQueue: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorAiQueueScreen()),
          AppRoutes.doctorAi: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorAiScreen()),
          AppRoutes.doctorCreateRecord: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorConsultationScreen()),
          AppRoutes.doctorCreatePrescription: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorCreatePrescriptionScreen()),
          AppRoutes.doctorPrescriptionDetail: (_) => const RoleGuard(requiredRole: 'doctor', child: PrescriptionDetailScreen()),
          AppRoutes.doctorRecordDetail: (_) => const RoleGuard(requiredRole: 'doctor', child: RecordDetailScreen()),
          AppRoutes.doctorProfile: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorProfileScreen()),
          AppRoutes.doctorNotifications: (_) => const RoleGuard(requiredRole: 'doctor', child: NotificationsScreen()),
          AppRoutes.doctorSensors: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorSensorScreen()),
          AppRoutes.doctorReports: (_) => const RoleGuard(requiredRole: 'doctor', child: DoctorReportsScreen()),

          // Receptionist
          AppRoutes.receptionistHome: (_) => const RoleGuard(requiredRole: 'receptionist', child: ReceptionistHomeScreen()),
          AppRoutes.receptionistAppointments: (_) => const RoleGuard(requiredRole: 'receptionist', child: ReceptionistAppointmentsScreen()),
          AppRoutes.receptionistQueue: (_) => const RoleGuard(requiredRole: 'receptionist', child: ReceptionistQueueScreen()),
          AppRoutes.receptionistPayments: (_) => const RoleGuard(requiredRole: 'receptionist', child: ReceptionistPaymentsScreen()),
          AppRoutes.receptionistRegisterPatient: (_) => const RoleGuard(requiredRole: 'receptionist', child: ReceptionistRegisterPatientScreen()),
          AppRoutes.receptionistBookAppointment: (_) => const RoleGuard(requiredRole: 'receptionist', child: ReceptionistBookAppointmentScreen()),
          AppRoutes.receptionistProfile: (_) => const RoleGuard(requiredRole: 'receptionist', child: ReceptionistProfileScreen()),
          AppRoutes.receptionistReports: (_) => const RoleGuard(requiredRole: 'receptionist', child: ReceptionistReportsScreen()),
          AppRoutes.receptionistNotifications: (_) => const RoleGuard(requiredRole: 'receptionist', child: NotificationsScreen()),
          AppRoutes.receptionistAi: (_) => const RoleGuard(requiredRole: 'receptionist', child: AiChatScreen(role: 'receptionist')),

          // Admin
          AppRoutes.adminHome: (_) => const RoleGuard(requiredRole: 'admin', child: AdminHomeScreen()),
          AppRoutes.adminUsers: (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            final tab = args is Map ? (args['tab'] as int? ?? 0) : 0;
            return RoleGuard(requiredRole: 'admin', child: AdminUsersScreen(initialTab: tab));
          },
          AppRoutes.adminCreateDoctor: (_) => const RoleGuard(requiredRole: 'admin', child: AdminCreateDoctorScreen()),
          AppRoutes.adminCreateReceptionist: (_) => const RoleGuard(requiredRole: 'admin', child: AdminCreateReceptionistScreen()),
          AppRoutes.adminCreatePatient: (_) => const RoleGuard(requiredRole: 'admin', child: AdminCreatePatientScreen()),
          AppRoutes.adminCreateAdmin: (_) => const RoleGuard(requiredRole: 'admin', child: AdminCreateAdminScreen()),
          AppRoutes.adminPatientDetail: (_) => const RoleGuard(requiredRole: 'admin', child: AdminPatientDetailScreen()),
          AppRoutes.adminSpecialties: (_) => const RoleGuard(requiredRole: 'admin', child: AdminSpecialtiesScreen()),
          AppRoutes.adminReports: (_) => const RoleGuard(requiredRole: 'admin', child: AdminReportsScreen()),
          AppRoutes.adminAppointments: (_) => const RoleGuard(requiredRole: 'admin', child: AdminAppointmentsScreen()),
          AppRoutes.adminPrescriptions: (_) => const RoleGuard(requiredRole: 'admin', child: AdminPrescriptionsScreen()),
          AppRoutes.adminRevenue: (_) => const RoleGuard(requiredRole: 'admin', child: AdminRevenueScreen()),
          AppRoutes.adminPrescriptionDetail: (_) => const RoleGuard(requiredRole: 'admin', child: PrescriptionDetailScreen()),
          AppRoutes.adminSettings: (_) => const RoleGuard(requiredRole: 'admin', child: AdminSettingsScreen()),
          AppRoutes.adminProfile: (_) => const RoleGuard(requiredRole: 'admin', child: AdminProfileScreen()),
          AppRoutes.adminNotifications: (_) => const RoleGuard(requiredRole: 'admin', child: NotificationsScreen()),
          AppRoutes.adminAi: (_) => const RoleGuard(requiredRole: 'admin', child: AiChatScreen(role: 'admin')),
        },
      ),
    );
  }
}
