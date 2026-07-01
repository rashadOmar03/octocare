import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../widgets/bottom_nav.dart';
import '../shared/chat_history_screen.dart';

class DoctorAiScreen extends StatelessWidget {
  const DoctorAiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatHistoryScreen(
        role: 'doctor',
        welcomeMessage: AppLocalizations.tr('doctor_ai_welcome'),
        showDisclaimer: true,
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 3, role: 'doctor'),
    );
  }
}
