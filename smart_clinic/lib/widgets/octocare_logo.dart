import 'package:flutter/material.dart';

class OctocareLogo extends StatelessWidget {
  final double height;

  const OctocareLogo({super.key, this.height = 140});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/octocare_logo.png',
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
