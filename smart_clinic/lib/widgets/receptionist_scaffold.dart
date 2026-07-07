import 'package:flutter/material.dart';
import '../l10n/localization.dart';
import '../config/routes.dart';
import 'app_drawer.dart';
import 'bottom_nav.dart';
import 'notification_icon.dart';

class ReceptionistScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final int? bottomNavIndex;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;
  final bool showNotifications;

  const ReceptionistScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottomNavIndex,
    this.actions,
    this.floatingActionButton,
    this.bottom,
    this.showNotifications = true,
  });

  @override
  Widget build(BuildContext context) {
    final appBarActions = <Widget>[
      ...?actions,
      if (showNotifications)
        NotificationIcon(
          iconColor: Colors.white,
          onPressed: () => Navigator.pushNamed(context, AppRoutes.receptionistNotifications),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: appBarActions,
        bottom: bottom,
      ),
      drawer: const AppDrawer(),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavIndex == null
          ? null
          : BottomNav(currentIndex: bottomNavIndex!, role: 'receptionist'),
    );
  }
}

Widget receptionistQuickActions(BuildContext context) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ActionChip(
        avatar: const Icon(Icons.person_add, size: 18),
        label: Text(AppLocalizations.tr('register_patient')),
        onPressed: () => Navigator.pushNamed(context, AppRoutes.receptionistRegisterPatient),
      ),
      ActionChip(
        avatar: const Icon(Icons.assessment, size: 18),
        label: Text(AppLocalizations.tr('reports')),
        onPressed: () => Navigator.pushNamed(context, AppRoutes.receptionistReports),
      ),
      ActionChip(
        avatar: const Icon(Icons.event_available, size: 18),
        label: Text(AppLocalizations.tr('book_appointment')),
        onPressed: () => Navigator.pushNamed(context, AppRoutes.receptionistBookAppointment),
      ),
    ],
  );
}
