import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../config/routes.dart';

class RoleGuard extends StatelessWidget {
  final String requiredRole;
  final Widget child;

  const RoleGuard({super.key, required this.requiredRole, required this.child});

  bool _roleAllowed(String actual, String required) {
    if (actual == required) return true;
    if (required == 'receptionist' && actual == 'admin') return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (!auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_roleAllowed(auth.userRole, requiredRole)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, auth.getHomeRoute());
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return child;
  }
}
