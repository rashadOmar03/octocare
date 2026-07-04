import 'package:flutter/material.dart';
import '../l10n/localization.dart';

class OctocareLogo extends StatelessWidget {
  final double height;
  final bool showOnDarkBackground;

  const OctocareLogo({
    super.key,
    this.height = 140,
    this.showOnDarkBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final image = Image.asset(
      'assets/images/octocare_logo.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.medical_services_outlined,
        size: height * 0.7,
        color: Theme.of(context).colorScheme.primary,
      ),
    );

    if (!showOnDarkBackground || !isDark) {
      return image;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: image,
    );
  }
}

class OctocareBrandHeader extends StatelessWidget {
  final double logoHeight;

  const OctocareBrandHeader({super.key, this.logoHeight = 140});

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
