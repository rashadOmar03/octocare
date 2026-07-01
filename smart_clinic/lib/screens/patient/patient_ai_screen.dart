import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../widgets/bottom_nav.dart';
import '../shared/chat_history_screen.dart';

class PatientAiScreen extends StatelessWidget {
  const PatientAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatHistoryScreen(
        role: 'patient',
        welcomeMessage: AppLocalizations.tr('patient_ai_welcome'),
        showDisclaimer: true,
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 2, role: 'patient'),
    );
  }
}
