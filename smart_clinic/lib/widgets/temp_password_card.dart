import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/localization.dart';
import '../utils/ui_helpers.dart';

class TempPasswordCard extends StatelessWidget {
  final String tempPassword;
  final String? subtitle;
  final VoidCallback? onCreateAnother;

  const TempPasswordCard({
    super.key,
    required this.tempPassword,
    this.subtitle,
    this.onCreateAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF388E3C).withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF388E3C), size: 48),
            const SizedBox(height: 8),
            Text(AppLocalizations.tr('account_created'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              '${AppLocalizations.tr('temp_password')}: $tempPassword',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: tempPassword));
                showSuccessSnackBar(context, AppLocalizations.tr('copied'));
              },
              icon: const Icon(Icons.copy),
              label: Text(AppLocalizations.tr('copy_to_clipboard')),
            ),
            if (onCreateAnother != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onCreateAnother, child: Text(AppLocalizations.tr('register'))),
            ],
          ],
        ),
      ),
    );
  }
}
