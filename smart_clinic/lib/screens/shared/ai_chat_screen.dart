import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import 'chat_history_screen.dart';

class AiChatScreen extends StatelessWidget {
  final String role;
  const AiChatScreen({super.key, required this.role});

  String _welcomeMessage() {
    switch (role) {
      case 'admin':
        return AppLocalizations.tr('admin_ai_welcome');
      case 'receptionist':
        return AppLocalizations.tr('receptionist_ai_welcome');
      case 'doctor':
        return AppLocalizations.tr('doctor_ai_welcome');
      default:
        return AppLocalizations.tr('patient_ai_welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatHistoryScreen(
        role: role,
        welcomeMessage: _welcomeMessage(),
        showDisclaimer: role == 'patient',
      ),
    );
  }
}
