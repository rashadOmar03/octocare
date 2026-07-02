import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import '../config/routes.dart';
import '../utils/responsive.dart';

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
    final theme = Theme.of(context);
    final selectedColor = theme.bottomNavigationBarTheme.selectedItemColor ?? theme.colorScheme.primary;
    final unselectedColor = theme.bottomNavigationBarTheme.unselectedItemColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final bg = theme.bottomNavigationBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final labelSize = Responsive.navLabelFontSize(context);
    final iconSize = Responsive.navIconSize(context);

    return Material(
      elevation: 8,
      color: bg,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: Responsive.isCompact(context) ? 62 : 68,
          child: Row(
            children: List.generate(items.length, (index) {
              final selected = index == currentIndex;
              final color = selected ? selectedColor : unselectedColor;
              return Expanded(
                child: InkWell(
                  onTap: () => _onTap(context, index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(items[index].icon, size: iconSize, color: color),
                        const SizedBox(height: 3),
                        Text(
                          items[index].label,
                          style: TextStyle(
                            fontSize: labelSize,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: color,
                            height: 1.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  List<_NavItem> _getItems() {
    switch (role) {
      case 'patient':
        return [
          _NavItem(Icons.home, AppLocalizations.tr('nav_home')),
          _NavItem(Icons.calendar_today, AppLocalizations.tr('nav_appts')),
          _NavItem(Icons.smart_toy, AppLocalizations.tr('nav_ai')),
          _NavItem(Icons.medical_information, AppLocalizations.tr('nav_records')),
          _NavItem(Icons.person, AppLocalizations.tr('nav_profile')),
        ];
      case 'doctor':
        return [
          _NavItem(Icons.dashboard, AppLocalizations.tr('nav_dashboard')),
          _NavItem(Icons.calendar_today, AppLocalizations.tr('nav_appts')),
          _NavItem(Icons.people, AppLocalizations.tr('nav_patients')),
          _NavItem(Icons.smart_toy, AppLocalizations.tr('nav_ai')),
          _NavItem(Icons.person, AppLocalizations.tr('nav_profile')),
        ];
      case 'receptionist':
        return [
          _NavItem(Icons.dashboard, AppLocalizations.tr('nav_dashboard')),
          _NavItem(Icons.calendar_today, AppLocalizations.tr('nav_appts')),
          _NavItem(Icons.queue, AppLocalizations.tr('nav_queue')),
          _NavItem(Icons.payment, AppLocalizations.tr('nav_payments')),
          _NavItem(Icons.person, AppLocalizations.tr('nav_profile')),
        ];
      case 'admin':
        return [
          _NavItem(Icons.dashboard, AppLocalizations.tr('nav_dashboard')),
          _NavItem(Icons.people, AppLocalizations.tr('nav_users')),
          _NavItem(Icons.assessment, AppLocalizations.tr('nav_reports')),
          _NavItem(Icons.settings, AppLocalizations.tr('nav_settings')),
          _NavItem(Icons.person, AppLocalizations.tr('nav_profile')),
        ];
      default:
        return [];
    }
  }

  void _onTap(BuildContext context, int index) {
    String route;
    switch (role) {
      case 'patient':
        route = [
          AppRoutes.patientHome,
          AppRoutes.patientAppointments,
          AppRoutes.patientAi,
          AppRoutes.patientRecords,
          AppRoutes.patientProfile,
        ][index];
        break;
      case 'doctor':
        route = [
          AppRoutes.doctorHome,
          AppRoutes.doctorAppointments,
          AppRoutes.doctorPatients,
          AppRoutes.doctorAi,
          AppRoutes.doctorProfile,
        ][index];
        break;
      case 'receptionist':
        route = [
          AppRoutes.receptionistHome,
          AppRoutes.receptionistAppointments,
          AppRoutes.receptionistQueue,
          AppRoutes.receptionistPayments,
          AppRoutes.receptionistProfile,
        ][index];
        break;
      case 'admin':
        route = [
          AppRoutes.adminHome,
          AppRoutes.adminUsers,
          AppRoutes.adminReports,
          AppRoutes.adminSettings,
          AppRoutes.adminProfile,
        ][index];
        break;
      default:
        return;
    }
    Navigator.pushReplacementNamed(context, route);
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}
