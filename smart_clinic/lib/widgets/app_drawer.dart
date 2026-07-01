import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/locale_provider.dart';
import '../l10n/localization.dart';
import '../config/routes.dart';
import 'user_avatar.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _avatarKey = GlobalKey<UserAvatarState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _avatarKey.currentState?.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final theme = Provider.of<ThemeProvider>(context);
    final locale = Provider.of<LocaleProvider>(context);
    final user = auth.currentUser;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            accountName: Text(user?.fullName ?? ''),
            accountEmail: Text(user?.email ?? ''),
            currentAccountPicture: UserAvatar(
              key: _avatarKey,
              name: user?.firstName,
              radius: 20,
            ),
          ),
          ..._buildMenuItems(context, auth.userRole),
          const Divider(),
          SwitchListTile(
            title: Text(AppLocalizations.tr('dark_mode')),
            value: theme.isDarkMode,
            onChanged: (_) => theme.toggleTheme(),
            secondary: const Icon(Icons.dark_mode),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(AppLocalizations.tr('language')),
            trailing: Text(locale.isArabic ? 'عربي' : 'EN'),
            onTap: () => locale.toggleLocale(),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(AppLocalizations.tr('change_password')),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.changePassword);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(
              AppLocalizations.tr('logout'),
              style: const TextStyle(color: Colors.red),
            ),
            onTap: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
              }
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context, String role) {
    switch (role) {
      case 'patient':
        return [
          _menuItem(context, Icons.home, 'home', AppRoutes.patientHome),
          _menuItem(context, Icons.calendar_today, 'appointments', AppRoutes.patientAppointments),
          _menuItem(context, Icons.smart_toy, 'ai_assistant', AppRoutes.patientAi),
          _menuItem(context, Icons.medical_information, 'medical_records', AppRoutes.patientRecords),
          _menuItem(context, Icons.sensors, 'sensors', AppRoutes.patientSensors),
          _menuItem(context, Icons.notifications, 'notifications', AppRoutes.patientNotifications),
          _menuItem(context, Icons.assessment, 'reports', AppRoutes.patientReports),
          _menuItem(context, Icons.person, 'profile', AppRoutes.patientProfile),
        ];
      case 'doctor':
        return [
          _menuItem(context, Icons.dashboard, 'dashboard', AppRoutes.doctorHome),
          _menuItem(context, Icons.calendar_today, 'appointments', AppRoutes.doctorAppointments),
          _menuItem(context, Icons.people, 'patients', AppRoutes.doctorPatients),
          _menuItem(context, Icons.smart_toy, 'ai_assistant', AppRoutes.doctorAi),
          _menuItem(context, Icons.auto_awesome, 'ai_suggestions', AppRoutes.doctorAiQueue),
          _menuItem(context, Icons.sensors, 'measure_vitals', AppRoutes.doctorSensors),
          _menuItem(context, Icons.assessment, 'reports', AppRoutes.doctorReports),
          _menuItem(context, Icons.notifications, 'notifications', AppRoutes.doctorNotifications),
          _menuItem(context, Icons.person, 'profile', AppRoutes.doctorProfile),
        ];
      case 'receptionist':
        return [
          _menuItem(context, Icons.dashboard, 'dashboard', AppRoutes.receptionistHome),
          _menuItem(context, Icons.calendar_today, 'appointments', AppRoutes.receptionistAppointments),
          _menuItem(context, Icons.queue, 'queue', AppRoutes.receptionistQueue),
          _menuItem(context, Icons.payment, 'payments', AppRoutes.receptionistPayments),
          _menuItem(context, Icons.person_add, 'register_patient', AppRoutes.receptionistRegisterPatient),
          _menuItem(context, Icons.assessment, 'reports', AppRoutes.receptionistReports),
          _menuItem(context, Icons.smart_toy, 'ai_assistant', AppRoutes.receptionistAi),
          _menuItem(context, Icons.notifications, 'notifications', AppRoutes.receptionistNotifications),
          _menuItem(context, Icons.person, 'profile', AppRoutes.receptionistProfile),
        ];
      case 'admin':
        return [
          _menuItem(context, Icons.dashboard, 'dashboard', AppRoutes.adminHome),
          _menuItem(context, Icons.people, 'users', AppRoutes.adminUsers),
          _menuItem(context, Icons.category, 'specialties', AppRoutes.adminSpecialties),
          _menuItem(context, Icons.assessment, 'reports', AppRoutes.adminReports),
          _menuItem(context, Icons.smart_toy, 'ai_assistant', AppRoutes.adminAi),
          _menuItem(context, Icons.notifications, 'notifications', AppRoutes.adminNotifications),
          _menuItem(context, Icons.settings, 'settings', AppRoutes.adminSettings),
          _menuItem(context, Icons.person, 'profile', AppRoutes.adminProfile),
        ];
      default:
        return [];
    }
  }

  Widget _menuItem(BuildContext context, IconData icon, String labelKey, String route) {
    return ListTile(
      leading: Icon(icon),
      title: Text(AppLocalizations.tr(labelKey)),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route);
      },
    );
  }
}
