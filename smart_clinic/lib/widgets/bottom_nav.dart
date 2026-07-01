import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import '../config/routes.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final String role;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final items = _getItems();
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) => _onTap(context, index),
      items: items,
    );
  }

  List<BottomNavigationBarItem> _getItems() {
    switch (role) {
      case 'patient':
        return [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: AppLocalizations.tr('home')),
          BottomNavigationBarItem(icon: const Icon(Icons.calendar_today), label: AppLocalizations.tr('appointments')),
          BottomNavigationBarItem(icon: const Icon(Icons.smart_toy), label: AppLocalizations.tr('ai_assistant')),
          BottomNavigationBarItem(icon: const Icon(Icons.medical_information), label: AppLocalizations.tr('medical_records')),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: AppLocalizations.tr('profile')),
        ];
      case 'doctor':
        return [
          BottomNavigationBarItem(icon: const Icon(Icons.dashboard), label: AppLocalizations.tr('dashboard')),
          BottomNavigationBarItem(icon: const Icon(Icons.calendar_today), label: AppLocalizations.tr('appointments')),
          BottomNavigationBarItem(icon: const Icon(Icons.people), label: AppLocalizations.tr('patients')),
          BottomNavigationBarItem(icon: const Icon(Icons.smart_toy), label: AppLocalizations.tr('ai_assistant')),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: AppLocalizations.tr('profile')),
        ];
      case 'receptionist':
        return [
          BottomNavigationBarItem(icon: const Icon(Icons.dashboard), label: AppLocalizations.tr('dashboard')),
          BottomNavigationBarItem(icon: const Icon(Icons.calendar_today), label: AppLocalizations.tr('appointments')),
          BottomNavigationBarItem(icon: const Icon(Icons.queue), label: AppLocalizations.tr('queue')),
          BottomNavigationBarItem(icon: const Icon(Icons.payment), label: AppLocalizations.tr('payments')),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: AppLocalizations.tr('profile')),
        ];
      case 'admin':
        return [
          BottomNavigationBarItem(icon: const Icon(Icons.dashboard), label: AppLocalizations.tr('dashboard')),
          BottomNavigationBarItem(icon: const Icon(Icons.people), label: AppLocalizations.tr('users')),
          BottomNavigationBarItem(icon: const Icon(Icons.assessment), label: AppLocalizations.tr('reports')),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: AppLocalizations.tr('settings')),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: AppLocalizations.tr('profile')),
        ];
      default:
        return [];
    }
  }

  void _onTap(BuildContext context, int index) {
    String route;
    switch (role) {
      case 'patient':
        route = [AppRoutes.patientHome, AppRoutes.patientAppointments, AppRoutes.patientAi, AppRoutes.patientRecords, AppRoutes.patientProfile][index];
        break;
      case 'doctor':
        route = [AppRoutes.doctorHome, AppRoutes.doctorAppointments, AppRoutes.doctorPatients, AppRoutes.doctorAi, AppRoutes.doctorProfile][index];
        break;
      case 'receptionist':
        route = [AppRoutes.receptionistHome, AppRoutes.receptionistAppointments, AppRoutes.receptionistQueue, AppRoutes.receptionistPayments, AppRoutes.receptionistProfile][index];
        break;
      case 'admin':
        route = [AppRoutes.adminHome, AppRoutes.adminUsers, AppRoutes.adminReports, AppRoutes.adminSettings, AppRoutes.adminProfile][index];
        break;
      default:
        return;
    }
    Navigator.pushReplacementNamed(context, route);
  }
}
