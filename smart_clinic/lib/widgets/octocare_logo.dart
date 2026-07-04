import 'package:flutter/material.dart';
import '../l10n/localization.dart';

class OctocareLogo extends StatelessWidget {
  final double height;

  const OctocareLogo({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/octocare_mark.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.medical_services_outlined,
        size: height * 0.7,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class OctocareBrandHeader extends StatelessWidget {
  final double logoHeight;

  const OctocareBrandHeader({super.key, this.logoHeight = 120});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OctocareLogo(height: logoHeight),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.tr('app_name'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
