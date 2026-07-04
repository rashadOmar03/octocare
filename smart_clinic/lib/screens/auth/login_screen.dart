import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/localization.dart';
import '../../config/routes.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/octocare_logo.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.pushReplacementNamed(context, auth.getPostAuthRoute());
    } else if (result['needs_verification'] == true) {
      final email = result['email']?.toString() ?? _emailController.text.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? AppLocalizations.tr('otp_sent'))),
      );
      Navigator.pushNamed(context, AppRoutes.verifyEmail, arguments: {'email': email});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? AppLocalizations.tr('error')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LangChip(
                              label: 'EN',
                              selected: !localeProvider.isArabic,
                              onTap: () => localeProvider.setLocale('en'),
                            ),
                            _LangChip(
                              label: 'عربي',
                              selected: localeProvider.isArabic,
                              onTap: () => localeProvider.setLocale('ar'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => themeProvider.toggleTheme(),
                        icon: Icon(
                          themeProvider.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        tooltip: themeProvider.isDarkMode
                            ? AppLocalizations.tr('light_mode')
                            : AppLocalizations.tr('dark_mode'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const OctocareLogo(height: 140),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.tr('app_name'),
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.tr('sign_in_continue'),
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  CustomTextField(
                    controller: _emailController,
                    label: AppLocalizations.tr('email'),
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.tr('field_required');
                      }
                      if (!value.contains('@')) {
                        return AppLocalizations.tr('invalid_email');
                      }
                      return null;
                    },
                  ),
                  CustomTextField(
                    controller: _passwordController,
                    label: AppLocalizations.tr('password'),
                    prefixIcon: Icons.lock_outlined,
                    obscureText: _obscurePassword,
                    suffix: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocalizations.tr('field_required');
                      }
                      if (value.length < 8) {
                        return AppLocalizations.tr('password_too_short');
                      }
                      return null;
                    },
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: _openForgotPassword,
                      child: Text(AppLocalizations.tr('forgot_password')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _login,
                      child: auth.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(AppLocalizations.tr('login')),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(AppLocalizations.tr('dont_have_account')),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.register),
                        child: Text(AppLocalizations.tr('sign_up')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
